import CoreLocation
import Foundation
import XCTest
@testable import Viim

final class BurkinaPhoneNumberTests: XCTestCase {
    func testNormalizesSpacedE164PhoneNumber() {
        XCTAssertEqual(BurkinaPhoneNumber.normalize("+226 70 00 00 00"), "+22670000000")
    }

    func testNormalizesLocalPhoneNumber() {
        XCTAssertEqual(BurkinaPhoneNumber.normalize("70 00 00 00"), "+22670000000")
    }

    func testNormalizesInternationalPrefixPhoneNumber() {
        XCTAssertEqual(BurkinaPhoneNumber.normalize("00226 70 00 00 00"), "+22670000000")
    }

    func testAcceptsInternationalPhoneNumbers() {
        XCTAssertEqual(BurkinaPhoneNumber.normalize("+2250700000000"), "+2250700000000")
        XCTAssertEqual(BurkinaPhoneNumber.normalize("+1 514 123 4567"), "+15141234567")
        XCTAssertEqual(BurkinaPhoneNumber.normalize("+33 6 12 34 56 78"), "+33612345678")
        XCTAssertEqual(BurkinaPhoneNumber.normalize("001 514 123 4567"), "+15141234567")
    }

    func testRejectsIncompleteBurkinaPhoneNumber() {
        XCTAssertNil(BurkinaPhoneNumber.normalize("+2267000000"))
    }

    func testRejectsImplausibleNumbers() {
        XCTAssertNil(BurkinaPhoneNumber.normalize(""))
        XCTAssertNil(BurkinaPhoneNumber.normalize("1234"))
        XCTAssertNil(BurkinaPhoneNumber.normalize("+0 123 456 789"))
        XCTAssertNil(BurkinaPhoneNumber.normalize("bonjour"))
        XCTAssertNil(BurkinaPhoneNumber.normalize("+1234567890123456"))
    }

    func testNormalizedContactTrimsNameAndFixesNumber() {
        let contact = EmergencyContact(name: "  Awa  ", phoneNumber: "70 12 34 56")
        let normalized = BurkinaPhoneNumber.normalizedContact(contact)

        XCTAssertEqual(normalized?.name, "Awa")
        XCTAssertEqual(normalized?.phoneNumber, "+22670123456")

        let unnamed = EmergencyContact(name: "   ", phoneNumber: "70 12 34 56")
        XCTAssertNil(BurkinaPhoneNumber.normalizedContact(unnamed))
    }
}

final class BackendAPIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testInvalidContactResponseKeepsErrorCode() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.burktech-ia.com/v1/alerts/test")
            return self.httpResponse(
                for: request,
                statusCode: 422,
                body: #"{"error":"invalid_contact"}"#
            )
        }

        do {
            try await client.sendAlertTest(contact: EmergencyContact(name: "Contact", phoneNumber: "+22670000000"), driverName: "Guy", contactsConsent: true)
            XCTFail("Expected BackendAPIError.apiStatus")
        } catch let error as BackendAPIError {
            XCTAssertEqual(error, .apiStatus(statusCode: 422, code: "invalid_contact"))
        }
    }

    func testProviderUnavailableResponseKeepsErrorCode() async throws {
        let client = makeClient { request in
            self.httpResponse(
                for: request,
                statusCode: 503,
                body: #"{"error":"newagent_unavailable"}"#
            )
        }

        do {
            try await client.sendAlertTest(contact: EmergencyContact(name: "Contact", phoneNumber: "+22670000000"), driverName: "Guy", contactsConsent: true)
            XCTFail("Expected BackendAPIError.apiStatus")
        } catch let error as BackendAPIError {
            XCTAssertEqual(error, .apiStatus(statusCode: 503, code: "newagent_unavailable"))
        }
    }

    func testOfflineTransportMapsToNetworkError() async throws {
        let client = makeClient { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            try await client.sendAlertTest(contact: EmergencyContact(name: "Contact", phoneNumber: "+22670000000"), driverName: "Guy", contactsConsent: true)
            XCTFail("Expected BackendAPIError.network")
        } catch let error as BackendAPIError {
            XCTAssertEqual(error, .network(.notConnectedToInternet))
        }
    }

    func testCollisionAlertSendsAllContactsAndConsentTrue() async throws {
        var captured: Data?
        let client = makeClient { request in
            captured = request.bodyData
            XCTAssertEqual(request.url?.absoluteString, "https://api.burktech-ia.com/v1/alerts/collision")
            return self.httpResponse(
                for: request,
                statusCode: 200,
                body: #"{"status":"sent","incidentId":"abc","sentCount":1}"#
            )
        }

        let contacts = [
            EmergencyContact(name: "Awa", phoneNumber: "+22670000001", consentAcknowledgedAt: Date()),
            EmergencyContact(name: "Boris", phoneNumber: "+22670000002", consentAcknowledgedAt: Date())
        ]
        try await client.sendCollisionAlert(
            contacts: contacts,
            driverName: "Guy",
            location: CLLocation(latitude: 12.3718, longitude: -1.5196),
            medicalProfile: nil
        )

        let json = try XCTUnwrap(
            captured.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        )
        XCTAssertEqual(json["contactsConsent"] as? Bool, true)
        XCTAssertNotNil(json["occurredAt"])
        XCTAssertNil(json["medicalProfile"])
        let sentContacts = try XCTUnwrap(json["contacts"] as? [[String: Any]])
        XCTAssertEqual(sentContacts.count, 2)
        XCTAssertEqual(sentContacts.first?["phoneNumber"] as? String, "+22670000001")
        let location = try XCTUnwrap(json["location"] as? [String: Any])
        XCTAssertEqual(location["latitude"] as? Double, 12.3718)
    }

    func testCollisionAlertConsentFalseWhenAContactHasNoConsent() async throws {
        var captured: Data?
        let client = makeClient { request in
            captured = request.bodyData
            return self.httpResponse(
                for: request,
                statusCode: 200,
                body: #"{"status":"sent","incidentId":"abc","sentCount":1}"#
            )
        }

        let contacts = [
            EmergencyContact(name: "Awa", phoneNumber: "+22670000001", consentAcknowledgedAt: Date()),
            EmergencyContact(name: "Boris", phoneNumber: "+22670000002", consentAcknowledgedAt: nil)
        ]
        try await client.sendCollisionAlert(
            contacts: contacts,
            driverName: nil,
            location: CLLocation(latitude: 12.3718, longitude: -1.5196),
            medicalProfile: nil
        )

        let json = try XCTUnwrap(
            captured.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        )
        XCTAssertEqual(json["contactsConsent"] as? Bool, false)
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> BackendAPIClient {
        URLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return BackendAPIClient(session: URLSession(configuration: configuration))
    }

    private func httpResponse(
        for request: URLRequest,
        statusCode: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// URLSession livre le corps des requetes stubbees via `httpBodyStream`,
    /// pas `httpBody` : cette lecture rend le JSON envoye inspectable en test.
    var bodyData: Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
