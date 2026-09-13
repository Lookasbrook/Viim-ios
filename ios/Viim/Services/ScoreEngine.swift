import Foundation

struct TripScores: Equatable {
    let score: Int?
    let scoreVitesse: Int?
    let scoreFluidite: Int?
    let scoreVigilance: Int?
    let scoreEco: Int?

    static let unavailable = TripScores(
        score: nil,
        scoreVitesse: nil,
        scoreFluidite: nil,
        scoreVigilance: nil,
        scoreEco: nil
    )
}

enum ScoreEngine {
    static let version = "score-speed-fluidity-eco-v6-coverage"
    static let minimumTemporalCoverageRatio = 0.80

    private static let speedToleranceKmh = 5.0
    private static let speedPenaltyPerKmh = 2.5
    private static let maximumOverspeedSampleGap: TimeInterval = 30
    private static let minimumOverspeedSampleGap: TimeInterval = 0.4
    private static let abruptEventPenaltyPer10Km = 8.0

    /// Au-dela de la tolerance, un exces de cette ampleur (km/h) est traite
    /// comme un depassement « ordinaire » : la severite vaut alors 1.
    private static let overspeedReferenceExcessKmh = 12.0
    private static let minimumOverspeedSeverity = 0.6
    private static let maximumOverspeedSeverity = 1.8

    /// En dessous de ce RMS d'acceleration positive (m/s2), le profil est
    /// considere lisse : bruit GPS residuel d'une conduite souple.
    private static let fluidityRmsFloor = 0.4
    private static let fluidityRmsPenaltyFactor = 22.0

    static func scores(
        for completedTrip: CompletedDetectedTrip,
        samples: [LocationSample],
        vehicleType: VehicleType
    ) -> TripScores {
        let boundedSamples = samples.filter {
            $0.timestamp >= completedTrip.startedAt && $0.timestamp <= completedTrip.endedAt
        }
        guard let speed = timeWeightedSpeedScore(
            samples: boundedSamples,
            duration: completedTrip.duration,
            vehicleType: vehicleType
        ) else {
            return .unavailable
        }

        let dynamics = DrivingDynamicsAnalyzer.dynamics(
            samples: boundedSamples,
            vehicleType: vehicleType,
            distanceKm: completedTrip.distanceMeters / 1_000
        )
        return assemble(speed: speed, dynamics: dynamics)
    }

    static func scores(
        maxSpeedKmh: Double,
        vehicleType: VehicleType,
        dynamics: DrivingDynamics? = nil
    ) -> TripScores {
        assemble(
            speed: speedScore(maxSpeedKmh: maxSpeedKmh, vehicleType: vehicleType),
            dynamics: dynamics
        )
    }

    private static func assemble(speed: Int?, dynamics: DrivingDynamics?) -> TripScores {
        let fluidity = fluidityScore(dynamics: dynamics)
        let eco = ecoScore(dynamics: dynamics)
        let global = globalScore(from: [speed, fluidity, eco])

        return TripScores(
            score: global,
            scoreVitesse: speed,
            scoreFluidite: fluidity,
            scoreVigilance: nil,
            scoreEco: eco
        )
    }

