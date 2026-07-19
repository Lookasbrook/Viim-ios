import CoreLocation
import Foundation

enum TripQualityConfidence: String, Equatable {
    case reliable
    case partial
    case needsReview
    case rejected
}

enum TripQualityReasonCode: String, Equatable, Hashable {
    case complete
    case tripTooShort
    case gpsInsufficient
    case gpsAccuracyTooLow
    case gpsCoverageIncomplete
    case impossibleSpeed
    case tooManyRejectedSegments
    case legacyUnverified
}

struct TripQualityReport: Equatable {
    let score: Int
    let confidence: TripQualityConfidence
    let reasonCodes: [TripQualityReasonCode]
    let activeDurationSec: Int
    let stationaryTailSec: Int
    let gpsAccuracyAvg: Double
    let gpsAccuracyP95: Double
    let rejectedSegmentCount: Int
    let validSegmentCount: Int
    let maxSampleGapSec: Double
    let p95SampleGapSec: Double
    let coverageRatio: Double
    let burstCount: Int
    let motionAgreementRate: Double?
    let formulaVersion: String

    var shouldPersist: Bool {
        confidence != .rejected
    }

    static let legacyUnverified = TripQualityReport(
        score: 0,
        confidence: .needsReview,
        reasonCodes: [.legacyUnverified],
        activeDurationSec: 0,
        stationaryTailSec: 0,
        gpsAccuracyAvg: -1,
        gpsAccuracyP95: -1,
        rejectedSegmentCount: 0,
        validSegmentCount: 0,
        maxSampleGapSec: 0,
        p95SampleGapSec: 0,
        coverageRatio: 0,
        burstCount: 0,
        motionAgreementRate: nil,
        formulaVersion: "legacy"
    )
}

enum TripQualityEngine {
    static let formulaVersion = "trip-quality-v4"

    private enum Constants {
        static let minimumQualityRoutePoints = 5
        static let maximumAverageAccuracyMeters: CLLocationAccuracy = 50
        static let maximumP95AccuracyMeters: CLLocationAccuracy = 100
        static let maximumRejectedSegmentRatio = 0.2
        static let maximumContinuousSampleGap: TimeInterval = 180
        static let severeSampleGap: TimeInterval = 600
        static let minimumCoverageRatio = 0.80
    }

    private struct ActivityWindow {
        let activeDuration: TimeInterval
        let stationaryTail: TimeInterval
    }

    private struct CoverageMetrics {
        let maxGap: TimeInterval
        let p95Gap: TimeInterval
        let ratio: Double
        let burstCount: Int
    }

