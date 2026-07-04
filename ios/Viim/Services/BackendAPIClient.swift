import CoreLocation
import Foundation

enum BackendAPIError: Error {
    case invalidURL
    case invalidResponse
    case invalidPayload
    case serverStatus(Int)
}

final class BackendAPIClient {
    static let shared = BackendAPIClient()

    private let baseURL = URL(string: "https://api.burktech-ia.com/v1")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func sendAlertTest(contact: EmergencyContact, driverName: String?) async throws {
        guard let normalizedContact = contact.normalizedForBurkina else {
            throw BackendAPIError.invalidPayload
        }
        let payload = AlertTestPayload(
            driverName: driverName,
            contact: AlertContactPayload(normalizedContact)
        )
        try await post(payload, path: "alerts/test")
    }

    func shareLocation(
        contact: EmergencyContact,
        driverName: String?,
        location: CLLocation
    ) async throws {
        guard let normalizedContact = contact.normalizedForBurkina else {
            throw BackendAPIError.invalidPayload
        }
        let payload = LocationSharePayload(
            driverName: driverName,
            contact: AlertContactPayload(normalizedContact),
            location: AlertLocationPayload(location)
        )
        try await post(payload, path: "alerts/location-share")
    }

    private func post<Payload: Encodable>(_ payload: Payload, path: String) async throws {
        guard let url = baseURL?.appending(path: path) else {
            throw BackendAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw BackendAPIError.serverStatus(httpResponse.statusCode)
        }
    }
}

private struct AlertContactPayload: Encodable {
    let name: String
    let phoneNumber: String

    init(_ contact: EmergencyContact) {
        name = contact.name
        phoneNumber = contact.phoneNumber
    }
}

private struct AlertLocationPayload: Encodable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        accuracyMeters = location.horizontalAccuracy
    }
}

private struct AlertTestPayload: Encodable {
    let driverName: String?
    let contact: AlertContactPayload
}

private struct LocationSharePayload: Encodable {
    let driverName: String?
    let contact: AlertContactPayload
    let location: AlertLocationPayload
}
