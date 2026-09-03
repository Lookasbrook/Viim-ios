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
    static let gpsSessionSplitDefaultsKey = "viim.feature.gpsSessionSplit"
    static let physicalFuelModelDefaultsKey = "viim.feature.physicalFuelModel"
    static let transitClassifierDefaultsKey = "viim.feature.transitClassifier"
    private static let activatedAtSuffix = ".activatedAt"

    let gpsSessionSplit: Bool
    let physicalFuelModel: Bool
    let transitClassifier: Bool

    static let disabled = CarburantFeatureFlags(
        gpsSessionSplit: false,
        physicalFuelModel: false,
        transitClassifier: false
    )

    /// Resume compact pour la journalisation de lancement. Rend visible, a
    /// chaque demarrage, tout override reste actif apres un spike.
    var diagnosticSummary: String {
        "gpsSessionSplit=\(gpsSessionSplit) physicalFuelModel=\(physicalFuelModel) transitClassifier=\(transitClassifier)"
    }

    /// Les variantes sont impossibles a activer dans une build Release/TestFlight.
    /// En Debug elles ne vivent que pendant le processus courant. Un experiment
    /// de localisation ne doit jamais survivre silencieusement a une relance.
    static func resolved(arguments: [String] = ProcessInfo.processInfo.arguments) -> CarburantFeatureFlags {
        #if DEBUG
        return CarburantFeatureFlags(
            gpsSessionSplit: arguments.contains(gpsSessionSplitArgument),
            physicalFuelModel: arguments.contains(physicalFuelModelArgument),
            transitClassifier: arguments.contains(transitClassifierArgument)
        )
        #else
        return .disabled
        #endif
    }

    /// Nettoie les overrides ecrits par les anciennes builds. Les supprimer est
    /// volontaire : ignorer la valeur ne suffit pas, car un rollback pourrait
    /// la rendre active de nouveau.
    static func clearPersistedDebugOverrides(userDefaults: UserDefaults = .standard) {
        func clear(_ key: String) {
            userDefaults.removeObject(forKey: key)
            userDefaults.removeObject(forKey: key + activatedAtSuffix)
        }
        clear(gpsSessionSplitDefaultsKey)
        clear(physicalFuelModelDefaultsKey)
        clear(transitClassifierDefaultsKey)
    }
}
