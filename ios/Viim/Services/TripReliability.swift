import CoreLocation
import Foundation

enum MetricConfidence: String, Equatable {
    case reliable
    case partial
    case needsInput
    case unavailable
    case needsReview
}

enum MetricReasonCode: String, Equatable {
    case complete
    case partialSpeedOnly
    case fuelEstimated
    case fuelInputMissing
    case gpsInsufficient
    case gpsAccuracyTooLow
    case impossibleSpeed
    case tripTooShort
    case tripNeedsReview
    case scoreUnavailable
    case syncEngineMissing

    var shortLocalizationKey: String {
        switch self {
        case .complete:
            return "metric.reason.complete.short"
        case .partialSpeedOnly:
            return "metric.reason.partialSpeedOnly.short"
        case .fuelEstimated:
            return "metric.reason.fuelEstimated.short"
        case .fuelInputMissing:
            return "metric.reason.fuelInputMissing.short"
        case .gpsInsufficient:
            return "metric.reason.gpsInsufficient.short"
        case .gpsAccuracyTooLow:
            return "metric.reason.gpsAccuracyTooLow.short"
        case .impossibleSpeed:
            return "metric.reason.impossibleSpeed.short"
        case .tripTooShort:
            return "metric.reason.tripTooShort.short"
        case .tripNeedsReview:
            return "metric.reason.tripNeedsReview.short"
        case .scoreUnavailable:
            return "metric.reason.scoreUnavailable.short"
        case .syncEngineMissing:
            return "metric.reason.syncEngineMissing.short"
        }
    }

    var detailLocalizationKey: String {
        switch self {
        case .complete:
            return "metric.reason.complete.detail"
        case .partialSpeedOnly:
            return "metric.reason.partialSpeedOnly.detail"
        case .fuelEstimated:
            return "metric.reason.fuelEstimated.detail"
        case .fuelInputMissing:
            return "metric.reason.fuelInputMissing.detail"
        case .gpsInsufficient:
            return "metric.reason.gpsInsufficient.detail"
        case .gpsAccuracyTooLow:
            return "metric.reason.gpsAccuracyTooLow.detail"
        case .impossibleSpeed:
            return "metric.reason.impossibleSpeed.detail"
        case .tripTooShort:
            return "metric.reason.tripTooShort.detail"
        case .tripNeedsReview:
            return "metric.reason.tripNeedsReview.detail"
        case .scoreUnavailable:
            return "metric.reason.scoreUnavailable.detail"
        case .syncEngineMissing:
            return "metric.reason.syncEngineMissing.detail"
        }
    }
}

struct ReliableMetric<Value: Equatable>: Equatable {
    let value: Value?
    let confidence: MetricConfidence
    let reasonCode: MetricReasonCode
    let source: String
    let formulaVersion: String

    static func reliable(
        _ value: Value,
        source: String,
        formulaVersion: String,
        reasonCode: MetricReasonCode = .complete
    ) -> ReliableMetric<Value> {
        ReliableMetric(
            value: value,
            confidence: .reliable,
            reasonCode: reasonCode,
            source: source,
            formulaVersion: formulaVersion
        )
    }

    static func missing(
        confidence: MetricConfidence,
        reasonCode: MetricReasonCode,
        source: String,
        formulaVersion: String
    ) -> ReliableMetric<Value> {
        ReliableMetric(
            value: nil,
            confidence: confidence,
            reasonCode: reasonCode,
            source: source,
            formulaVersion: formulaVersion
        )
    }
}

enum TripReliabilityRules {
    static let minimumPersistedTripDistanceMeters: CLLocationDistance = 80
    static let minimumPersistedTripDuration: TimeInterval = 60
    static let minimumValidRoutePoints = 2
    static let maximumRouteHorizontalAccuracy: CLLocationAccuracy = 100
    static let maximumSpeedHorizontalAccuracy: CLLocationAccuracy = 50
    static let maximumReportedSpeedAccuracy: CLLocationSpeedAccuracy = 3
    static let stationarySpeedThresholdKmh = 3.0

    static func isValidRouteAccuracy(_ accuracy: CLLocationAccuracy) -> Bool {
        accuracy >= 0 && accuracy <= maximumRouteHorizontalAccuracy
    }

