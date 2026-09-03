import CoreLocation
import XCTest
@testable import Viim

@MainActor
final class FuelPriceGeographyTests: XCTestCase {
    func testLegacyFuelSettingsDecodeWithoutInventingLocationEvidence() throws {
        let encoded = try JSONEncoder().encode(
            officialSettings(observedAt: Date(timeIntervalSince1970: 2_000_000_000))
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json.removeValue(forKey: "locationEvidence")

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(FuelSettings.self, from: legacyData)

        XCTAssertNil(decoded.locationEvidence)
        XCTAssertFalse(FuelPriceGeographyMatcher.acquisitionMatchesPrice(decoded))
    }

    func testOfficialPriceCannotMatchATripWithoutValidAcquisitionLocationEvidence() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let legacy = FuelSettings(
            currency: .cad,
            pricePerLiter: 1.55,
            source: .officialPublicData,
            capturedAt: now,
            fuelType: .gasoline,
            sourceIdentifier: OfficialFuelPriceEvidenceContract.ontarioIdentifier,
            sourceURL: OfficialFuelPriceEvidenceContract.ontarioURL,
            locality: "Toronto"
        )
        let mismatched = officialSettings(
            observedAt: now,
            evidenceLocality: "Toronto",
            requestedLocality: "Ottawa"
        )

        XCTAssertTrue(legacy.canSnapshotCost)
        XCTAssertFalse(FuelPriceGeographyMatcher.acquisitionMatchesPrice(legacy))
        XCTAssertFalse(FuelPriceGeographyMatcher.acquisitionMatchesPrice(mismatched))
    }

    func testTorontoPriceMatchesOnlyWhenBothTripEndpointsResolveToToronto() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let settings = officialSettings(observedAt: now)
        let toronto = locality("CA", "ON", "Toronto")
        let ottawa = locality("CA", "ON", "Ottawa")