    static func report(
        completedTrip: CompletedDetectedTrip,
        samples: [LocationSample],
        vehicleType: VehicleType
    ) -> TripQualityReport {
        let durationMetric = TripMetricsCalculator.durationMetric(completedTrip: completedTrip)
        let distanceMetric = TripMetricsCalculator.distanceMetric(samples: samples, vehicleType: vehicleType)
        let validSamples = TripMetricsCalculator.validRouteSamples(from: samples)
        let activityWindow = activityWindow(
            completedTrip: completedTrip,
            samples: validSamples,
            vehicleType: vehicleType
        )
        let accuracies = samples
            .map(\.horizontalAccuracy)
            .filter { $0.isFinite && $0 >= 0 }
        let gpsAccuracyAvg = average(accuracies) ?? -1
        let gpsAccuracyP95 = percentile(accuracies, percentile: 0.95) ?? -1
        let segmentCounts = countSegments(samples: validSamples, vehicleType: vehicleType)
        let coverage = coverageMetrics(
            samples: validSamples,
            startedAt: completedTrip.startedAt,
            activeDuration: activityWindow.activeDuration
        )

        var reasons: [TripQualityReasonCode] = []
        var penalty = 0
        var shouldReject = false

        if durationMetric.value == nil ||
            activityWindow.activeDuration < TripReliabilityRules.minimumPersistedTripDuration {
            penalty += 40
            shouldReject = true
            reasons.append(.tripTooShort)
        }

        if validSamples.count < Constants.minimumQualityRoutePoints {
            penalty += 30
            shouldReject = true
            reasons.append(.gpsInsufficient)
        }

        if gpsAccuracyAvg > Constants.maximumAverageAccuracyMeters {
            penalty += 15
            reasons.append(.gpsAccuracyTooLow)
        }

        if gpsAccuracyP95 > Constants.maximumP95AccuracyMeters {
            penalty += 30
            shouldReject = true
            reasons.append(.gpsAccuracyTooLow)
        }

        if segmentCounts.rejected > 0 {
            penalty += min(35, 10 + segmentCounts.rejected * 10)
            reasons.append(.impossibleSpeed)
        }

        if segmentCounts.total > 0 {
            let rejectedRatio = Double(segmentCounts.rejected) / Double(segmentCounts.total)
            if rejectedRatio > Constants.maximumRejectedSegmentRatio {
                penalty += 20
                shouldReject = true
                reasons.append(.tooManyRejectedSegments)
            }
        }


        // La precision de chaque point ne revele pas les periodes ou iOS n'a
        // livre aucun point. Une route avec plusieurs trous de 4-5 minutes ne
        // peut donc plus recevoir 100 %, meme si chaque fix isole est precis.
        if coverage.maxGap > Constants.maximumContinuousSampleGap {
            penalty += 20
            reasons.append(.gpsCoverageIncomplete)
        }
        if coverage.maxGap > Constants.severeSampleGap {
            penalty += 20
        }
        if coverage.ratio > 0, coverage.ratio < Constants.minimumCoverageRatio {
            penalty += 15
            reasons.append(.gpsCoverageIncomplete)
        }

        if distanceMetric.value == nil {
            penalty += 40
            shouldReject = true
            reasons.append(reasonCode(from: distanceMetric.reasonCode))
        }

        let score = max(0, min(100, 100 - penalty))
        let confidence: TripQualityConfidence
        if shouldReject || score < 50 {
            confidence = .rejected
        } else if score >= 85 {
            confidence = .reliable
        } else if score >= 65 {
            confidence = .partial
        } else {
            confidence = .needsReview
        }

        return TripQualityReport(
            score: score,
            confidence: confidence,
            reasonCodes: normalizedReasons(reasons),
            activeDurationSec: max(0, Int(activityWindow.activeDuration.rounded())),
            stationaryTailSec: max(0, Int(activityWindow.stationaryTail.rounded())),
            gpsAccuracyAvg: gpsAccuracyAvg,
            gpsAccuracyP95: gpsAccuracyP95,
            rejectedSegmentCount: segmentCounts.rejected,
            validSegmentCount: segmentCounts.valid,
            maxSampleGapSec: coverage.maxGap,
            p95SampleGapSec: coverage.p95Gap,
            coverageRatio: coverage.ratio,
            burstCount: coverage.burstCount,
            motionAgreementRate: nil,
            formulaVersion: formulaVersion
        )
    }

