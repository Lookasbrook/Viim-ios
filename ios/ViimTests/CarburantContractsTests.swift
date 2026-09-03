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

    func testDebugLaunchOverridePersistsForSystemRelaunch() {
        let suiteName = "CarburantContractsTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        CarburantFeatureFlags.persistDebugOverridesIfRequested(
            arguments: ["Viim", CarburantFeatureFlags.gpsSessionSplitArgument],
            userDefaults: defaults
        )

        let relaunched = CarburantFeatureFlags.resolved(
            arguments: ["Viim"],
            userDefaults: defaults
        )
        #if DEBUG
        XCTAssertTrue(relaunched.gpsSessionSplit)
        #else
        XCTAssertEqual(relaunched, .disabled)
        #endif
        XCTAssertFalse(relaunched.physicalFuelModel)
        XCTAssertFalse(relaunched.transitClassifier)
    }
}