        XCTAssertNotNil(
            FuelPriceGeographyMatcher.verifiedMatch(
                tripID: UUID(),
                settings: settings,
                start: toronto,
                end: toronto,
                matchedAt: now
            )
        )
        XCTAssertNil(
            FuelPriceGeographyMatcher.verifiedMatch(
                tripID: UUID(),
                settings: settings,
                start: toronto,
                end: ottawa,
                matchedAt: now
            )
        )
    }

    func testOntarioFallbackAcceptsOnlyOntarioEndpoints() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let settings = officialSettings(
            observedAt: now,
            evidenceLocality: "Ontario",
            requestedLocality: "Kingston"
        )

        XCTAssertNotNil(
            FuelPriceGeographyMatcher.verifiedMatch(
                tripID: UUID(),
                settings: settings,
                start: locality("CA", "ON", "Kingston"),
                end: locality("CA", "ON", "Ottawa"),
                matchedAt: now
            )
        )
        XCTAssertNil(
            FuelPriceGeographyMatcher.verifiedMatch(
                tripID: UUID(),
                settings: settings,
                start: locality("CA", "ON", "Kingston"),
                end: locality("CA", "QC", "Gatineau"),
                matchedAt: now
            )
        )
    }

    func testCanadaFallbackRejectsTripLeavingCanada() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let settings = statCanSettings(
            observedAt: now,
            evidenceLocality: "Canada",
            requestedRegion: "QC",
            requestedLocality: "Sherbrooke"
        )

        XCTAssertNotNil(
            FuelPriceGeographyMatcher.verifiedMatch(
                tripID: UUID(),
                settings: settings,
                start: locality("CA", "QC", "Sherbrooke"),
                end: locality("CA", "BC", "Vancouver"),
                matchedAt: now
            )
        )
        XCTAssertNil(
            FuelPriceGeographyMatcher.verifiedMatch(
                tripID: UUID(),
                settings: settings,
                start: locality("CA", "QC", "Sherbrooke"),
                end: locality("US", "VT", "Burlington"),
                matchedAt: now
            )
        )
    }

    func testStatCanCityMarketRejectsAnotherCityInSameProvince() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let settings = statCanSettings(
            observedAt: now,
            evidenceLocality: "Montréal",
            requestedRegion: "QC",
            requestedLocality: "Montréal"
        )

        XCTAssertNil(
            FuelPriceGeographyMatcher.verifiedMatch(
                tripID: UUID(),
                settings: settings,
                start: locality("CA", "QC", "Montréal"),
                end: locality("CA", "QC", "Québec"),
                matchedAt: now
            )
        )
    }

    func testEnricherPersistsOnlyAfterBothLocationsResolveAndMatch() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let persister = PersisterSpy()
        let resolver = ResolverStub(results: [
            .success(locality("CA", "ON", "Toronto")),
            .success(locality("CA", "ON", "Toronto"))
        ])
        let enricher = TripFuelCostEnricher(persister: persister, resolver: resolver)
        let tripID = UUID()

        let outcome = await enricher.enrich(
            request(
                tripID: tripID,
                settings: officialSettings(observedAt: now),
                endedAt: now
            ),
            matchedAt: now
        )

        XCTAssertEqual(outcome, .enriched)
        XCTAssertEqual(persister.persistedTripIDs, [tripID])
        XCTAssertEqual(resolver.receivedCoordinates.count, 2)
        XCTAssertEqual(persister.matches.first?.version, VerifiedFuelPriceGeographyMatch.version)
    }

    func testEnricherLeavesCostUnavailableOnCrossMarketOrGeocoderFailure() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let settings = officialSettings(observedAt: now)
        let crossMarketPersister = PersisterSpy()
        let crossMarket = TripFuelCostEnricher(
            persister: crossMarketPersister,
            resolver: ResolverStub(results: [
                .success(locality("CA", "ON", "Toronto")),
                .success(locality("CA", "ON", "Ottawa"))
            ])
        )
        let failedPersister = PersisterSpy()
        let failed = TripFuelCostEnricher(
            persister: failedPersister,
            resolver: ResolverStub(results: [.failure(CLError(.network))])
        )

        let crossMarketOutcome = await crossMarket.enrich(
            request(settings: settings, endedAt: now),
            matchedAt: now
        )
        let failedOutcome = await failed.enrich(
            request(settings: settings, endedAt: now),
            matchedAt: now
        )
        XCTAssertEqual(crossMarketOutcome, .geographyMismatch)
        XCTAssertEqual(failedOutcome, .locationResolutionFailed)
        XCTAssertTrue(crossMarketPersister.persistedTripIDs.isEmpty)
        XCTAssertTrue(failedPersister.persistedTripIDs.isEmpty)
    }

    func testEnricherRejectsPoorAccuracyBeforeCallingGeocoder() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let resolver = ResolverStub(results: [])
        let persister = PersisterSpy()
        let enricher = TripFuelCostEnricher(persister: persister, resolver: resolver)
        let poorPoints = routePoints(horizontalAccuracy: 101)

        let outcome = await enricher.enrich(
            TripFuelCostEnrichmentRequest(
                tripID: UUID(),
                routePoints: poorPoints,
                settings: officialSettings(observedAt: now),
                tripEndedAt: now
            ),
            matchedAt: now
        )

        XCTAssertEqual(outcome, .noQualifiedEndpoints)
        XCTAssertTrue(resolver.receivedCoordinates.isEmpty)
        XCTAssertTrue(persister.persistedTripIDs.isEmpty)
    }

    private func officialSettings(
        observedAt: Date,
        evidenceLocality: String = "Toronto",
        requestedLocality: String = "Toronto"
    ) -> FuelSettings {
        FuelSettings(
            currency: .cad,
            pricePerLiter: 1.55,
            source: .officialPublicData,
            capturedAt: observedAt,
            fuelType: .gasoline,
            sourceIdentifier: OfficialFuelPriceEvidenceContract.ontarioIdentifier,
            sourceURL: OfficialFuelPriceEvidenceContract.ontarioURL,
            locality: evidenceLocality,
            locationEvidence: FuelPriceLocationEvidence(
                countryCode: "CA",
                regionCode: "ON",
                locality: requestedLocality,
                resolvedAt: observedAt
            )
        )
    }

    private func statCanSettings(
        observedAt: Date,
        evidenceLocality: String,
        requestedRegion: String,
        requestedLocality: String
    ) -> FuelSettings {
        FuelSettings(
            currency: .cad,
            pricePerLiter: 1.60,
            source: .officialPublicData,
            capturedAt: observedAt,
            fuelType: .gasoline,
            sourceIdentifier: OfficialFuelPriceEvidenceContract.statisticsCanadaIdentifier,
            sourceURL: OfficialFuelPriceEvidenceContract.statisticsCanadaURL,
            locality: evidenceLocality,
            locationEvidence: FuelPriceLocationEvidence(
                countryCode: "CA",
                regionCode: requestedRegion,
                locality: requestedLocality,
                resolvedAt: observedAt
            )
        )
    }

    private func locality(_ country: String, _ region: String, _ city: String) -> TripEndpointLocality {
        TripEndpointLocality(countryCode: country, regionCode: region, locality: city)
    }

    private func request(
        tripID: UUID = UUID(),
        settings: FuelSettings,
        endedAt: Date
    ) -> TripFuelCostEnrichmentRequest {
        TripFuelCostEnrichmentRequest(
            tripID: tripID,
            routePoints: routePoints(horizontalAccuracy: 5),
            settings: settings,
            tripEndedAt: endedAt
        )
    }

    private func routePoints(horizontalAccuracy: CLLocationAccuracy) -> [TripRoutePoint] {
        [
            TripRoutePoint(
                timestamp: Date(timeIntervalSince1970: 2_000_000_000),
                latitude: 43.65,
                longitude: -79.38,
                speedKmh: 30,
                horizontalAccuracy: horizontalAccuracy
            ),
            TripRoutePoint(
                timestamp: Date(timeIntervalSince1970: 2_000_000_060),
                latitude: 43.70,
                longitude: -79.40,
                speedKmh: 30,
                horizontalAccuracy: horizontalAccuracy
            )
        ]
    }
}

@MainActor
private final class ResolverStub: TripEndpointLocalityResolving {
    private var results: [Result<TripEndpointLocality, Error>]
    private(set) var receivedCoordinates: [CLLocationCoordinate2D] = []

    init(results: [Result<TripEndpointLocality, Error>]) {
        self.results = results
    }

    func resolve(coordinate: CLLocationCoordinate2D) async throws -> TripEndpointLocality {
        receivedCoordinates.append(coordinate)
        guard !results.isEmpty else { throw CLError(.geocodeFoundNoResult) }
        return try results.removeFirst().get()
    }
}

@MainActor
private final class PersisterSpy: TripFuelCostPersisting {
    private(set) var persistedTripIDs: [UUID] = []
    private(set) var matches: [VerifiedFuelPriceGeographyMatch] = []

    func persistVerifiedOfficialFuelCost(
        tripID: UUID,
        settings: FuelSettings,
        match: VerifiedFuelPriceGeographyMatch
    ) throws -> Bool {
        persistedTripIDs.append(tripID)
        matches.append(match)
        return true
    }
}
