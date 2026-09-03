import Foundation

enum FuelCostState: String, Codable, CaseIterable {
    case pending
    case unavailable
    case estimated
    case confirmed
}

enum FuelPriceEvidenceKind: String, Codable, CaseIterable {
    case administeredExact = "administered_exact"
    case officialAverage = "official_average"
    case cachedStale = "cached_stale"
}

enum TripRole: String, Codable, CaseIterable {
    case conducteur
    case passagerTransport = "passager_transport"
    case inconnu

    init?(persistedValue: String) {
        switch persistedValue {
        case Self.conducteur.rawValue:
            self = .conducteur
        case Self.passagerTransport.rawValue, "passager", "bus":
            self = .passagerTransport
        case Self.inconnu.rawValue:
            self = .inconnu
        default:
            return nil
        }
    }
}

struct CarburantFeatureFlags: Equatable {
    static let gpsSessionSplitArgument = "-viimFeature:gpsSessionSplit"
    static let physicalFuelModelArgument = "-viimFeature:physicalFuelModel"
    static let transitClassifierArgument = "-viimFeature:transitClassifier"
    static let resetDebugOverridesArgument = "-viimFeature:reset"

    private static let gpsSessionSplitDefaultsKey = "viim.feature.gpsSessionSplit"
    private static let physicalFuelModelDefaultsKey = "viim.feature.physicalFuelModel"
    private static let transitClassifierDefaultsKey = "viim.feature.transitClassifier"

    let gpsSessionSplit: Bool
    let physicalFuelModel: Bool
    let transitClassifier: Bool

    static let disabled = CarburantFeatureFlags(
        gpsSessionSplit: false,
        physicalFuelModel: false,
        transitClassifier: false
    )

    /// Les variantes sont volontairement impossibles a activer dans une build
    /// Release/TestFlight. En Debug, l'argument de lancement est memorise afin
    /// de survivre a une relance systeme Core Location pendant le spike terrain.
    static func resolved(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        userDefaults: UserDefaults = .standard
    ) -> CarburantFeatureFlags {
        #if DEBUG
        CarburantFeatureFlags(
            gpsSessionSplit: arguments.contains(gpsSessionSplitArgument) || userDefaults.bool(forKey: gpsSessionSplitDefaultsKey),
            physicalFuelModel: arguments.contains(physicalFuelModelArgument) || userDefaults.bool(forKey: physicalFuelModelDefaultsKey),
            transitClassifier: arguments.contains(transitClassifierArgument) || userDefaults.bool(forKey: transitClassifierDefaultsKey)
        )
        #else
        .disabled
        #endif
    }

    static func persistDebugOverridesIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        userDefaults: UserDefaults = .standard
    ) {
        #if DEBUG
        if arguments.contains(resetDebugOverridesArgument) {
            userDefaults.set(false, forKey: gpsSessionSplitDefaultsKey)
            userDefaults.set(false, forKey: physicalFuelModelDefaultsKey)
            userDefaults.set(false, forKey: transitClassifierDefaultsKey)
        }
        if arguments.contains(gpsSessionSplitArgument) {
            userDefaults.set(true, forKey: gpsSessionSplitDefaultsKey)
        }
        if arguments.contains(physicalFuelModelArgument) {
            userDefaults.set(true, forKey: physicalFuelModelDefaultsKey)
        }
        if arguments.contains(transitClassifierArgument) {
            userDefaults.set(true, forKey: transitClassifierDefaultsKey)
        }
        #endif
    }
}
