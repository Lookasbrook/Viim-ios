import Foundation

/// Resume de la dynamique reelle d'un trajet, derive des vitesses GPS
/// horodatees. Sert a moduler l'estimation carburant et a calculer les
/// scores de fluidite et d'eco-conduite : un meme kilometrage ne coute
/// pas pareil selon les accelerations, freinages et temps de ralenti.
struct DrivingDynamics: Equatable {
    /// Vitesse moyenne pendant les phases de deplacement (km/h).
    let meanMovingSpeedKmh: Double
    /// Fraction du temps analyse passee quasi a l'arret (moteur tournant).
    let idleRatio: Double
    /// Accelerations franches (> seuil) detectees sur le trajet.
    let hardAccelerationCount: Int
    /// Freinages brusques (< seuil) detectes sur le trajet.
    let hardBrakingCount: Int
    /// RMS des accelerations positives (m/s2) : agressivite globale.
    let accelerationRms: Double
    /// Duree effectivement couverte par des paires d'echantillons valides.
    let analyzedDurationSec: Double
    /// Distance de reference pour normaliser les evenements.
    let distanceKm: Double

    var abruptEventsPer10Km: Double? {
        guard distanceKm > 0.2 else {
            return nil
        }
        return Double(hardAccelerationCount + hardBrakingCount) / distanceKm * 10
    }
}

enum DrivingDynamicsAnalyzer {
    static let formulaVersion = "driving-dynamics-v1"

    /// Seuils issus des standards telematiques assurantiels (m/s2).
    static let hardAccelerationThreshold = 2.5
    static let hardBrakingThreshold = -3.0
    /// En dessous, le vehicule est considere a l'arret (ralenti).
    static let idleSpeedThresholdKmh = 4.0
    /// Paires d'echantillons exploitables pour une derivee de vitesse.
    private static let minimumPairInterval: TimeInterval = 0.4
    private static let maximumPairInterval: TimeInterval = 8.0
    /// Couverture minimale pour publier une dynamique fiable.
    static let minimumAnalyzedDuration: TimeInterval = 60

    static func dynamics(
        samples: [LocationSample],
        vehicleType: VehicleType,
        distanceKm: Double
    ) -> DrivingDynamics? {
        dynamics(
            points: samples.map { ($0.timestamp, $0.speedKmh, $0.horizontalAccuracy, $0.speedAccuracy) },
            vehicleType: vehicleType,
            distanceKm: distanceKm,
            allowUnknownSpeedAccuracy: false
        )
    }

    /// Variante pour les trajets deja stockes : leurs points de trace ont
    /// deja passe le filtre qualite a l'enregistrement, mais les anciens
    /// encodages ne persistaient pas `speedAccuracy` (-1 au decodage). On
    /// l'accepte donc comme « inconnue » pour ne pas priver l'historique
    /// des scores de fluidite et de la consommation dynamique.
    static func dynamics(
        routePoints: [TripRoutePoint],
        vehicleType: VehicleType,
        distanceKm: Double
    ) -> DrivingDynamics? {
        dynamics(
            points: routePoints.map { ($0.timestamp, $0.speedKmh, $0.horizontalAccuracy, $0.speedAccuracy) },
            vehicleType: vehicleType,
            distanceKm: distanceKm,
            allowUnknownSpeedAccuracy: true
        )
    }