    private static func coverageMetrics(
        samples: [LocationSample],
        startedAt: Date,
        activeDuration: TimeInterval
    ) -> CoverageMetrics {
        guard activeDuration > 0 else {
            return CoverageMetrics(maxGap: 0, p95Gap: 0, ratio: 0, burstCount: 0)
        }

        let activeEnd = startedAt.addingTimeInterval(activeDuration)
        let firstReceiptDate = samples.map(\.receivedAt).min()
        let timestamps = samples
            .map { sample -> Date in
                let gpsElapsed = sample.timestamp.timeIntervalSince(startedAt)
                let receiptElapsed = firstReceiptDate.map {
                    sample.receivedAt.timeIntervalSince($0)
                } ?? gpsElapsed
                return startedAt.addingTimeInterval(max(gpsElapsed, receiptElapsed))
            }
            .filter { $0 >= startedAt && $0 <= activeEnd }
            .sorted()
        guard !timestamps.isEmpty else {
            return CoverageMetrics(
                maxGap: activeDuration,
                p95Gap: activeDuration,
                ratio: 0,
                burstCount: 0
            )
        }

        let timeline = ([startedAt] + timestamps + [activeEnd])
            .sorted()
            .reduce(into: [Date]()) { result, timestamp in
                if result.last != timestamp {
                    result.append(timestamp)
                }
            }
        let gaps = zip(timeline, timeline.dropFirst())
            .map { max(0, $1.timeIntervalSince($0)) }
        guard activeDuration > 0, !gaps.isEmpty else {
            return CoverageMetrics(maxGap: 0, p95Gap: 0, ratio: 0, burstCount: 1)
        }

        let coveredDuration = gaps.reduce(0) { partialResult, gap in
            partialResult + min(gap, Constants.maximumContinuousSampleGap)
        }
        return CoverageMetrics(
            maxGap: gaps.max() ?? 0,
            p95Gap: percentile(gaps, percentile: 0.95) ?? 0,
            ratio: max(0, min(1, coveredDuration / activeDuration)),
            burstCount: 1 + gaps.filter { $0 > Constants.maximumContinuousSampleGap }.count
        )
    }

    private static func activityWindow(
        completedTrip: CompletedDetectedTrip,
        samples: [LocationSample],
        vehicleType: VehicleType
    ) -> ActivityWindow {
        let completedDuration = max(0, completedTrip.duration)
        let boundedSamples = samples.filter { sample in
            sample.timestamp >= completedTrip.startedAt &&
                sample.timestamp <= completedTrip.endedAt
        }

        guard let firstSample = boundedSamples.first else {
            return ActivityWindow(activeDuration: 0, stationaryTail: completedDuration)
        }

        var lastMovingSample: LocationSample? = TripReliabilityRules.hasReliableMovementSpeed(firstSample)
            ? firstSample
            : nil
        var anchor = firstSample

        for current in boundedSamples.dropFirst() {
            guard let distance = TripMetricsCalculator.segmentDistanceMeters(
                previous: anchor,
                current: current,
                vehicleType: vehicleType
            ) else {
                continue
            }

            // Meme double chronologie que segmentDistanceMeters : une rafale
            // relivree compresse les timestamps GPS, la reception fait foi.
            let elapsed = max(
                current.timestamp.timeIntervalSince(anchor.timestamp),
                current.receivedAt.timeIntervalSince(anchor.receivedAt)
            )
            let impliedSpeedKmh = elapsed > 0 ? distance / elapsed * 3.6 : 0
            let hasMovementEvidence =
                TripReliabilityRules.hasReliableMovementSpeed(current) ||
                (distance > 0 && impliedSpeedKmh > TripReliabilityRules.stationarySpeedThresholdKmh)

            if hasMovementEvidence {
                lastMovingSample = current
            }
            if distance > 0 || TripReliabilityRules.hasReliableMovementSpeed(current) {
                anchor = current
            }
        }

        guard let lastMovingSample else {
            return ActivityWindow(activeDuration: 0, stationaryTail: completedDuration)
        }

        // Duree active sur la chronologie la plus plausible : timestamps GPS
        // depuis le debut du trajet, ou etalement de reception depuis le
        // premier point si iOS a compresse les timestamps de la rafale.
        let gpsActiveDuration = lastMovingSample.timestamp.timeIntervalSince(completedTrip.startedAt)
        let receiptActiveDuration = lastMovingSample.receivedAt.timeIntervalSince(firstSample.receivedAt)
        let activeDuration = max(0, min(completedDuration, max(gpsActiveDuration, receiptActiveDuration)))
        return ActivityWindow(
            activeDuration: activeDuration,
            stationaryTail: max(0, completedDuration - activeDuration)
        )
    }

