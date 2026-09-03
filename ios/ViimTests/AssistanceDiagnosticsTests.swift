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

    func testOfficialFuelPriceRejectsUnsupportedCountryBeforeNetworking() async throws {
        let client = makeClient { _ in
            XCTFail("Une localite sans contrat public ne doit pas atteindre le reseau")
            throw URLError(.badURL)
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

    func testOfficialFuelPricePreservesBackendErrorCodeForQualifiedMarket() async throws {
        let client = makeClient { request in
            self.httpResponse(
                for: request,
                statusCode: 503,
                body: #"{"error":"fuel_price_stale"}"#
            )
        }

        do {
            _ = try await client.fetchOfficialFuelPrice(
                countryCode: "CA",
                regionCode: "ON",
                locality: "Toronto",
                fuelType: .gasoline
            )
            XCTFail("Expected BackendAPIError.apiStatus")
        } catch let error as BackendAPIError {
            XCTAssertEqual(error, .apiStatus(statusCode: 503, code: "fuel_price_stale"))
        }
    }

    func testOfficialFuelPriceLookupRouteIsExplicitlyLimitedToQualifiedCanadianSources() {
        XCTAssertEqual(
            OfficialFuelPriceLookupRoute.resolve(countryCode: " ca ", regionCode: "Ontario"),
            .ontarioDirect
        )
        XCTAssertEqual(
            OfficialFuelPriceLookupRoute.resolve(countryCode: "CA", regionCode: "QC"),
            .statisticsCanadaDirect
        )
        XCTAssertEqual(
            OfficialFuelPriceLookupRoute.resolve(countryCode: "BF", regionCode: "Kadiogo"),
            .unavailable
        )
        XCTAssertEqual(
            OfficialFuelPriceLookupRoute.resolve(countryCode: "US", regionCode: "CA"),
            .unavailable
        )
    }

    func testOfficialFuelPriceCoordinatorRejectsBurkinaWithoutCallingAProvider() async throws {
        let ontario = OfficialFuelPriceFetcherSpy(result: .success(makeOfficialFuelPriceQuote()))
        let statisticsCanada = OfficialFuelPriceFetcherSpy(result: .success(makeOfficialFuelPriceQuote()))
        let coordinator = OfficialFuelPriceLookupCoordinator(
            ontarioClient: ontario,
            statisticsCanadaClient: statisticsCanada
        )

        do {
            _ = try await coordinator.fetchCurrentPrice(
                countryCode: "BF",
                regionCode: "Kadiogo",
                locality: "Ouagadougou",
                fuelType: .gasoline
            )
            XCTFail("Expected BackendAPIError.apiStatus")
        } catch let error as BackendAPIError {
            XCTAssertEqual(error, .apiStatus(statusCode: 404, code: "fuel_price_unavailable"))
        }

        XCTAssertEqual(ontario.callCount, 0)
        XCTAssertEqual(statisticsCanada.callCount, 0)
    }

    func testOfficialFuelPriceCoordinatorUsesOnlyOntarioProviderForOntario() async throws {
        let expectedQuote = makeOfficialFuelPriceQuote(regionCode: "ON", locality: "Toronto")
        let ontario = OfficialFuelPriceFetcherSpy(result: .success(expectedQuote))
        let statisticsCanada = OfficialFuelPriceFetcherSpy(result: .failure(BackendAPIError.transport))
        let coordinator = OfficialFuelPriceLookupCoordinator(
            ontarioClient: ontario,
            statisticsCanadaClient: statisticsCanada
        )

        let quote = try await coordinator.fetchCurrentPrice(
            countryCode: "CA",
            regionCode: "Ontario",
            locality: "Toronto",
            fuelType: .gasoline
        )

        XCTAssertEqual(quote, expectedQuote)
        XCTAssertEqual(ontario.callCount, 1)
        XCTAssertEqual(ontario.lastRegionCode, "Ontario")
        XCTAssertEqual(statisticsCanada.callCount, 0)
    }

    func testOfficialFuelPriceCoordinatorUsesOnlyStatisticsCanadaForOtherCanadianRegions() async throws {
        let expectedQuote = makeOfficialFuelPriceQuote(regionCode: "QC", locality: "Montreal")
        let ontario = OfficialFuelPriceFetcherSpy(result: .failure(BackendAPIError.transport))
        let statisticsCanada = OfficialFuelPriceFetcherSpy(result: .success(expectedQuote))
        let coordinator = OfficialFuelPriceLookupCoordinator(
            ontarioClient: ontario,
            statisticsCanadaClient: statisticsCanada
        )

        let quote = try await coordinator.fetchCurrentPrice(
            countryCode: "CA",
            regionCode: "QC",
            locality: "Montreal",
            fuelType: .gasoline
        )

        XCTAssertEqual(quote, expectedQuote)
        XCTAssertEqual(ontario.callCount, 0)
        XCTAssertEqual(statisticsCanada.callCount, 1)
        XCTAssertEqual(statisticsCanada.lastRegionCode, "QC")
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

    func testStatisticsCanadaFuelPriceUsesOnlyOfficialSeriesCoordinate() async throws {
        let endpoint = try XCTUnwrap(
            URL(string: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromCubePidCoordAndLatestNPeriods")
        )
        let session = makeSession { request in
            XCTAssertEqual(request.url, endpoint)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try self.requestBodyData(request)
            let values = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [[String: Any]]
            )
            XCTAssertEqual(values.count, 1)
            XCTAssertEqual(values[0]["productId"] as? Int, 18_100_001)
            XCTAssertEqual(values[0]["coordinate"] as? String, "7.2.0.0.0.0.0.0.0.0")
            XCTAssertEqual(values[0]["latestN"] as? Int, 3)
            let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))
            XCTAssertFalse(bodyText.localizedCaseInsensitiveContains("Montréal"))
            XCTAssertFalse(bodyText.localizedCaseInsensitiveContains("Québec"))
            XCTAssertFalse(bodyText.contains("latitude"))
            XCTAssertFalse(bodyText.contains("longitude"))
            return self.httpResponse(
                for: request,
                statusCode: 200,
                body: self.statisticsCanadaFuelResponse(
                    coordinate: "7.2.0.0.0.0.0.0.0.0",
                    value: 187.4
                ),
                responseURL: endpoint,
                contentType: "application/json"
            )
        }
        let client = StatisticsCanadaPublicFuelPriceClient(session: session)
        let now = Date(timeIntervalSince1970: 1_788_409_800)

        let quote = try await client.fetchCurrentPrice(
            countryCode: "CA",
            regionCode: "Québec",
            locality: "Montréal",
            fuelType: .gasoline,
            now: now
        )

        XCTAssertEqual(quote.pricePerLiter, 1.874, accuracy: 0.000_1)
        XCTAssertEqual(quote.locality, "Montréal")
        XCTAssertEqual(quote.currency, .cad)
        XCTAssertEqual(quote.source, "statistics_canada_table_18_10_0001_01")
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            utcCalendar.dateComponents([.year, .month, .day], from: quote.observedAt),
            DateComponents(year: 2026, month: 7, day: 31)
        )
        XCTAssertEqual(
            quote.sourceURL.absoluteString,
            "https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1810000101"
        )
    }

    func testStatisticsCanadaFuelPriceFallsBackHonestlyToCanadaAverage() async throws {
        let endpoint = try XCTUnwrap(
            URL(string: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromCubePidCoordAndLatestNPeriods")
        )
        let client = StatisticsCanadaPublicFuelPriceClient(session: makeSession { request in
            let body = try self.requestBodyData(request)
            let values = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [[String: Any]]
            )
            XCTAssertEqual(values[0]["coordinate"] as? String, "20.2.0.0.0.0.0.0.0.0")
            return self.httpResponse(
                for: request,
                statusCode: 200,
                body: self.statisticsCanadaFuelResponse(
                    coordinate: "20.2.0.0.0.0.0.0.0.0",
                    value: 181.2
                ),
                responseURL: endpoint,
                contentType: "application/json"
            )
        })

        let quote = try await client.fetchCurrentPrice(
            countryCode: "CA",
            regionCode: "Québec",
            locality: "Sherbrooke",
            fuelType: .gasoline,
            now: Date(timeIntervalSince1970: 1_788_409_800)
        )

        XCTAssertEqual(quote.locality, "Canada")
        XCTAssertEqual(quote.pricePerLiter, 1.812, accuracy: 0.000_1)
        XCTAssertEqual(quote.fuelType, .gasoline)
    }

    func testStatisticsCanadaMarketMappingIsRegionScopedAndComplete() async throws {
        let endpoint = try XCTUnwrap(
            URL(string: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromCubePidCoordAndLatestNPeriods")
        )
        let cases: [(region: String, locality: String, member: Int, label: String)] = [
            ("Terre-Neuve-et-Labrador", "St. John's", 2, "St. John's"),
            ("Île-du-Prince-Édouard", "Summerside", 3, "Charlottetown et Summerside"),
            ("Nouvelle-Écosse", "Halifax", 4, "Halifax"),
            ("Nouveau-Brunswick", "Saint John", 5, "Saint John"),
            ("QC", "Québec", 6, "Québec"),
            ("Québec", "Montréal", 7, "Montréal"),
            ("Québec", "Gatineau", 20, "Canada"),
            ("Manitoba", "Winnipeg", 11, "Winnipeg"),
            ("Saskatchewan", "Regina", 12, "Regina"),
            ("SK", "Saskatoon", 13, "Saskatoon"),
            ("Alberta", "Edmonton", 14, "Edmonton"),
            ("AB", "Calgary", 15, "Calgary"),
            ("Colombie-Britannique", "Vancouver", 16, "Vancouver"),
            ("BC", "Victoria", 17, "Victoria"),
            ("Yukon", "Whitehorse", 18, "Whitehorse"),
            ("Territoires du Nord-Ouest", "Yellowknife", 19, "Yellowknife"),
            ("Nunavut", "Iqaluit", 20, "Canada")
        ]

        for item in cases {
            let coordinate = "\(item.member).2.0.0.0.0.0.0.0.0"
            let client = StatisticsCanadaPublicFuelPriceClient(session: makeSession { request in
                self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: self.statisticsCanadaFuelResponse(
                        coordinate: coordinate,
                        value: 150.0
                    ),
                    responseURL: endpoint,
                    contentType: "application/json"
                )
            })

            let quote = try await client.fetchCurrentPrice(
                countryCode: "CA",
                regionCode: item.region,
                locality: item.locality,
                fuelType: .gasoline,
                now: Date(timeIntervalSince1970: 1_788_409_800)
            )

            XCTAssertEqual(quote.locality, item.label, "\(item.region) / \(item.locality)")
        }
    }

    func testStatisticsCanadaFuelPriceRejectsUntrustedOrIncoherentResponses() async throws {
        let endpoint = try XCTUnwrap(
            URL(string: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromCubePidCoordAndLatestNPeriods")
        )
        let cases: [(URL, String)] = [
            (
                try XCTUnwrap(URL(string: "https://attacker.example/t1/wds/rest/getDataFromCubePidCoordAndLatestNPeriods")),
                statisticsCanadaFuelResponse(
                    coordinate: "7.2.0.0.0.0.0.0.0.0",
                    value: 187.4
                )
            ),
            (
                endpoint,
                statisticsCanadaFuelResponse(
                    coordinate: "20.2.0.0.0.0.0.0.0.0",
                    value: 187.4
                )
            ),
            (
                endpoint,
                statisticsCanadaFuelResponse(
                    coordinate: "7.2.0.0.0.0.0.0.0.0",
                    value: 187.4,
                    releaseTime: "2026-06-01T08:30"
                )
            )
        ]

        for (responseURL, responseBody) in cases {
            let client = StatisticsCanadaPublicFuelPriceClient(session: makeSession { request in
                self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: responseBody,
                    responseURL: responseURL,
                    contentType: "application/json"
                )
            })
            do {
                _ = try await client.fetchCurrentPrice(
                    countryCode: "CA",
                    regionCode: "QC",
                    locality: "Montréal",
                    fuelType: .gasoline,
                    now: Date(timeIntervalSince1970: 1_788_409_800)
                )
                XCTFail("Expected Statistics Canada evidence rejection")
            } catch let error as BackendAPIError {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
    }

    func testStatisticsCanadaFuelPriceRejectsUnsupportedInputBeforeNetworking() async throws {
        let client = StatisticsCanadaPublicFuelPriceClient(session: makeSession { _ in
            XCTFail("Unsupported input must not reach the network")
            throw URLError(.badURL)
        })

        let cases: [(country: String, region: String, locality: String, fuel: VehicleFuelType)] = [
            ("BF", "Centre", "Ouagadougou", .gasoline),
            ("CA", "Québec", "Montréal", .electric),
            ("CA", "Québec", "Sherbrooke", .diesel)
        ]
        for item in cases {
            do {
                _ = try await client.fetchCurrentPrice(
                    countryCode: item.country,
                    regionCode: item.region,
                    locality: item.locality,
                    fuelType: item.fuel
                )
                XCTFail("Expected unavailable public fuel price")
            } catch let error as BackendAPIError {
                XCTAssertEqual(
                    error,
                    .apiStatus(statusCode: 404, code: "fuel_price_unavailable")
                )
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

    func testLocalizedVehicleCatalogUsesNRCanOnlyForCanada() {
        XCTAssertEqual(
            LocalizedVehicleCatalogClient.preferredSourceIdentifier(for: .canada),
            NRCanVehicleClient.sourceIdentifier
        )
        XCTAssertEqual(
            LocalizedVehicleCatalogClient.preferredSourceIdentifier(for: .burkinaFaso),
            FuelEconomyVehicleClient.sourceIdentifier
        )
        XCTAssertEqual(
            LocalizedVehicleCatalogClient.preferredSourceIdentifier(for: .other),
            FuelEconomyVehicleClient.sourceIdentifier
        )
    }

    func testNRCanVariantsUseOfficialCSVWithoutLocationAndExcludeAdjacentModels() async throws {
        let csv = """
        \u{feff}Model year,Make,Model,Vehicle class,Engine size (L),Cylinders,Transmission,Fuel type,City (L/100 km),Highway (L/100 km),Combined (L/100 km),Combined (mpg),CO2 emissions (g/km),CO2 rating,Smog rating
        2026,Toyota,Corolla (1-mode),Compact,2.0,4,AV,X,7.4,5.7,6.7,42,158,6,5
        2026,Toyota,Corolla Hybrid,Compact,1.8,4,AV,X,4.4,5.1,4.7,60,110,8,6
        2026,Toyota,Corolla Cross,Sport utility vehicle: Small,2.0,4,AV10,X,7.6,7.2,7.4,38,172,6,5
        2026,Honda,Corolla (1-mode),Compact,2.0,4,AV,X,7.4,5.7,6.7,42,158,6,5
        2025,Toyota,Corolla (1-mode),Compact,2.0,4,AV,X,7.4,5.7,6.7,42,158,6,5
        """
        let client = NRCanVehicleClient(session: makeSession { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(
                url.absoluteString,
                "https://open.canada.ca/data/dataset/98f1a129-f628-4ce4-b24d-6f16bf24dd64/resource/9df1b18d-d036-4783-a61c-99f1f75b3ac5/download/my2026-fuel-consumption-ratings.csv"
            )
            XCTAssertNil(url.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/csv")
            return self.httpResponse(for: request, statusCode: 200, body: csv, contentType: "text/csv")
        })

        let variants = try await client.fetchVariants(
            year: 2026,
            make: "Toyota",
            model: "Corolla",
            expectedFuelType: .gasoline
        )

        XCTAssertEqual(variants.count, 1)
        XCTAssertTrue(variants[0].description.contains("Corolla (1-mode)"))
        XCTAssertEqual(variants[0].sourceIdentifier, NRCanVehicleClient.sourceIdentifier)
        XCTAssertTrue(NRCanVehicleClient.isValidRecordID(variants[0].recordID))
    }

    func testNRCanCreatesAuditableSpecificationAndRejectsPersistedTampering() async throws {
        let csv = """
        Model year,Make,Model,Vehicle class,Engine size (L),Cylinders,Transmission,Fuel type,City (L/100 km),Highway (L/100 km),Combined (L/100 km),Combined (mpg),CO2 emissions (g/km),CO2 rating,Smog rating
        2026,Toyota,Corolla (1-mode),Compact,2.0,4,AV,X,7.4,5.7,6.7,42,158,6,5
        """
        let client = NRCanVehicleClient(session: makeSession { request in
            self.httpResponse(for: request, statusCode: 200, body: csv, contentType: "text/csv")
        })
        let variants = try await client.fetchVariants(
            year: 2026,
            make: "Toyota",
            model: "Corolla",
            expectedFuelType: .gasoline
        )
        let variant = try XCTUnwrap(variants.first)
        let retrievedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let specification = try await client.fetchSpecification(
            variant: variant,
            expectedYear: 2026,
            expectedMake: "Toyota",
            expectedModel: "Corolla",
            expectedFuelType: .gasoline,
            retrievedAt: retrievedAt
        )

        XCTAssertEqual(specification.sourceIdentifier, NRCanVehicleClient.sourceIdentifier)
        XCTAssertEqual(specification.variant, "Corolla (1-mode)")
        XCTAssertEqual(specification.engineDescription, "2 L · 4 cyl")
        XCTAssertEqual(specification.cityLitersPer100Km, 7.4)
        XCTAssertEqual(specification.highwayLitersPer100Km, 5.7)
        XCTAssertEqual(specification.combinedLitersPer100Km, 6.7)
        XCTAssertEqual(specification.fuelType, .gasoline)
        XCTAssertEqual(specification.retrievedAt, retrievedAt)
        XCTAssertTrue(specification.hasTrustedEvidence)

        let encoded = try JSONEncoder().encode(specification)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["combinedLitersPer100Km"] = 7.0
        let tampered = try JSONDecoder().decode(
            VerifiedVehicleSpecification.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertFalse(tampered.hasTrustedEvidence)
    }

    func testNRCanAcceptsExactOfficialBlobRedirectAndRejectsDifferentPath() async throws {
        let csv = """
        Model year,Make,Model,Vehicle class,Engine size (L),Cylinders,Transmission,Fuel type,City (L/100 km),Highway (L/100 km),Combined (L/100 km),Combined (mpg),CO2 emissions (g/km),CO2 rating,Smog rating
        2026,Toyota,"Corolla (1-mode)",Compact,2.0,4,AV,X,7.4,5.7,6.7,42,158,6,5
        """
        let trustedBlob = URL(string: "https://opencanada.blob.core.windows.net/opengovprod/resources/9df1b18d-d036-4783-a61c-99f1f75b3ac5/my2026-fuel-consumption-ratings.csv?sv=official&sig=redacted")!
        let trustedClient = NRCanVehicleClient(session: makeSession { request in
            self.httpResponse(
                for: request,
                statusCode: 200,
                body: csv,
                responseURL: trustedBlob,
                contentType: "text/csv"
            )
        })
        let variants = try await trustedClient.fetchVariants(
            year: 2026,
            make: "Toyota",
            model: "Corolla",
            expectedFuelType: .gasoline
        )
        XCTAssertEqual(variants.count, 1)

        let wrongPath = URL(string: "https://opencanada.blob.core.windows.net/opengovprod/resources/attacker/my2026-fuel-consumption-ratings.csv")!
        let rejectedClient = NRCanVehicleClient(session: makeSession { request in
            self.httpResponse(
                for: request,
                statusCode: 200,
                body: csv,
                responseURL: wrongPath,
                contentType: "text/csv"
            )
        })
        do {
            _ = try await rejectedClient.fetchVariants(
                year: 2026,
                make: "Toyota",
                model: "Corolla",
                expectedFuelType: .gasoline
            )
            XCTFail("Expected an unrelated blob path to be rejected")
        } catch let error as PublicVehicleCatalogError {
            XCTAssertEqual(error, .untrustedResponse)
        }
    }

    func testNRCanRejectsMalformedCSVAndImplausibleEngineEvidence() async throws {
        let malformedCSV = """
        Model year,Make,Model,Vehicle class,Engine size (L),Cylinders,Transmission,Fuel type,City (L/100 km),Highway (L/100 km),Combined (L/100 km),Combined (mpg),CO2 emissions (g/km),CO2 rating,Smog rating
        2026,Toyota,"Corolla (1-mode),Compact,2.0,4,AV,X,7.4,5.7,6.7,42,158,6,5
        """
        let malformedClient = NRCanVehicleClient(session: makeSession { request in
            self.httpResponse(for: request, statusCode: 200, body: malformedCSV, contentType: "text/csv")
        })
        do {
            _ = try await malformedClient.fetchVariants(
                year: 2026,
                make: "Toyota",
                model: "Corolla",
                expectedFuelType: .gasoline
            )
            XCTFail("Expected malformed CSV to be rejected")
        } catch let error as PublicVehicleCatalogError {
            XCTAssertEqual(error, .invalidResponse)
        }

        let impossibleEngineCSV = """
        Model year,Make,Model,Vehicle class,Engine size (L),Cylinders,Transmission,Fuel type,City (L/100 km),Highway (L/100 km),Combined (L/100 km),Combined (mpg),CO2 emissions (g/km),CO2 rating,Smog rating
        2026,Toyota,Corolla (1-mode),Compact,200,400,AV,X,7.4,5.7,6.7,42,158,6,5
        """
        let impossibleClient = NRCanVehicleClient(session: makeSession { request in
            self.httpResponse(for: request, statusCode: 200, body: impossibleEngineCSV, contentType: "text/csv")
        })
        do {
            _ = try await impossibleClient.fetchVariants(
                year: 2026,
                make: "Toyota",
                model: "Corolla",
                expectedFuelType: .gasoline
            )
            XCTFail("Expected implausible engine evidence to be rejected")
        } catch let error as PublicVehicleCatalogError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    private func statisticsCanadaFuelResponse(
        coordinate: String,
        value: Double,
        releaseTime: String = "2026-08-17T08:30"
    ) -> String {
        """
        [{"status":"SUCCESS","object":{"responseStatusCode":0,"productId":18100001,"coordinate":"\(coordinate)","vectorId":735096,"vectorDataPoint":[{"refPer":"2026-07-01","value":\(value),"decimals":1,"scalarFactorCode":0,"symbolCode":0,"statusCode":0,"securityLevelCode":0,"releaseTime":"\(releaseTime)","frequencyCode":6}]}}]
        """
    }

    private func requestBodyData(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw try XCTUnwrap(stream.streamError)
            }
            if count == 0 {
                return data
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> BackendAPIClient {
        BackendAPIClient(session: makeSession(handler: handler))
    }

    private func makeOfficialFuelPriceQuote(
        regionCode: String = "ON",
        locality: String = "Toronto"
    ) -> PublicFuelPriceQuote {
        PublicFuelPriceQuote(
            countryCode: "CA",
            regionCode: regionCode,
            locality: locality,
            fuelType: .gasoline,
            pricePerLiter: 1.55,
            currency: .cad,
            observedAt: Date(timeIntervalSince1970: 1_788_112_000),
            retrievedAt: Date(timeIntervalSince1970: 1_788_198_400),
            source: OfficialFuelPriceEvidenceContract.ontarioIdentifier,
            sourceURL: OfficialFuelPriceEvidenceContract.ontarioURL
        )
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

private final class OfficialFuelPriceFetcherSpy: OfficialFuelPriceFetching {
    private let result: Result<PublicFuelPriceQuote, Error>
    private(set) var callCount = 0
    private(set) var lastRegionCode: String?

    init(result: Result<PublicFuelPriceQuote, Error>) {
        self.result = result
    }

    func fetchCurrentPrice(
        countryCode: String,
        regionCode: String,
        locality: String,
        fuelType: VehicleFuelType,
        now: Date
    ) async throws -> PublicFuelPriceQuote {
        callCount += 1
        lastRegionCode = regionCode
        return try result.get()
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
