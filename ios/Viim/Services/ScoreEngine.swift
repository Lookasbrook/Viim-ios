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
    static let version = "score-speed-fluidity-eco-v3"

    private static let speedToleranceKmh = 5.0
    private static let speedPenaltyPerKmh = 2.5
    private static let sustainedOverspeedDuration: TimeInterval = 10
    private static let maximumOverspeedSampleGap: TimeInterval = 30
    private static let abruptEventPenaltyPer10Km = 8.0

    static func scores(
        for completedTrip: CompletedDetectedTrip,
        samples: [LocationSample],
        vehicleType: VehicleType
    ) -> TripScores {
        let scoreSpeedMetric = scoreSpeedMetric(
            samples: samples,
            vehicleType: vehicleType
        )
        guard let maxSpeedKmh = scoreSpeedMetric.value else {
            return .unavailable
        }

        let dynamics = DrivingDynamicsAnalyzer.dynamics(
            samples: samples,
            vehicleType: vehicleType,
            distanceKm: completedTrip.distanceMeters / 1_000
        )
        return scores(maxSpeedKmh: maxSpeedKmh, vehicleType: vehicleType, dynamics: dynamics)
    }

    static func scores(
        maxSpeedKmh: Double,
        vehicleType: VehicleType,
        dynamics: DrivingDynamics? = nil
    ) -> TripScores {
        let speed = speedScore(maxSpeedKmh: maxSpeedKmh, vehicleType: vehicleType)
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

    /// Fluidite : penalise les accelerations franches et freinages brusques,
    /// normalises par la distance pour ne pas punir les longs trajets.
    private static func fluidityScore(dynamics: DrivingDynamics?) -> Int? {
        guard let dynamics,
              let eventsPer10Km = dynamics.abruptEventsPer10Km else {
            return nil
        }

        return clampedScore(100 - Int((eventsPer10Km * abruptEventPenaltyPer10Km).rounded()))
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

    private static func scoreSpeedMetric(
        samples: [LocationSample],
        vehicleType: VehicleType
    ) -> ReliableMetric<Double> {
        let accurateSamples = samples
            .filter { sample in
                TripReliabilityRules.isValidSpeedAccuracy(sample.horizontalAccuracy) &&
                    TripReliabilityRules.isValidReportedSpeedAccuracy(sample.speedAccuracy) &&
                    sample.speedKmh.isFinite &&
                    sample.speedKmh >= 0 &&
                    sample.speedKmh <= TripReliabilityRules.maximumReasonableSpeedKmh(for: vehicleType)
            }
            .sorted { $0.timestamp < $1.timestamp }

        guard !accurateSamples.isEmpty else {
            return .missing(
                confidence: .unavailable,
                reasonCode: .gpsAccuracyTooLow,
                source: "LocationService.samples",
                formulaVersion: TripMetricsCalculator.formulaVersion
            )
        }

        let threshold = speedLimitKmh(for: vehicleType) + speedToleranceKmh
        var overspeedStart: Date?
        var previousOverspeedSampleDate: Date?
        var windowMaxSpeed = 0.0
        var sustainedMaxSpeed: Double?

        for sample in accurateSamples {
            if sample.speedKmh > threshold {
                if let previousOverspeedSampleDate,
                   sample.timestamp.timeIntervalSince(previousOverspeedSampleDate) > maximumOverspeedSampleGap {
                    overspeedStart = nil
                    windowMaxSpeed = 0
                }
                if overspeedStart == nil {
                    overspeedStart = sample.timestamp
                    windowMaxSpeed = sample.speedKmh
                } else {
                    windowMaxSpeed = max(windowMaxSpeed, sample.speedKmh)
                }

                if let overspeedStart,
                   sample.timestamp.timeIntervalSince(overspeedStart) >= sustainedOverspeedDuration {
                    sustainedMaxSpeed = max(sustainedMaxSpeed ?? windowMaxSpeed, windowMaxSpeed)
                }
                previousOverspeedSampleDate = sample.timestamp
            } else {
                overspeedStart = nil
                previousOverspeedSampleDate = nil
                windowMaxSpeed = 0
            }
        }

        let maxSpeed = accurateSamples.map(\.speedKmh).max() ?? 0
        return .reliable(
            sustainedMaxSpeed ?? min(maxSpeed, threshold),
            source: "LocationService.samples",
            formulaVersion: version
        )
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