    static func isValidSpeedAccuracy(_ accuracy: CLLocationAccuracy) -> Bool {
        accuracy >= 0 && accuracy <= maximumSpeedHorizontalAccuracy
    }

    static func isValidReportedSpeedAccuracy(_ accuracy: CLLocationSpeedAccuracy) -> Bool {
        accuracy >= 0 && accuracy <= maximumReportedSpeedAccuracy
    }

    static func maximumReasonableSpeedKmh(for vehicleType: VehicleType) -> Double {
        switch vehicleType {
        case .moto:
            return 160
        case .voiture:
            return 220
        case .velo:
            return 70
        }
    }

    static func hasReliableMovementSpeed(_ sample: LocationSample) -> Bool {
        sample.speedKmh.isFinite &&
            sample.speedKmh > stationarySpeedThresholdKmh &&
            isValidSpeedAccuracy(sample.horizontalAccuracy) &&
            isValidReportedSpeedAccuracy(sample.speedAccuracy)
    }

    static func combinedHorizontalUncertaintyMeters(
        previous: LocationSample,
        current: LocationSample
    ) -> CLLocationDistance {
        max(0, previous.horizontalAccuracy) + max(0, current.horizontalAccuracy)
    }
}

enum TripMetricsCalculator {
    static let formulaVersion = "trip-metrics-v2"

    static func persistabilityMetric(
        completedTrip: CompletedDetectedTrip,
        samples: [LocationSample],
        vehicleType: VehicleType
    ) -> ReliableMetric<Bool> {
        let duration = durationMetric(completedTrip: completedTrip)
        guard duration.value != nil else {
            return .missing(
                confidence: .unavailable,
                reasonCode: duration.reasonCode,
                source: "LocationService",
                formulaVersion: formulaVersion
            )
        }

        let distance = distanceMetric(samples: samples, vehicleType: vehicleType)
        guard distance.value != nil else {
            return .missing(
                confidence: distance.confidence,
                reasonCode: distance.reasonCode,
                source: "LocationService",
                formulaVersion: formulaVersion
            )
        }

        return .reliable(
            true,
            source: "LocationService",
            formulaVersion: formulaVersion
        )
    }

    static func shouldPersist(
        completedTrip: CompletedDetectedTrip,
        samples: [LocationSample],
        vehicleType: VehicleType
    ) -> Bool {
        persistabilityMetric(
            completedTrip: completedTrip,
            samples: samples,
            vehicleType: vehicleType
        ).value == true
    }

    static func durationMetric(completedTrip: CompletedDetectedTrip) -> ReliableMetric<TimeInterval> {
        let duration = completedTrip.duration
        guard duration.isFinite,
              duration >= TripReliabilityRules.minimumPersistedTripDuration else {
            return .missing(
                confidence: .unavailable,
                reasonCode: .tripTooShort,
                source: "LocationService.completedTrip",
                formulaVersion: formulaVersion
            )
        }

        return .reliable(
            duration,
            source: "LocationService.completedTrip",
            formulaVersion: formulaVersion
        )
    }

    static func distanceMetric(
        samples: [LocationSample],
        vehicleType: VehicleType
    ) -> ReliableMetric<CLLocationDistance> {
        let validSamples = validRouteSamples(from: samples)
        guard validSamples.count >= TripReliabilityRules.minimumValidRoutePoints else {
            return .missing(
                confidence: .unavailable,
                reasonCode: .gpsInsufficient,
                source: "LocationService.samples",
                formulaVersion: formulaVersion
            )
        }

        let analysis = distanceAnalysis(samples: validSamples, vehicleType: vehicleType)
        let totalDistance = analysis.distanceMeters
        let validSegmentCount = analysis.validSegmentCount

        guard validSegmentCount > 0 else {
            return .missing(
                confidence: analysis.rejectedSegmentCount > 0 ? .needsReview : .unavailable,
                reasonCode: analysis.rejectedSegmentCount > 0 ? .impossibleSpeed : .gpsInsufficient,
                source: "LocationService.samples",
                formulaVersion: formulaVersion
            )
        }

        guard totalDistance >= TripReliabilityRules.minimumPersistedTripDistanceMeters else {
            return .missing(
                confidence: .unavailable,
                reasonCode: .tripTooShort,
                source: "LocationService.samples",
                formulaVersion: formulaVersion
            )
        }

        return .reliable(
            totalDistance,
            source: "LocationService.samples",
            formulaVersion: formulaVersion
        )
    }