    private static func countSegments(
        samples: [LocationSample],
        vehicleType: VehicleType
    ) -> (valid: Int, rejected: Int, total: Int) {
        // Meme parcours par ancre que TripMetricsCalculator.distanceAnalysis,
        // pour que le ratio de segments rejetes corresponde au calcul de distance.
        let analysis = TripMetricsCalculator.distanceAnalysis(
            samples: samples,
            vehicleType: vehicleType
        )
        return (analysis.validSegmentCount, analysis.rejectedSegmentCount, analysis.totalSegmentCount)
    }

    private static func reasonCode(from reasonCode: MetricReasonCode) -> TripQualityReasonCode {
        switch reasonCode {
        case .complete, .partialSpeedOnly, .fuelEstimated, .fuelInputMissing, .scoreUnavailable, .syncEngineMissing:
            return .complete
        case .gpsInsufficient:
            return .gpsInsufficient
        case .gpsAccuracyTooLow:
            return .gpsAccuracyTooLow
        case .impossibleSpeed:
            return .impossibleSpeed
        case .tripTooShort:
            return .tripTooShort
        case .tripNeedsReview:
            return .legacyUnverified
        }
    }

    private static func normalizedReasons(_ reasons: [TripQualityReasonCode]) -> [TripQualityReasonCode] {
        let filteredReasons = reasons.filter { $0 != .complete }
        guard !filteredReasons.isEmpty else {
            return [.complete]
        }

        var seen = Set<String>()
        return filteredReasons.filter { reason in
            seen.insert(reason.rawValue).inserted
        }
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        let sortedValues = values.sorted()
        let index = Int((Double(sortedValues.count - 1) * percentile).rounded(.up))
        return sortedValues[min(sortedValues.count - 1, max(0, index))]
    }
}

enum TripQualityDecisionSource: String, Equatable {
    case liveAccepted
    case liveRejected
    case historicalRecalculation
}

enum TripQualityLearningSignal: String, Equatable {
    case insufficientData
    case stable
    case gpsDegraded
    case segmentationNoisy
    case legacyDataNeedsReview
}

struct TripQualityTelemetryRecord: Identifiable, Equatable {
    let id: UUID
    let tripId: UUID?
    let createdAt: Date
    let decisionSource: TripQualityDecisionSource
    let vehicleType: VehicleType
    let qualityScore: Int
    let qualityConfidence: TripQualityConfidence
    let qualityReasonCodes: [TripQualityReasonCode]
    let acceptedForStorage: Bool
    let includedInSummaryAtDecision: Bool
    let sampleCount: Int
    let gpsAccuracyAvg: Double
    let gpsAccuracyP95: Double
    let rejectedSegmentCount: Int
    let validSegmentCount: Int
    let maxSampleGapSec: Double
    let p95SampleGapSec: Double
    let coverageRatio: Double
    let burstCount: Int
    let formulaVersion: String
    let synced: Bool
}

struct TripQualityLearningProfile: Equatable {
    let sampleSize: Int
    let acceptedCount: Int
    let rejectedCount: Int
    let needsReviewCount: Int
    let rejectedRate: Double
    let needsReviewRate: Double
    let topReasonCodes: [TripQualityReasonCode]
    let minimumSummaryQualityScore: Int
    let signal: TripQualityLearningSignal

    var isProtectiveModeEnabled: Bool {
        minimumSummaryQualityScore > TripQualityLearningEngine.baselineMinimumSummaryQualityScore
    }

    static let insufficientData = TripQualityLearningProfile(
        sampleSize: 0,
        acceptedCount: 0,
        rejectedCount: 0,
        needsReviewCount: 0,
        rejectedRate: 0,
        needsReviewRate: 0,
        topReasonCodes: [],
        minimumSummaryQualityScore: TripQualityLearningEngine.baselineMinimumSummaryQualityScore,
        signal: .insufficientData
    )
}

enum TripQualityLearningEngine {
    static let baselineMinimumSummaryQualityScore = 65
    private static let protectiveMinimumSummaryQualityScore = 85
    private static let minimumSamplesForLearning = 5