    /// Vitesse : penalise en continu la part du trajet passee au-dessus du
    /// seuil technique, ponderee par l'ampleur du depassement. Les pointes GPS
    /// isolees sont absorbees par la moyenne de chaque paire d'echantillons ;
    /// sans couverture temporelle exploitable, le score reste indisponible
    /// plutot que d'afficher un 100 non fonde.
    private static func timeWeightedSpeedScore(
        samples: [LocationSample],
        duration: TimeInterval,
        vehicleType: VehicleType
    ) -> Int? {
        let accurateSamples = samples
            .filter { sample in
                TripReliabilityRules.isValidSpeedAccuracy(sample.horizontalAccuracy) &&
                    TripReliabilityRules.isValidReportedSpeedAccuracy(sample.speedAccuracy) &&
                    sample.speedKmh.isFinite &&
                    sample.speedKmh >= 0 &&
                    sample.speedKmh <= TripReliabilityRules.maximumReasonableSpeedKmh(for: vehicleType)
            }
            .sorted { $0.timestamp < $1.timestamp }

        guard accurateSamples.count >= 2 else {
            return nil
        }

        let threshold = speedLimitKmh(for: vehicleType) + speedToleranceKmh
        var analyzedSeconds = 0.0
        var overspeedSeconds = 0.0
        var excessIntegral = 0.0

        for (previous, current) in zip(accurateSamples, accurateSamples.dropFirst()) {
            let interval = current.timestamp.timeIntervalSince(previous.timestamp)
            let receiptInterval = current.receivedAt.timeIntervalSince(previous.receivedAt)
            guard interval >= minimumOverspeedSampleGap,
                  interval <= maximumOverspeedSampleGap,
                  receiptInterval >= 0,
                  receiptInterval <= maximumOverspeedSampleGap else {
                continue
            }

            let averageSpeed = (previous.speedKmh + current.speedKmh) / 2
            analyzedSeconds += interval
            if averageSpeed > threshold {
                overspeedSeconds += interval
                excessIntegral += (averageSpeed - threshold) * interval
            }
        }

        guard duration.isFinite, duration > 0,
              analyzedSeconds / duration >= minimumTemporalCoverageRatio else {
            // Des vitesses observees faibles ne prouvent rien pendant les
            // interruptions. Ne pas attribuer 100 a une trace clairsemee.
            return nil
        }

        let overspeedRatio = overspeedSeconds / analyzedSeconds
        let meanExcessWhileOver = overspeedSeconds > 0 ? excessIntegral / overspeedSeconds : 0
        let severity = min(
            maximumOverspeedSeverity,
            max(minimumOverspeedSeverity, meanExcessWhileOver / overspeedReferenceExcessKmh)
        )
        let penalty = overspeedRatio * 100 * severity
        return clampedScore(100 - Int(penalty.rounded()))
    }

    /// Fluidite : penalise les accelerations franches et freinages brusques,
    /// normalises par la distance, plus un terme continu tire du RMS des
    /// accelerations positives pour que la texture d'une conduite un peu
    /// nerveuse fasse bouger le score sans attendre un evenement « franc ».
    private static func fluidityScore(dynamics: DrivingDynamics?) -> Int? {
        guard let dynamics,
              let eventsPer10Km = dynamics.abruptEventsPer10Km else {
            return nil
        }

        let eventPenalty = eventsPer10Km * abruptEventPenaltyPer10Km
        let rmsExcess = max(0, dynamics.accelerationRms - fluidityRmsFloor)
        let rmsPenalty = rmsExcess * fluidityRmsPenaltyFactor
        return clampedScore(100 - Int((eventPenalty + rmsPenalty).rounded()))
    }

    /// Eco-conduite : derive du multiplicateur carburant. Une conduite au
    /// niveau du cycle mixte constructeur (multiplicateur <= 1) vaut 100 ;
    /// la borne haute (1.5) descend vers 40.
    private static func ecoScore(dynamics: DrivingDynamics?) -> Int? {
        guard let dynamics else {
            return nil
        }

        let overconsumption = max(0, dynamics.fuelConsumptionMultiplier - 1.0)
        return clampedScore(100 - Int((overconsumption * 120).rounded()))
    }

    private static func speedScore(maxSpeedKmh: Double, vehicleType: VehicleType) -> Int? {
        guard maxSpeedKmh.isFinite,
              maxSpeedKmh >= 0,
              maxSpeedKmh <= TripReliabilityRules.maximumReasonableSpeedKmh(for: vehicleType) else {
            return nil
        }

        let excessKmh = max(0, maxSpeedKmh - speedLimitKmh(for: vehicleType) - speedToleranceKmh)
        return clampedScore(100 - Int((excessKmh * speedPenaltyPerKmh).rounded()))
    }

    private static func speedLimitKmh(for vehicleType: VehicleType) -> Double {
        switch vehicleType {
        case .moto:
            return 80
        case .voiture:
            return 100
        case .velo:
            return 35
        }
    }

    private static func globalScore(from values: [Int?]) -> Int? {
        let availableValues = values.compactMap { $0 }
        guard !availableValues.isEmpty else {
            return nil
        }

        return Int((Double(availableValues.reduce(0, +)) / Double(availableValues.count)).rounded())
    }

    private static func clampedScore(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}
