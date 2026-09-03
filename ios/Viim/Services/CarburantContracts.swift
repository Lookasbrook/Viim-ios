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
    private static let activatedAtSuffix = ".activatedAt"

    /// Un override de debug est memorise pour survivre a une relance systeme
    /// Core Location pendant un spike terrain, mais PAS indefiniment. Au-dela
    /// de cette fenetre il est ignore tant qu'un lancement ne le re-arme pas
    /// explicitement. Sans ce plafond, un flag `gpsSessionSplit` oublie a
    /// degrade la collecte GPS en arriere-plan en silence pendant deux
    /// semaines (incident 2026-09-02, journal device `authorizedWhenInUse` +
    /// session d'activite jamais restauree).
    static let persistedOverrideTTL: TimeInterval = 7 * 24 * 60 * 60

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

    /// Les variantes sont volontairement impossibles a activer dans une build
    /// Release/TestFlight. En Debug, l'argument de lancement est memorise afin
    /// de survivre a une relance systeme Core Location pendant le spike terrain,
    /// puis expire apres `persistedOverrideTTL`.
    static func resolved(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> CarburantFeatureFlags {
        #if DEBUG
        func isActive(argument: String, key: String) -> Bool {
            if arguments.contains(argument) {
                return true
            }
            guard userDefaults.bool(forKey: key) else {
                return false
            }
            // Un override persiste sans horodatage vient d'une version
            // anterieure au plafond : impossible de prouver qu'il est recent,
            // on l'ignore plutot que de degrader la collecte a l'aveugle.
            guard let activatedAt = userDefaults.object(forKey: key + activatedAtSuffix) as? Date else {
                return false
            }
            return now.timeIntervalSince(activatedAt) <= persistedOverrideTTL
        }
        return CarburantFeatureFlags(
            gpsSessionSplit: isActive(argument: gpsSessionSplitArgument, key: gpsSessionSplitDefaultsKey),
            physicalFuelModel: isActive(argument: physicalFuelModelArgument, key: physicalFuelModelDefaultsKey),
            transitClassifier: isActive(argument: transitClassifierArgument, key: transitClassifierDefaultsKey)
        )
        #else
        return .disabled
        #endif
    }

    static func persistDebugOverridesIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        #if DEBUG
        func clear(_ key: String) {
            userDefaults.removeObject(forKey: key)
            userDefaults.removeObject(forKey: key + activatedAtSuffix)
        }
        func arm(_ key: String) {
            userDefaults.set(true, forKey: key)
            userDefaults.set(now, forKey: key + activatedAtSuffix)
        }
        if arguments.contains(resetDebugOverridesArgument) {
            clear(gpsSessionSplitDefaultsKey)
            clear(physicalFuelModelDefaultsKey)
            clear(transitClassifierDefaultsKey)
        }
        if arguments.contains(gpsSessionSplitArgument) {
            arm(gpsSessionSplitDefaultsKey)
        }
        if arguments.contains(physicalFuelModelArgument) {
            arm(physicalFuelModelDefaultsKey)
        }
        if arguments.contains(transitClassifierArgument) {
            arm(transitClassifierDefaultsKey)
        }
        #endif
    }
}
