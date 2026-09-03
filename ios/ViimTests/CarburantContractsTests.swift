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

    func testPersistedGpsSplitOverrideIsIgnoredAfterTTL() {
        let suiteName = "CarburantContractsTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let armedAt = Date(timeIntervalSince1970: 1_000_000)
        CarburantFeatureFlags.persistDebugOverridesIfRequested(
            arguments: ["Viim", CarburantFeatureFlags.gpsSessionSplitArgument],
            userDefaults: defaults,
            now: armedAt
        )

        let withinWindow = CarburantFeatureFlags.resolved(
            arguments: ["Viim"],
            userDefaults: defaults,
            now: armedAt.addingTimeInterval(CarburantFeatureFlags.persistedOverrideTTL - 60)
        )
        let afterWindow = CarburantFeatureFlags.resolved(
            arguments: ["Viim"],
            userDefaults: defaults,
            now: armedAt.addingTimeInterval(CarburantFeatureFlags.persistedOverrideTTL + 60)
        )

        #if DEBUG
        XCTAssertTrue(withinWindow.gpsSessionSplit)
        XCTAssertFalse(afterWindow.gpsSessionSplit)
        #else
        XCTAssertEqual(withinWindow, .disabled)
        XCTAssertEqual(afterWindow, .disabled)
        #endif
    }

    func testExpiredPersistedOverrideIsReArmedByLaunchArgument() {
        let suiteName = "CarburantContractsTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let armedAt = Date(timeIntervalSince1970: 1_000_000)
        CarburantFeatureFlags.persistDebugOverridesIfRequested(
            arguments: ["Viim", CarburantFeatureFlags.gpsSessionSplitArgument],
            userDefaults: defaults,
            now: armedAt
        )

        let staleNow = armedAt.addingTimeInterval(CarburantFeatureFlags.persistedOverrideTTL * 4)
        CarburantFeatureFlags.persistDebugOverridesIfRequested(
            arguments: ["Viim", CarburantFeatureFlags.gpsSessionSplitArgument],
            userDefaults: defaults,
            now: staleNow
        )

        let resolved = CarburantFeatureFlags.resolved(
            arguments: ["Viim"],
            userDefaults: defaults,
            now: staleNow.addingTimeInterval(60)
        )

        #if DEBUG
        XCTAssertTrue(resolved.gpsSessionSplit)
        #else
        XCTAssertEqual(resolved, .disabled)
        #endif
    }

    func testLegacyPersistedOverrideWithoutTimestampIsIgnored() {
        // Reproduit l'etat du telephone lors de l'incident 2026-09-02 :
        // `viim.feature.gpsSessionSplit = true` ecrit par une version sans
        // horodatage. La build corrigee ne doit plus l'honorer.
        let suiteName = "CarburantContractsTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "viim.feature.gpsSessionSplit")

        let resolved = CarburantFeatureFlags.resolved(
            arguments: ["Viim"],
            userDefaults: defaults,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #if DEBUG
        XCTAssertFalse(resolved.gpsSessionSplit)
        #else
        XCTAssertEqual(resolved, .disabled)
        #endif
    }

    func testDiagnosticSummaryListsEveryFlag() {
        XCTAssertEqual(
            CarburantFeatureFlags.disabled.diagnosticSummary,
            "gpsSessionSplit=false physicalFuelModel=false transitClassifier=false"
        )
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