    static func validRoutePoints(from samples: [LocationSample]) -> [TripRoutePoint] {
        validRouteSamples(from: samples).map { sample in
            return TripRoutePoint(
                timestamp: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude,
                speedKmh: sample.speedKmh,
                horizontalAccuracy: sample.horizontalAccuracy,
                speedAccuracy: sample.speedAccuracy
            )
        }
    }

    static func segmentDistanceMeters(
        previous: LocationSample,
        current: LocationSample,
        vehicleType: VehicleType
    ) -> CLLocationDistance? {
        guard coordinatesAreValid(previous),
              coordinatesAreValid(current) else {
            return nil
        }

        // Double chronologie : iOS peut relivrer une rafale mise en file avec
        // des timestamps GPS compresses sur quelques secondes alors que la
        // reception s'etale sur plusieurs minutes. La chronologie la plus
        // longue est la seule plausible pour juger la vitesse du segment.
        let gpsElapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        let receiptElapsed = current.receivedAt.timeIntervalSince(previous.receivedAt)
        let elapsed = max(gpsElapsed, receiptElapsed)
        guard elapsed > 0 else {
            return nil
        }

        let previousLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
        let currentLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
        let distance = previousLocation.distance(from: currentLocation)
        let segmentSpeedKmh = distance / elapsed * 3.6
        guard segmentSpeedKmh.isFinite,
              segmentSpeedKmh <= TripReliabilityRules.maximumReasonableSpeedKmh(for: vehicleType) else {
            return nil
        }

        // Un deplacement qui reste a l'interieur des deux rayons d'erreur GPS
        // n'est pas une distance parcourue tant qu'aucune vitesse fiable ne
        // prouve le mouvement. Cette regle elimine la derive stationnaire sans
        // retrancher de metres aux segments de conduite confirmes.
        let hasReliableMovementSpeed =
            TripReliabilityRules.hasReliableMovementSpeed(previous) ||
            TripReliabilityRules.hasReliableMovementSpeed(current)
        let uncertaintyMeters = TripReliabilityRules.combinedHorizontalUncertaintyMeters(
            previous: previous,
            current: current
        )
        if !hasReliableMovementSpeed, distance <= uncertaintyMeters {
            return 0
        }

        return max(0, distance)
    }

    static func validRoutePoints(from points: [TripRoutePoint]) -> [TripRoutePoint] {
        points.filter { point in
            TripReliabilityRules.isValidRouteAccuracy(point.horizontalAccuracy)
        }
    }

    static func routeMetric(points: [TripRoutePoint]) -> ReliableMetric<Int> {
        let validPoints = validRoutePoints(from: points)
        guard validPoints.count >= TripReliabilityRules.minimumValidRoutePoints else {
            return .missing(
                confidence: .unavailable,
                reasonCode: .gpsInsufficient,
                source: "TripStore.polyline",
                formulaVersion: formulaVersion
            )
        }

        return .reliable(
            validPoints.count,
            source: "TripStore.polyline",
            formulaVersion: formulaVersion
        )
    }

    static func maxSpeedMetric(samples: [LocationSample], vehicleType: VehicleType) -> ReliableMetric<Double> {
        return maxSpeedMetric(
            speeds: samples.map { ($0.speedKmh, $0.horizontalAccuracy, $0.speedAccuracy) },
            vehicleType: vehicleType,
            source: "LocationService.samples"
        )
    }

    static func maxSpeedMetric(for trip: TripRecord) -> ReliableMetric<Double> {
        guard trip.isTrustedForDisplay else {
            return .missing(
                confidence: .needsReview,
                reasonCode: .tripNeedsReview,
                source: "TripStore.quality",
                formulaVersion: trip.qualityFormulaVersion
            )
        }
        return maxSpeedMetric(
            speeds: trip.routePoints.map { ($0.speedKmh, $0.horizontalAccuracy, $0.speedAccuracy) },
            vehicleType: trip.vehicleType,
            source: "TripStore.polyline"
        )
    }

