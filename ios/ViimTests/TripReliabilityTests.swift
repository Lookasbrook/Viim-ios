import CoreLocation
import XCTest
@testable import Viim

final class TripReliabilityTests: XCTestCase {
    func testPersistabilityRequiresDistanceDurationAndGpsSamples() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(30),
            distanceMeters: 120,
            sampleCount: 2
        )

        let metric = TripMetricsCalculator.persistabilityMetric(
            completedTrip: trip,
            samples: samples(start: start),
            vehicleType: .moto
        )

        XCTAssertNil(metric.value)
        XCTAssertEqual(metric.confidence, .unavailable)
        XCTAssertEqual(metric.reasonCode, .tripTooShort)
    }

    func testDistanceMetricRejectsImpossibleGpsJumpEvenWithGoodAccuracy() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let metric = TripMetricsCalculator.distanceMetric(
            samples: [
                sample(latitude: 12.3714, longitude: -1.5197, speed: 12, accuracy: 5, timestamp: start),
                sample(latitude: 12.4714, longitude: -1.5197, speed: 12, accuracy: 5, timestamp: start.addingTimeInterval(10))
            ],
            vehicleType: .moto
        )

        XCTAssertNil(metric.value)
        XCTAssertEqual(metric.confidence, .needsReview)
        XCTAssertEqual(metric.reasonCode, .impossibleSpeed)
    }

    func testDistanceMetricRejectsRecordedStationaryGpsDrift() {
        // Reproduction exacte du faux trajet de 108 m capture le 13 juillet.
        // Les deux premiers points annoncent 42 km/h, mais speedAccuracy == -1
        // signifie que cette vitesse n'est pas exploitable. Tous les points
        // restent dans la marge d'incertitude GPS autour du meme emplacement.
        let samples = [
            LocationSample(timestamp: Date(timeIntervalSinceReferenceDate: 805_609_546.4343005), latitude: 46.90651918767258, longitude: -71.21148568886476, speedKmh: 42.04800109863282, horizontalAccuracy: 13.344688234208022, speedAccuracy: -1),
            LocationSample(timestamp: Date(timeIntervalSinceReferenceDate: 805_609_547.4332902), latitude: 46.9064371710842, longitude: -71.2116222594481, speedKmh: 42.04800109863282, horizontalAccuracy: 13.18918996862836, speedAccuracy: -1),
            LocationSample(timestamp: Date(timeIntervalSinceReferenceDate: 805_609_548.9992746), latitude: 46.906243503476816, longitude: -71.21152500496223, speedKmh: 0.7200000107288361, horizontalAccuracy: 8.69995631201621, speedAccuracy: 1),
            LocationSample(timestamp: Date(timeIntervalSinceReferenceDate: 805_609_552.0004315), latitude: 46.90632235746273, longitude: -71.21162064109608, speedKmh: 0, horizontalAccuracy: 9.330636966759347, speedAccuracy: 0.07000000029802322),
            LocationSample(timestamp: Date(timeIntervalSinceReferenceDate: 805_609_556.0002191), latitude: 46.90644039522468, longitude: -71.21167330708708, speedKmh: 0, horizontalAccuracy: 16.891546370779338, speedAccuracy: 0.23000000417232513),
            LocationSample(timestamp: Date(timeIntervalSinceReferenceDate: 805_609_560.0000987), latitude: 46.90640786062278, longitude: -71.2116632333361, speedKmh: 0, horizontalAccuracy: 6.862816888139593, speedAccuracy: 0.3080157138848601),
            LocationSample(timestamp: Date(timeIntervalSinceReferenceDate: 805_609_647.9993397), latitude: 46.90661306719633, longitude: -71.21176159916901, speedKmh: 0.7579623522801562, horizontalAccuracy: 20.79176106441999, speedAccuracy: 0.7226544149975637),
            LocationSample(timestamp: Date(timeIntervalSinceReferenceDate: 805_609_648.9993318), latitude: 46.90646327838196, longitude: -71.21166197924641, speedKmh: 0.6045068363675067, horizontalAccuracy: 4.632568527562044, speedAccuracy: 0.7262882770159721)
        ]

        let analysis = TripMetricsCalculator.distanceAnalysis(
            samples: TripMetricsCalculator.validRouteSamples(from: samples),
            vehicleType: .moto
        )
        let metric = TripMetricsCalculator.distanceMetric(samples: samples, vehicleType: .moto)

        XCTAssertLessThan(analysis.distanceMeters, TripReliabilityRules.minimumPersistedTripDistanceMeters)
        XCTAssertNil(metric.value)
        XCTAssertEqual(metric.reasonCode, .tripTooShort)
    }

    func testDistanceMetricAccumulatesSlowMovementBeyondGpsUncertainty() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        // Environ 5,5 m par seconde avec une precision horizontale de 5 m.
        // Pris un par un, chaque segment est inferieur aux 10 m d'incertitude
        // combines. L'ancre doit toutefois conserver le deplacement cumule.
        let routeSamples = (0...20).map { index in
            LocationSample(
                timestamp: start.addingTimeInterval(Double(index)),
                latitude: 46.9064,
                longitude: -71.2117 + Double(index) * 0.000072,
                speedKmh: 20,
                horizontalAccuracy: 5,
                speedAccuracy: -1
            )
        }

        let metric = TripMetricsCalculator.distanceMetric(samples: routeSamples, vehicleType: .voiture)

        XCTAssertNotNil(metric.value)
        XCTAssertGreaterThan(metric.value ?? 0, TripReliabilityRules.minimumPersistedTripDistanceMeters)
        XCTAssertLessThan(metric.value ?? .greatestFiniteMagnitude, 130)
    }

    func testDistanceMetricSkipsIsolatedImpossibleSegmentsInsteadOfDroppingTrip() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let routeSamples = [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 12, accuracy: 5, timestamp: start),
            sample(latitude: 12.3724, longitude: -1.5187, speed: 12, accuracy: 5, timestamp: start.addingTimeInterval(120)),
            sample(latitude: 12.4724, longitude: -1.5187, speed: 12, accuracy: 5, timestamp: start.addingTimeInterval(130)),
            sample(latitude: 12.3734, longitude: -1.5177, speed: 12, accuracy: 5, timestamp: start.addingTimeInterval(240)),
            sample(latitude: 12.3744, longitude: -1.5167, speed: 12, accuracy: 5, timestamp: start.addingTimeInterval(360))
        ]

        let metric = TripMetricsCalculator.distanceMetric(samples: routeSamples, vehicleType: .moto)
        let analysis = TripMetricsCalculator.distanceAnalysis(
            samples: TripMetricsCalculator.validRouteSamples(from: routeSamples),
            vehicleType: .moto
        )

        XCTAssertNotNil(metric.value)
        XCTAssertEqual(metric.confidence, .reliable)
        // Parcours par ancre : le point aberrant ne coute qu'un seul segment
        // rejete et la distance entre les points qui l'encadrent est conservee.
        XCTAssertEqual(analysis.validSegmentCount, 3)
        XCTAssertEqual(analysis.rejectedSegmentCount, 1)
        XCTAssertGreaterThan(metric.value ?? 0, TripReliabilityRules.minimumPersistedTripDistanceMeters)
    }

    func testRouteMetricRequiresTwoValidGpsPoints() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let point = TripRoutePoint(
            timestamp: start,
            latitude: 12.3714,
            longitude: -1.5197,
            speedKmh: 12,
            horizontalAccuracy: 5
        )

        let metric = TripMetricsCalculator.routeMetric(points: [point])

        XCTAssertNil(metric.value)
        XCTAssertEqual(metric.reasonCode, .gpsInsufficient)
    }

    func testMaxSpeedRejectsPoorAccuracy() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let metric = TripMetricsCalculator.maxSpeedMetric(
            samples: [
                sample(latitude: 12.3714, longitude: -1.5197, speed: 20, accuracy: 80, timestamp: start),
                sample(latitude: 12.3724, longitude: -1.5187, speed: 24, accuracy: 90, timestamp: start.addingTimeInterval(30))
            ],
            vehicleType: .moto
        )

        XCTAssertNil(metric.value)
        XCTAssertEqual(metric.confidence, .unavailable)
        XCTAssertEqual(metric.reasonCode, .gpsAccuracyTooLow)
    }

    func testMaxSpeedRejectsPoorReportedSpeedAccuracy() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let metric = TripMetricsCalculator.maxSpeedMetric(
            samples: [
                sample(latitude: 12.3714, longitude: -1.5197, speed: 20, accuracy: 5, speedAccuracy: 7, timestamp: start),
                sample(latitude: 12.3724, longitude: -1.5187, speed: 24, accuracy: 5, speedAccuracy: 8, timestamp: start.addingTimeInterval(30))
            ],
            vehicleType: .moto
        )

        XCTAssertNil(metric.value)
        XCTAssertEqual(metric.confidence, .unavailable)
        XCTAssertEqual(metric.reasonCode, .gpsAccuracyTooLow)
    }

    func testMaxSpeedRejectsImpossibleVehicleSpeed() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let metric = TripMetricsCalculator.maxSpeedMetric(
            samples: [
                sample(latitude: 12.3714, longitude: -1.5197, speed: 30, accuracy: 5, timestamp: start),
                sample(latitude: 12.3724, longitude: -1.5187, speed: 250, accuracy: 5, timestamp: start.addingTimeInterval(30))
            ],
            vehicleType: .moto
        )

        XCTAssertNil(metric.value)
        XCTAssertEqual(metric.confidence, .needsReview)
        XCTAssertEqual(metric.reasonCode, .impossibleSpeed)
    }

    func testScoreWithOnlySpeedSubscoreIsPartial() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = TripRecord(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(600),
            distanceKm: 1.2,
            durationSec: 600,
            avgSpeedKmh: 7.2,
            maxSpeedKmh: 40,
            score: 100,
            scoreVitesse: 100,
            scoreFluidite: nil,
            scoreVigilance: nil,
            scoreEco: nil,
            fuelLiters: nil,
            fuelFCFA: nil,
            routePoints: [
                routePoint(timestamp: start, speedKmh: 12),
                routePoint(timestamp: start.addingTimeInterval(30), speedKmh: 18)
            ],
            qualityScore: 100,
            qualityConfidence: .reliable,
            qualityReasonCodes: [.complete],
            activeDurationSec: 600,
            stationaryTailSec: 0,
            gpsAccuracyAvg: 5,
            gpsAccuracyP95: 5,
            rejectedSegmentCount: 0,
            validSegmentCount: 1,
            maxSampleGapSec: 30,
            p95SampleGapSec: 30,
            coverageRatio: 1,
            burstCount: 1,
            motionAgreementRate: nil,
            qualityFormulaVersion: TripQualityEngine.formulaVersion,
            isCalibration: false,
            vehicleType: .moto,
            synced: false
        )

        let metric = TripMetricsCalculator.scoreMetric(for: trip)

        XCTAssertEqual(metric.value, 100)
        XCTAssertEqual(metric.confidence, .partial)
        XCTAssertEqual(metric.reasonCode, .partialSpeedOnly)
    }

    private func samples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 10, accuracy: 5, timestamp: start),
            sample(latitude: 12.3724, longitude: -1.5187, speed: 12, accuracy: 5, timestamp: start.addingTimeInterval(30))
        ]
    }

    private func sample(
        latitude: Double,
        longitude: Double,
        speed: CLLocationSpeed,
        accuracy: CLLocationAccuracy,
        speedAccuracy: CLLocationSpeedAccuracy = 1,
        timestamp: Date
    ) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            speedKmh: speed * 3.6,
            horizontalAccuracy: accuracy,
            speedAccuracy: speedAccuracy
        )
    }

    private func routePoint(timestamp: Date, speedKmh: Double) -> TripRoutePoint {
        TripRoutePoint(
            timestamp: timestamp,
            latitude: 12.3714,
            longitude: -1.5197,
            speedKmh: speedKmh,
            horizontalAccuracy: 5
        )
    }
}