    static func profile(from telemetryRecords: [TripQualityTelemetryRecord]) -> TripQualityLearningProfile {
        guard telemetryRecords.count >= minimumSamplesForLearning else {
            return TripQualityLearningProfile(
                sampleSize: telemetryRecords.count,
                acceptedCount: telemetryRecords.filter(\.acceptedForStorage).count,
                rejectedCount: telemetryRecords.filter { $0.qualityConfidence == .rejected }.count,
                needsReviewCount: telemetryRecords.filter { $0.qualityConfidence == .needsReview }.count,
                rejectedRate: 0,
                needsReviewRate: 0,
                topReasonCodes: topReasonCodes(from: telemetryRecords),
                minimumSummaryQualityScore: baselineMinimumSummaryQualityScore,
                signal: .insufficientData
            )
        }

        let sampleSize = telemetryRecords.count
        let acceptedCount = telemetryRecords.filter(\.acceptedForStorage).count
        let rejectedCount = telemetryRecords.filter { $0.qualityConfidence == .rejected }.count
        let needsReviewCount = telemetryRecords.filter { $0.qualityConfidence == .needsReview }.count
        let rejectedRate = Double(rejectedCount) / Double(sampleSize)
        let needsReviewRate = Double(needsReviewCount) / Double(sampleSize)
        let topReasons = topReasonCodes(from: telemetryRecords)

        let gpsIssueCount = reasonCount(.gpsAccuracyTooLow, in: telemetryRecords) +
            reasonCount(.gpsInsufficient, in: telemetryRecords) +
            reasonCount(.gpsCoverageIncomplete, in: telemetryRecords)
        let segmentationIssueCount = reasonCount(.impossibleSpeed, in: telemetryRecords) +
            reasonCount(.tooManyRejectedSegments, in: telemetryRecords)
        let legacyIssueCount = reasonCount(.legacyUnverified, in: telemetryRecords)

        let signal: TripQualityLearningSignal
        let minimumSummaryQualityScore: Int
        if gpsIssueCount >= 3 && rejectedRate >= 0.3 {
            signal = .gpsDegraded
            minimumSummaryQualityScore = protectiveMinimumSummaryQualityScore
        } else if segmentationIssueCount >= 3 && rejectedRate >= 0.2 {
            signal = .segmentationNoisy
            minimumSummaryQualityScore = protectiveMinimumSummaryQualityScore
        } else if legacyIssueCount >= 3 && needsReviewRate >= 0.3 {
            signal = .legacyDataNeedsReview
            minimumSummaryQualityScore = protectiveMinimumSummaryQualityScore
        } else {
            signal = .stable
            minimumSummaryQualityScore = baselineMinimumSummaryQualityScore
        }

        return TripQualityLearningProfile(
            sampleSize: sampleSize,
            acceptedCount: acceptedCount,
            rejectedCount: rejectedCount,
            needsReviewCount: needsReviewCount,
            rejectedRate: rejectedRate,
            needsReviewRate: needsReviewRate,
            topReasonCodes: topReasons,
            minimumSummaryQualityScore: minimumSummaryQualityScore,
            signal: signal
        )
    }

    private static func topReasonCodes(
        from telemetryRecords: [TripQualityTelemetryRecord],
        limit: Int = 3
    ) -> [TripQualityReasonCode] {
        let counts = telemetryRecords
            .flatMap(\.qualityReasonCodes)
            .filter { $0 != .complete }
            .reduce(into: [TripQualityReasonCode: Int]()) { partialResult, reasonCode in
                partialResult[reasonCode, default: 0] += 1
            }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.rawValue < rhs.key.rawValue
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map(\.key)
    }

    private static func reasonCount(
        _ reasonCode: TripQualityReasonCode,
        in telemetryRecords: [TripQualityTelemetryRecord]
    ) -> Int {
        telemetryRecords.reduce(0) { partialResult, record in
            partialResult + record.qualityReasonCodes.filter { $0 == reasonCode }.count
        }
    }
}