    static func scoreMetric(for trip: TripRecord) -> ReliableMetric<Int> {
        guard trip.isTrustedForDisplay else {
            return .missing(
                confidence: .needsReview,
                reasonCode: .tripNeedsReview,
                source: "TripStore.quality",
                formulaVersion: trip.qualityFormulaVersion
            )
        }
        guard let score = trip.score else {
            return .missing(
                confidence: .unavailable,
                reasonCode: .scoreUnavailable,
                source: "ScoreEngine",
                formulaVersion: ScoreEngine.version
            )
        }

        let subScores = [
            trip.scoreVitesse,
            trip.scoreFluidite,
            trip.scoreEco
        ]
        let availableSubScoreCount = subScores.compactMap { $0 }.count

        if availableSubScoreCount < subScores.count {
            return ReliableMetric(
                value: score,
                confidence: .partial,
                reasonCode: .partialSpeedOnly,
                source: "ScoreEngine",
                formulaVersion: ScoreEngine.version
            )
        }

        return .reliable(
            score,
            source: "ScoreEngine",
            formulaVersion: ScoreEngine.version
        )
    }

    static func summaryScoreMetric(_ summary: DrivingSummary) -> ReliableMetric<Int> {
        guard let score = summary.avgScore else {
            return .missing(
                confidence: .unavailable,
                reasonCode: .scoreUnavailable,
                source: "TripStore.summary",
                formulaVersion: ScoreEngine.version
            )
        }

        let availableCriteria = [
            summary.avgScoreVitesse,
            summary.avgScoreFluidite,
            summary.avgScoreEco
        ].compactMap { $0 }.count
        if availableCriteria == 3 {
            return .reliable(
                score,
                source: "TripStore.summary",
                formulaVersion: ScoreEngine.version
            )
        }
        return ReliableMetric(
            value: score,
            confidence: .partial,
            reasonCode: .partialSpeedOnly,
            source: "TripStore.summary",
            formulaVersion: ScoreEngine.version
        )
    }

    static func summarySpeedScoreMetric(_ summary: DrivingSummary) -> ReliableMetric<Int> {
        guard let score = summary.avgScoreVitesse else {
            return .missing(
                confidence: .unavailable,
                reasonCode: .scoreUnavailable,
                source: "TripStore.summary.scoreVitesse",
                formulaVersion: ScoreEngine.version
            )
        }
        return ReliableMetric(
            value: score,
            confidence: .partial,
            reasonCode: .partialSpeedOnly,
            source: "TripStore.summary.scoreVitesse",
            formulaVersion: ScoreEngine.version
        )
    }

    static func fuelCostMetric(for trip: TripRecord) -> ReliableMetric<Int> {
        guard trip.isTrustedForDisplay else {
            return .missing(
                confidence: .needsReview,
                reasonCode: .tripNeedsReview,
                source: "TripStore.quality",
                formulaVersion: trip.qualityFormulaVersion
            )
        }
        if let amount = trip.fuelCostMinorUnits,
           trip.fuelCurrency != nil {
            if trip.vehicleType == .velo {
                return .reliable(
                    amount,
                    source: "TripStore.fuelCostSnapshot",
                    formulaVersion: trip.qualityFormulaVersion
                )
            }
            return ReliableMetric(
                value: amount,
                confidence: .partial,
                reasonCode: .fuelEstimated,
                source: "TripStore.fuelCostSnapshot",
                formulaVersion: VehicleFuelCatalog.formulaVersion
            )
        }

        return .missing(
            confidence: .needsInput,
            reasonCode: .fuelInputMissing,
            source: "TripStore.fuelCostSnapshot",
            formulaVersion: trip.fuelFormulaVersion
        )
    }

