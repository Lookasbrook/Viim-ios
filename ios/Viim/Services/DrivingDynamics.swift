import CoreLocation
import Foundation

/// Resume de la dynamique reelle d'un trajet, derive des vitesses GPS
/// horodatees. Sert a moduler l'estimation carburant et a calculer les
/// scores de fluidite et d'eco-conduite : un meme kilometrage ne coute
/// pas pareil selon les variations de vitesse et le temps a tres basse vitesse.
struct DrivingDynamics: Equatable {
    /// Vitesse moyenne pendant les phases de deplacement (km/h).
    let meanMovingSpeedKmh: Double
    /// Fraction du temps analyse passee quasi a l'arret. L'etat moteur est inconnu.
    let idleRatio: Double
    /// Variations positives de vitesse GPS compatibles avec une acceleration franche.
    let hardAccelerationCount: Int
    /// Variations negatives de vitesse GPS compatibles avec un freinage brusque.
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

    /// Les valeurs de dynamique peuvent aussi provenir de trajets historiques.
    /// Refuser toute valeur incoherente evite qu'un NaN ou un snapshot corrompu
    /// contamine les litres et le cout persistants.
    var isUsableForFuelEstimate: Bool {
        meanMovingSpeedKmh.isFinite && meanMovingSpeedKmh >= 0 &&
            idleRatio.isFinite && (0...1).contains(idleRatio) &&
            hardAccelerationCount >= 0 && hardBrakingCount >= 0 &&
            accelerationRms.isFinite && accelerationRms >= 0 &&
            analyzedDurationSec.isFinite &&
            analyzedDurationSec >= DrivingDynamicsAnalyzer.minimumAnalyzedDuration &&
            distanceKm.isFinite && distanceKm > 0
    }
}

enum DrivingDynamicsAnalyzer {
    static let formulaVersion = "driving-dynamics-v1"

    /// Seuils issus des standards telematiques assurantiels (m/s2).
    static let hardAccelerationThreshold = 2.5
    static let hardBrakingThreshold = -3.0
    /// En dessous, le vehicule est considere quasi a l'arret par le GPS.
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
    /// - faible vitesse / arret : proxy GPS du stop-and-go. Le telephone ne
    ///   sait pas si le moteur tourne, ce facteur reste donc volontairement
    ///   faible et ne doit pas etre presente comme du ralenti mesure.
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

struct ElevationProfile: Equatable {
    let gainMeters: Double
    let lossMeters: Double
    let analyzedDistanceMeters: Double
    let coverageRatio: Double
}

/// Produit un denivele conservateur a partir de l'altitude GPS. L'analyse se
/// fait sur des fenetres longues afin de ne pas additionner le bruit vertical
/// de chaque point comme s'il s'agissait de petites montees successives.
enum ElevationProfileAnalyzer {
    static let formulaVersion = "elevation-profile-v1-conservative"
    static let maximumVerticalAccuracyMeters = 20.0
    static let minimumWindowDistanceMeters = 150.0
    static let maximumSegmentDistanceMeters = 500.0
    static let minimumAnalyzedDistanceMeters = 300.0
    static let minimumCoverageRatio = 0.5
    static let maximumPlausibleGrade = 0.25

    static func profile(
        samples: [LocationSample],
        referenceDistanceKm: Double
    ) -> ElevationProfile? {
        profile(
            points: samples.map {
                ElevationPoint(
                    timestamp: $0.timestamp,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    horizontalAccuracy: $0.horizontalAccuracy,
                    altitudeMeters: $0.altitudeMeters,
                    verticalAccuracy: $0.verticalAccuracy
                )
            },
            referenceDistanceKm: referenceDistanceKm
        )
    }

    static func profile(
        routePoints: [TripRoutePoint],
        referenceDistanceKm: Double
    ) -> ElevationProfile? {
        profile(
            points: routePoints.map {
                ElevationPoint(
                    timestamp: $0.timestamp,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    horizontalAccuracy: $0.horizontalAccuracy,
                    altitudeMeters: $0.altitudeMeters,
                    verticalAccuracy: $0.verticalAccuracy
                )
            },
            referenceDistanceKm: referenceDistanceKm
        )
    }

    private static func profile(
        points: [ElevationPoint],
        referenceDistanceKm: Double
    ) -> ElevationProfile? {
        guard referenceDistanceKm.isFinite, referenceDistanceKm > 0 else {
            return nil
        }

        let validPoints = points
            .filter(\.isUsable)
            .sorted { $0.timestamp < $1.timestamp }
        guard validPoints.count >= 2 else {
            return nil
        }

        var windowStart = validPoints[0]
        var previous = validPoints[0]
        var windowDistance = 0.0
        var analyzedDistance = 0.0
        var gain = 0.0
        var loss = 0.0

        for current in validPoints.dropFirst() {
            let segmentDistance = previous.location.distance(from: current.location)
            previous = current

            guard segmentDistance.isFinite,
                  segmentDistance > 0,
                  segmentDistance <= maximumSegmentDistanceMeters else {
                windowStart = current
                windowDistance = 0
                continue
            }

            windowDistance += segmentDistance
            guard windowDistance >= minimumWindowDistanceMeters else {
                continue
            }

            let altitudeDelta = current.altitude - windowStart.altitude
            let grade = altitudeDelta / windowDistance
            guard grade.isFinite, abs(grade) <= maximumPlausibleGrade else {
                windowStart = current
                windowDistance = 0
                continue
            }

            // Retrancher l'incertitude plutot que la compter comme denivele.
            // Le resultat sous-estime parfois une pente douce, mais n'invente
            // pas des dizaines de metres sur une route plate.
            let uncertainty = max(windowStart.verticalAccuracy, current.verticalAccuracy)
            let conservativeDelta = max(0, abs(altitudeDelta) - uncertainty)
            if altitudeDelta > 0 {
                gain += conservativeDelta
            } else if altitudeDelta < 0 {
                loss += conservativeDelta
            }
            analyzedDistance += windowDistance
            windowStart = current
            windowDistance = 0
        }

        let referenceDistanceMeters = referenceDistanceKm * 1_000
        let coverageRatio = min(1, analyzedDistance / referenceDistanceMeters)
        guard analyzedDistance >= minimumAnalyzedDistanceMeters,
              coverageRatio >= minimumCoverageRatio else {
            return nil
        }

        return ElevationProfile(
            gainMeters: gain,
            lossMeters: loss,
            analyzedDistanceMeters: analyzedDistance,
            coverageRatio: coverageRatio
        )
    }

    private struct ElevationPoint {
        let timestamp: Date
        let latitude: Double
        let longitude: Double
        let horizontalAccuracy: Double
        let altitudeMeters: Double?
        let verticalAccuracy: Double

        var altitude: Double {
            altitudeMeters ?? 0
        }

        var location: CLLocation {
            CLLocation(latitude: latitude, longitude: longitude)
        }

        var isUsable: Bool {
            guard let altitudeMeters else {
                return false
            }
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            return CLLocationCoordinate2DIsValid(coordinate) &&
                horizontalAccuracy.isFinite && horizontalAccuracy >= 0 && horizontalAccuracy <= 100 &&
                altitudeMeters.isFinite &&
                verticalAccuracy.isFinite && verticalAccuracy >= 0 &&
                verticalAccuracy <= ElevationProfileAnalyzer.maximumVerticalAccuracyMeters
        }
    }
}