    private static func dynamics(
        points: [(timestamp: Date, speedKmh: Double, horizontalAccuracy: Double, speedAccuracy: Double)],
        vehicleType: VehicleType,
        distanceKm: Double,
        allowUnknownSpeedAccuracy: Bool
    ) -> DrivingDynamics? {
        let validPoints = points
            .filter { point in
                TripReliabilityRules.isValidSpeedAccuracy(point.horizontalAccuracy) &&
                    (TripReliabilityRules.isValidReportedSpeedAccuracy(point.speedAccuracy) ||
                        (allowUnknownSpeedAccuracy && point.speedAccuracy < 0)) &&
                    point.speedKmh.isFinite &&
                    point.speedKmh >= 0 &&
                    point.speedKmh <= TripReliabilityRules.maximumReasonableSpeedKmh(for: vehicleType)
            }
            .sorted { $0.timestamp < $1.timestamp }

        guard validPoints.count >= 2 else {
            return nil
        }

        var analyzedDuration: TimeInterval = 0
        var idleDuration: TimeInterval = 0
        var movingSpeedWeightedSum = 0.0
        var movingDuration: TimeInterval = 0
        var hardAccelerations = 0
        var hardBrakings = 0
        var positiveAccelerationSquaredSum = 0.0
        var positiveAccelerationDuration: TimeInterval = 0

        for (previous, current) in zip(validPoints, validPoints.dropFirst()) {
            let interval = current.timestamp.timeIntervalSince(previous.timestamp)
            guard interval >= minimumPairInterval, interval <= maximumPairInterval else {
                continue
            }

            analyzedDuration += interval
            let averageSpeedKmh = (previous.speedKmh + current.speedKmh) / 2
            if averageSpeedKmh < idleSpeedThresholdKmh {
                idleDuration += interval
            } else {
                movingSpeedWeightedSum += averageSpeedKmh * interval
                movingDuration += interval
            }

            let accelerationMs2 = (current.speedKmh - previous.speedKmh) / 3.6 / interval
            if accelerationMs2 >= hardAccelerationThreshold {
                hardAccelerations += 1
            } else if accelerationMs2 <= hardBrakingThreshold {
                hardBrakings += 1
            }
            if accelerationMs2 > 0 {
                positiveAccelerationSquaredSum += accelerationMs2 * accelerationMs2 * interval
                positiveAccelerationDuration += interval
            }
        }

        guard analyzedDuration >= minimumAnalyzedDuration else {
            return nil
        }

        let accelerationRms = positiveAccelerationDuration > 0
            ? (positiveAccelerationSquaredSum / positiveAccelerationDuration).squareRoot()
            : 0

        return DrivingDynamics(
            meanMovingSpeedKmh: movingDuration > 0 ? movingSpeedWeightedSum / movingDuration : 0,
            idleRatio: idleDuration / analyzedDuration,
            hardAccelerationCount: hardAccelerations,
            hardBrakingCount: hardBrakings,
            accelerationRms: accelerationRms,
            analyzedDurationSec: analyzedDuration,
            distanceKm: distanceKm
        )
    }
}

extension DrivingDynamics {
    /// Multiplicateur applique a la consommation constructeur (cycle mixte).
    /// Chaque composante est bornee pour rester une estimation credible :
    /// - profil de vitesse : le stop-and-go urbain et la tres haute vitesse
    ///   consomment plus que le cycle mixte de la fiche technique ;
    /// - agressivite : accelerations soutenues = surconsommation ;
    /// - ralenti : du carburant brule sans kilometre parcouru.
    var fuelConsumptionMultiplier: Double {
        let speedFactor: Double
        switch meanMovingSpeedKmh {
        case ..<20: speedFactor = 1.20
        case 20..<35: speedFactor = 1.12
        case 35..<55: speedFactor = 1.05
        case 55..<90: speedFactor = 1.0
        case 90..<110: speedFactor = 1.05
        default: speedFactor = 1.12
        }

        let smoothRms = 0.5
        let aggressivenessFactor = accelerationRms <= smoothRms
            ? 0.97
            : min(1.25, 1.0 + (accelerationRms - smoothRms) * 0.25)

        let idleFactor = 1.0 + min(idleRatio, 0.5) * 0.2

        let eventsFactor: Double
        if let eventsPer10Km = abruptEventsPer10Km {
            eventsFactor = 1.0 + min(eventsPer10Km * 0.01, 0.10)
        } else {
            eventsFactor = 1.0
        }

        let combined = speedFactor * aggressivenessFactor * idleFactor * eventsFactor
        return min(1.5, max(0.85, combined))
    }
}