    static func summaryFuelCostMetric(_ summary: DrivingSummary) -> ReliableMetric<Int> {
        guard let amount = summary.fuelCostMinorUnits,
              summary.fuelCurrency != nil else {
            return .missing(
                confidence: .needsInput,
                reasonCode: .fuelInputMissing,
                source: "TripStore.summary.fuelCostSnapshots",
                formulaVersion: VehicleFuelCatalog.formulaVersion
            )
        }
        return ReliableMetric(
            value: amount,
            confidence: .partial,
            reasonCode: .fuelEstimated,
            source: "TripStore.summary.fuelCostSnapshots",
            formulaVersion: VehicleFuelCatalog.formulaVersion
        )
    }

    private static func maxSpeedMetric(
        speeds: [(
            speedKmh: Double,
            horizontalAccuracy: CLLocationAccuracy,
            speedAccuracy: CLLocationSpeedAccuracy
        )],
        vehicleType: VehicleType,
        source: String
    ) -> ReliableMetric<Double> {
        let accurateSpeeds = speeds.filter { speed in
            TripReliabilityRules.isValidSpeedAccuracy(speed.horizontalAccuracy) &&
                TripReliabilityRules.isValidReportedSpeedAccuracy(speed.speedAccuracy)
        }

        guard !accurateSpeeds.isEmpty else {
            return .missing(
                confidence: .unavailable,
                reasonCode: .gpsAccuracyTooLow,
                source: source,
                formulaVersion: formulaVersion
            )
        }

        let maximumReasonableSpeed = TripReliabilityRules.maximumReasonableSpeedKmh(for: vehicleType)
        if accurateSpeeds.contains(where: { !$0.speedKmh.isFinite || $0.speedKmh < 0 || $0.speedKmh > maximumReasonableSpeed }) {
            return .missing(
                confidence: .needsReview,
                reasonCode: .impossibleSpeed,
                source: source,
                formulaVersion: formulaVersion
            )
        }

        guard let maxSpeed = accurateSpeeds.map({ $0.speedKmh }).max() else {
            return .missing(
                confidence: .unavailable,
                reasonCode: .gpsAccuracyTooLow,
                source: source,
                formulaVersion: formulaVersion
            )
        }

        return .reliable(
            maxSpeed,
            source: source,
            formulaVersion: formulaVersion
        )
    }

    static func validRouteSamples(from samples: [LocationSample]) -> [LocationSample] {
        samples
            .filter { sample in
                TripReliabilityRules.isValidRouteAccuracy(sample.horizontalAccuracy) &&
                    coordinatesAreValid(sample)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private static func coordinatesAreValid(_ sample: LocationSample) -> Bool {
        sample.latitude.isFinite &&
            sample.longitude.isFinite &&
            (-90...90).contains(sample.latitude) &&
            (-180...180).contains(sample.longitude)
    }

    static func distanceAnalysis(
        samples validSamples: [LocationSample],
        vehicleType: VehicleType
    ) -> (
        distanceMeters: CLLocationDistance,
        validSegmentCount: Int,
        rejectedSegmentCount: Int,
        totalSegmentCount: Int
    ) {
        var totalDistance: CLLocationDistance = 0
        var validSegmentCount = 0
        var rejectedSegmentCount = 0

        // Parcours par ancre : un point aberrant est saute sans devenir la
        // reference du segment suivant. Un glitch isole ne coute qu'un segment
        // rejete et la distance reelle entre les points qui l'encadrent est
        // conservee.
        var anchor = validSamples.first
        for current in validSamples.dropFirst() {
            guard let previous = anchor else {
                anchor = current
                continue
            }

            guard let distance = segmentDistanceMeters(
                previous: previous,
                current: current,
                vehicleType: vehicleType
            ) else {
                rejectedSegmentCount += 1
                continue
            }

            totalDistance += distance
            validSegmentCount += 1
            // Un segment nul represente une variation encore contenue dans
            // l'incertitude GPS. Garder l'ancre permet au mouvement reel de
            // s'accumuler jusqu'a devenir mesurable, notamment a faible vitesse.
            if distance > 0 {
                anchor = current
            }
        }

        return (
            distanceMeters: totalDistance,
            validSegmentCount: validSegmentCount,
            rejectedSegmentCount: rejectedSegmentCount,
            totalSegmentCount: validSegmentCount + rejectedSegmentCount
        )
    }
}
