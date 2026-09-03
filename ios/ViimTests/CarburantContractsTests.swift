import XCTest
@testable import Viim

final class CarburantContractsTests: XCTestCase {
    func testWireValuesRemainStable() {
        XCTAssertEqual(FuelCostState.allCases.map(\.rawValue), [
            "pending", "unavailable", "estimated", "confirmed"
        ])
        XCTAssertEqual(FuelPriceEvidenceKind.allCases.map(\.rawValue), [
            "administered_exact", "official_average", "cached_stale"
        ])
        XCTAssertEqual(TripRole.allCases.map(\.rawValue), [
            "conducteur", "passager_transport", "inconnu"
        ])
    }

    func testLegacyTripRolesNormalizeWithoutBecomingCanonicalValues() {
        XCTAssertEqual(TripRole(persistedValue: "passager"), .passagerTransport)
        XCTAssertEqual(TripRole(persistedValue: "bus"), .passagerTransport)
        XCTAssertNil(TripRole(persistedValue: "chauffeur_probable"))
    }

    func testExperimentalFlagsAreDisabledUnlessIndividuallyRequested() {
        XCTAssertEqual(CarburantFeatureFlags.resolved(arguments: ["Viim"]), .disabled)

        let gpsOnly = CarburantFeatureFlags.resolved(arguments: [
            "Viim", CarburantFeatureFlags.gpsSessionSplitArgument
        ])
        #if DEBUG
        XCTAssertTrue(gpsOnly.gpsSessionSplit)
        #else
        XCTAssertEqual(gpsOnly, .disabled)
        #endif
        XCTAssertFalse(gpsOnly.physicalFuelModel)
        XCTAssertFalse(gpsOnly.transitClassifier)
    }

    func testPersistedGpsSplitOverrideNeverActivatesAFlag() {
        let suiteName = "CarburantContractsTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: CarburantFeatureFlags.gpsSessionSplitDefaultsKey)
        defaults.set(Date(), forKey: CarburantFeatureFlags.gpsSessionSplitDefaultsKey + ".activatedAt")

        XCTAssertEqual(CarburantFeatureFlags.resolved(arguments: ["Viim"]), .disabled)
    }

    func testLegacyPersistedOverridesAreDeletedAtLaunch() {
        // Reproduit l'etat du telephone lors de l'incident 2026-09-02 :
        // `viim.feature.gpsSessionSplit = true` ecrit par une version sans
        // horodatage. La build corrigee ne doit plus l'honorer.
        let suiteName = "CarburantContractsTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keys = [
            CarburantFeatureFlags.gpsSessionSplitDefaultsKey,
            CarburantFeatureFlags.physicalFuelModelDefaultsKey,
            CarburantFeatureFlags.transitClassifierDefaultsKey
        ]
        for key in keys {
            defaults.set(true, forKey: key)
            defaults.set(Date(), forKey: key + ".activatedAt")
        }

        CarburantFeatureFlags.clearPersistedDebugOverrides(userDefaults: defaults)

        for key in keys {
            XCTAssertNil(defaults.object(forKey: key))
            XCTAssertNil(defaults.object(forKey: key + ".activatedAt"))
        }
    }

    func testDiagnosticSummaryListsEveryFlag() {
        XCTAssertEqual(
            CarburantFeatureFlags.disabled.diagnosticSummary,
            "gpsSessionSplit=false physicalFuelModel=false transitClassifier=false"
        )
    }

    func testDebugLaunchOverrideEndsWithTheCurrentProcessArguments() {
        let requested = CarburantFeatureFlags.resolved(
            arguments: ["Viim", CarburantFeatureFlags.gpsSessionSplitArgument]
        )
        let relaunched = CarburantFeatureFlags.resolved(arguments: ["Viim"])
        #if DEBUG
        XCTAssertTrue(requested.gpsSessionSplit)
        #else
        XCTAssertEqual(requested, .disabled)
        #endif
        XCTAssertEqual(relaunched, .disabled)
    }
}
