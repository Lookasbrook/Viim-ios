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
            try await client.sendAlertTest(contact: EmergencyContact(name: "Contact", phoneNumber: "+22670000000"), driverName: "Guy")
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
            try await client.sendAlertTest(contact: EmergencyContact(name: "Contact", phoneNumber: "+22670000000"), driverName: "Guy")
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
            try await client.sendAlertTest(contact: EmergencyContact(name: "Contact", phoneNumber: "+22670000000"), driverName: "Guy")
            XCTFail("Expected BackendAPIError.network")
        } catch let error as BackendAPIError {
            XCTAssertEqual(error, .network(.notConnectedToInternet))
        }
    }

    func testOfficialFuelPriceUsesOnlyCoarseLocalityAndDecodesEvidence() async throws {
        let client = makeClient { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            XCTAssertEqual(components.path, "/v1/fuel-prices/current")
            XCTAssertEqual(query["country"], "CA")
            XCTAssertEqual(query["region"], "ON")
            XCTAssertEqual(query["locality"], "Toronto")
            XCTAssertEqual(query["fuelType"], "gasoline")
            XCTAssertNil(query["latitude"])
            XCTAssertNil(query["longitude"])
            return self.httpResponse(
                for: request,
                statusCode: 200,
                body: #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"}"#
            )
        }

        let quote = try await client.fetchOfficialFuelPrice(
            countryCode: "CA",
            regionCode: "ON",
            locality: "Toronto",
            fuelType: .gasoline
        )

        XCTAssertEqual(quote.pricePerLiter, 1.55)
        XCTAssertEqual(quote.currency, .cad)
        XCTAssertEqual(quote.source, "government_of_ontario_fuel_price_survey")
        XCTAssertEqual(quote.sourceURL.scheme, "https")
    }

    func testOfficialFuelPricePreservesBackendErrorCode() async throws {
        let client = makeClient { request in
            self.httpResponse(
                for: request,
                statusCode: 404,
                body: #"{"error":"fuel_price_unavailable"}"#
            )
        }

        do {
            _ = try await client.fetchOfficialFuelPrice(
                countryCode: "BF",
                regionCode: "KADIOGO",
                locality: "Ouagadougou",
                fuelType: .gasoline
            )
            XCTFail("Expected BackendAPIError.apiStatus")
        } catch let error as BackendAPIError {
            XCTAssertEqual(error, .apiStatus(statusCode: 404, code: "fuel_price_unavailable"))
        }
    }

    func testOfficialFuelPriceMapsOfflineTransportToNetworkError() async throws {
        let client = makeClient { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await client.fetchOfficialFuelPrice(
                countryCode: "CA",
                regionCode: "ON",
                locality: "Toronto",
                fuelType: .gasoline
            )
            XCTFail("Expected BackendAPIError.network")
        } catch let error as BackendAPIError {
            XCTAssertEqual(error, .network(.notConnectedToInternet))
        }
    }

    func testOfficialFuelPriceRejectsUntrustedOrMalformedEvidence() async throws {
        let invalidBodies = [
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"http://example.com/fuel.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":-1,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/fuel.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"not-a-date","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/fuel.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"hydrogen","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/fuel.csv"}"#,
            #"{"countryCode":"US","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/fuel.csv"}"#,
            #"{"countryCode":"CA","regionCode":"QC","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/fuel.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"untrusted","sourceUrl":"https://www.ontario.ca/fuel.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://example.com/fuel.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"diesel","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"USD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":5.01,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-01T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-04T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"}"#,
            #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv?download=1"}"#
        ]

        for body in invalidBodies {
            let client = makeClient { request in
                self.httpResponse(for: request, statusCode: 200, body: body)
            }
            do {
                _ = try await client.fetchOfficialFuelPrice(
                    countryCode: "CA",
                    regionCode: "ON",
                    locality: "Toronto",
                    fuelType: .gasoline,
                    now: Date(timeIntervalSince1970: 1_788_409_800)
                )
                XCTFail("Expected BackendAPIError.invalidResponse for \(body)")
            } catch let error as BackendAPIError {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
    }

    func testOfficialFuelPriceRejectsUntrustedTransportEvidence() async throws {
        let body = #"{"countryCode":"CA","regionCode":"ON","locality":"Toronto","fuelType":"gasoline","pricePerLiter":1.55,"currency":"CAD","observedAt":"2026-08-31T00:00:00.000Z","retrievedAt":"2026-09-02T12:00:00.000Z","source":"government_of_ontario_fuel_price_survey","sourceUrl":"https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"}"#
        let cases: [(URL?, String, String)] = [
            (URL(string: "https://attacker.example/v1/fuel-prices/current"), "application/json", body),
            (nil, "text/html", body),
            (nil, "application/json", String(repeating: "x", count: 128_001))
        ]

        for (responseURL, contentType, responseBody) in cases {
            let client = makeClient { request in
                self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: responseBody,
                    responseURL: responseURL,
                    contentType: contentType
                )
            }
            do {
                _ = try await client.fetchOfficialFuelPrice(
                    countryCode: "CA",
                    regionCode: "ON",
                    locality: "Toronto",
                    fuelType: .gasoline
                )
                XCTFail("Expected transport evidence rejection")
            } catch let error as BackendAPIError {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
    }

    func testOfficialFuelPriceRejectsInvalidCoarseLocationBeforeNetworking() async throws {
        let client = makeClient { _ in
            XCTFail("Invalid location must not reach the network")
            throw URLError(.badURL)
        }

        do {
            _ = try await client.fetchOfficialFuelPrice(
                countryCode: "CA",
                regionCode: "ON",
                locality: "Toronto\nlatitude=1",
                fuelType: .gasoline
            )
            XCTFail("Expected BackendAPIError.invalidURL")
        } catch let error as BackendAPIError {
            XCTAssertEqual(error, .invalidURL)
        }
    }

    func testOntarioPublicFuelPriceReadsOfficialCSVLocally() async throws {
        let csv = """
        Date,Toronto West/Ouest,Toronto East/Est,Ontario Average/Moyenne provinciale,Fuel Type,,
        2026-08-25,140.0,142.0,145.0,Regular Unleaded Gasoline,,
        2026-09-01,150.0,152.0,155.0,Regular Unleaded Gasoline,,
        2026-09-01,160.0,162.0,165.0,Diesel,,
        """
        let session = makeSession { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/csv")
            XCTAssertNil(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.query)
            return self.httpResponse(
                for: request,
                statusCode: 200,
                body: csv,
                responseURL: URL(string: "https://prod-energy-fuel-prices.s3.amazonaws.com/fueltypesall.csv"),
                contentType: "text/csv"
            )
        }
        let client = OntarioPublicFuelPriceClient(session: session)
        let now = Date(timeIntervalSince1970: 1_788_409_800)

        let quote = try await client.fetchCurrentPrice(
            countryCode: "CA",
            regionCode: "Ontario",
            locality: "Toronto",
            fuelType: .gasoline,
            now: now
        )

        XCTAssertEqual(quote.pricePerLiter, 1.51, accuracy: 0.000_1)
        XCTAssertEqual(quote.locality, "Toronto")
        XCTAssertEqual(quote.currency, .cad)
        XCTAssertEqual(quote.fuelType, .gasoline)
        XCTAssertEqual(quote.sourceURL.absoluteString, "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv")
    }

    func testOntarioPublicFuelPriceFallsBackToProvincialAverage() async throws {
        let csv = """
        Date,Ontario Average/Moyenne provinciale,Fuel Type
        2026-09-01,155.4,Regular Unleaded Gasoline
        """
        let client = OntarioPublicFuelPriceClient(session: makeSession { request in
            self.httpResponse(
                for: request,
                statusCode: 200,
                body: csv,
                responseURL: URL(string: "https://prod-energy-fuel-prices.s3.amazonaws.com/fueltypesall.csv"),
                contentType: "text/csv"
            )
        })

        let quote = try await client.fetchCurrentPrice(
            countryCode: "CA",
            regionCode: "ON",
            locality: "Kingston",
            fuelType: .gasoline,
            now: Date(timeIntervalSince1970: 1_788_409_800)
        )

        XCTAssertEqual(quote.pricePerLiter, 1.554, accuracy: 0.000_1)
        XCTAssertEqual(quote.locality, "Ontario")
    }

    func testOntarioPublicFuelPriceRejectsUntrustedRedirectAndStaleDataset() async throws {
        let staleCSV = """
        Date,Ontario Average/Moyenne provinciale,Fuel Type
        2026-07-01,155.4,Regular Unleaded Gasoline
        """
        let cases = [
            (URL(string: "https://attacker.example/fueltypesall.csv"), "2026-09-01"),
            (URL(string: "https://prod-energy-fuel-prices.s3.amazonaws.com/fueltypesall.csv"), "2026-07-01")
        ]

        for (responseURL, date) in cases {
            let body = staleCSV.replacingOccurrences(of: "2026-07-01", with: date)
            let client = OntarioPublicFuelPriceClient(session: makeSession { request in
                self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: body,
                    responseURL: responseURL,
                    contentType: "text/csv"
                )
            })
            do {
                _ = try await client.fetchCurrentPrice(
                    countryCode: "CA",
                    regionCode: "ON",
                    locality: "Toronto",
                    fuelType: .gasoline,
                    now: Date(timeIntervalSince1970: 1_788_409_800)
                )
                XCTFail("Expected official CSV rejection")
            } catch let error as BackendAPIError {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
    }

    func testFuelEconomyVariantsUseAnExactEncodedVehicleQuery() async throws {
        let session = makeSession { request in
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            XCTAssertEqual(components.scheme, "https")
            XCTAssertEqual(components.host, "www.fueleconomy.gov")
            XCTAssertEqual(components.path, "/ws/rest/vehicle/menu/options")
            XCTAssertEqual(query, ["year": "2024", "make": "Toyota", "model": "Corolla"])
            XCTAssertNil(query["latitude"])
            XCTAssertNil(query["longitude"])
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            return self.httpResponse(
                for: request,
                statusCode: 200,
                body: #"{"menuItem":[{"text":"Auto (AV-S10), 4 cyl, 2.0 L, SIDI & PFI","value":"47343"},{"text":"Auto (AV-S10), 4 cyl, 2.0 L, 3-mode","value":"47344"}]}"#
            )
        }
        let client = FuelEconomyVehicleClient(session: session)

        let variants = try await client.fetchVariants(year: 2024, make: "Toyota", model: "Corolla")

        XCTAssertEqual(variants.map(\.recordID), ["47343", "47344"])
        XCTAssertEqual(variants.first?.description, "Auto (AV-S10), 4 cyl, 2.0 L, SIDI & PFI")
    }

    func testFuelEconomyVehicleCreatesExactAuditableSpecification() async throws {
        let retrievedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let session = makeSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://www.fueleconomy.gov/ws/rest/vehicle/47343")
            return self.httpResponse(
                for: request,
                statusCode: 200,
                body: #"{"id":"47343","year":"2024","make":"Toyota","model":"Corolla","baseModel":"Corolla","fuelType1":"Regular Gasoline","atvType":"","city08":"32","highway08":"41","comb08":"35","cylinders":"4","displ":"2.0","eng_dscr":"SIDI & PFI","trany":"Automatic (AV-S10)","modifiedOn":"2024-01-18T00:00:00-05:00"}"#
            )
        }
        let client = FuelEconomyVehicleClient(session: session)
        let variant = FuelEconomyVehicleVariant(
            recordID: "47343",
            description: "Auto (AV-S10), 4 cyl, 2.0 L, SIDI & PFI"
        )

        let specification = try await client.fetchSpecification(
            variant: variant,
            expectedYear: 2024,
            expectedMake: "Toyota",
            expectedModel: "Corolla",
            retrievedAt: retrievedAt
        )

        XCTAssertEqual(specification.sourceIdentifier, "fueleconomy.gov.vehicle")
        XCTAssertEqual(specification.sourceRecordID, "47343")
        XCTAssertEqual(specification.fuelType, .gasoline)
        XCTAssertEqual(specification.transmission, "Automatic (AV-S10)")
        XCTAssertEqual(specification.engineDescription, "2.0 L · 4 cyl · SIDI & PFI")
        XCTAssertEqual(specification.combinedLitersPer100Km, 235.214583 / 35, accuracy: 0.000_001)
        XCTAssertEqual(specification.retrievedAt, retrievedAt)
        XCTAssertTrue(specification.hasTrustedEvidence)
    }

    func testFuelEconomyVehicleRejectsMismatchedIdentityAndUntrustedRedirect() async throws {
        let validBody = #"{"id":"47343","year":"2024","make":"Toyota","model":"Camry","baseModel":"Camry","fuelType1":"Regular Gasoline","atvType":"","city08":"32","highway08":"41","comb08":"35","cylinders":"4","displ":"2.0","eng_dscr":"","trany":"Automatic","modifiedOn":"2024-01-18T00:00:00-05:00"}"#
        let mismatchedClient = FuelEconomyVehicleClient(session: makeSession { request in
            self.httpResponse(for: request, statusCode: 200, body: validBody)
        })
        let variant = FuelEconomyVehicleVariant(recordID: "47343", description: "Automatic")

        do {
            _ = try await mismatchedClient.fetchSpecification(
                variant: variant,
                expectedYear: 2024,
                expectedMake: "Toyota",
                expectedModel: "Corolla"
            )
            XCTFail("Expected identity mismatch to be rejected")
        } catch let error as PublicVehicleCatalogError {
            XCTAssertEqual(error, .identityMismatch)
        }

        let redirectedClient = FuelEconomyVehicleClient(session: makeSession { request in
            self.httpResponse(
                for: request,
                statusCode: 200,
                body: validBody,
                responseURL: URL(string: "https://example.com/ws/rest/vehicle/47343")
            )
        })
        do {
            _ = try await redirectedClient.fetchSpecification(
                variant: variant,
                expectedYear: 2024,
                expectedMake: "Toyota",
                expectedModel: "Camry"
            )
            XCTFail("Expected untrusted response URL to be rejected")
        } catch let error as PublicVehicleCatalogError {
            XCTAssertEqual(error, .untrustedResponse)
        }
    }

    func testFuelEconomyVehicleRejectsOversizedResponse() async throws {
        let oversized = String(repeating: "x", count: FuelEconomyVehicleClient.maximumResponseBytes + 1)
        let client = FuelEconomyVehicleClient(session: makeSession { request in
            self.httpResponse(for: request, statusCode: 200, body: oversized)
        })

        do {
            _ = try await client.fetchVariants(year: 2024, make: "Toyota", model: "Corolla")
            XCTFail("Expected oversized response to be rejected")
        } catch let error as PublicVehicleCatalogError {
            XCTAssertEqual(error, .responseTooLarge)
        }
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> BackendAPIClient {
        BackendAPIClient(session: makeSession(handler: handler))
    }

    private func makeSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        URLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func httpResponse(
        for request: URLRequest,
        statusCode: Int,
        body: String,
        responseURL: URL? = nil,
        contentType: String = "application/json"
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: responseURL ?? request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
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
