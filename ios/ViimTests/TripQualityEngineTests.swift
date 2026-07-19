import CoreLocation
import XCTest
@testable import Viim

final class TripQualityEngineTests: XCTestCase {
    func testReliableTripProducesAuditableQualityMetadata() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let report = TripQualityEngine.report(
            completedTrip: completedTrip(start: start),
            samples: samples(start: start),
            vehicleType: .moto
        )

        XCTAssertEqual(report.score, 100)
        XCTAssertEqual(report.confidence, .reliable)
        XCTAssertEqual(report.reasonCodes, [.complete])
        XCTAssertEqual(report.activeDurationSec, 600)
        XCTAssertEqual(report.gpsAccuracyAvg, 5)
        XCTAssertEqual(report.gpsAccuracyP95, 5)
        XCTAssertEqual(report.validSegmentCount, 4)
        XCTAssertEqual(report.rejectedSegmentCount, 0)
        XCTAssertEqual(report.maxSampleGapSec, 150)
        XCTAssertEqual(report.coverageRatio, 1)
        XCTAssertTrue(report.shouldPersist)
    }

    func testPrecisePointsWithLongCollectionGapsCannotScoreOneHundred() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        // Reproduit la topologie du trajet terrain : points precis, mais deux
        // suspensions de presque cinq minutes au milieu de la route.
        let offsets: [TimeInterval] = [0, 20, 40, 60, 351, 371, 391, 411, 701, 721, 741, 761, 910]
        let route = offsets.enumerated().map { index, offset in
            sample(
                latitude: 46.8915 + Double(index) * 0.00035,
                longitude: -71.2137,
                speed: 12,
                accuracy: 5,
                timestamp: start.addingTimeInterval(offset)
            )
        }
        let report = TripQualityEngine.report(
            completedTrip: CompletedDetectedTrip(
                id: UUID(),
                startedAt: start,
                endedAt: start.addingTimeInterval(910),
                distanceMeters: 470,
                sampleCount: route.count
            ),
            samples: route,
            vehicleType: .voiture
        )

        XCTAssertEqual(report.confidence, .partial)
        XCTAssertEqual(report.score, 65)
        XCTAssertTrue(report.reasonCodes.contains(.gpsCoverageIncomplete))
        XCTAssertEqual(report.maxSampleGapSec, 291)
        XCTAssertEqual(report.burstCount, 3)
        XCTAssertLessThan(report.coverageRatio, 0.80)
        XCTAssertTrue(report.shouldPersist)
    }

    func testRejectsTripWithTooFewGpsPoints() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let report = TripQualityEngine.report(
            completedTrip: completedTrip(start: start),
            samples: Array(samples(start: start).prefix(3)),
            vehicleType: .moto
        )

        XCTAssertEqual(report.confidence, .rejected)
        XCTAssertTrue(report.reasonCodes.contains(.gpsInsufficient))
        XCTAssertFalse(report.shouldPersist)
    }

    func testRejectsTripWithPoorGpsAccuracy() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let report = TripQualityEngine.report(
            completedTrip: completedTrip(start: start),
            samples: samples(start: start, accuracy: 150),
            vehicleType: .moto
        )

        XCTAssertEqual(report.confidence, .rejected)
        XCTAssertTrue(report.reasonCodes.contains(.gpsAccuracyTooLow))
        XCTAssertTrue(report.reasonCodes.contains(.gpsInsufficient))
        XCTAssertFalse(report.shouldPersist)
    }

    func testRejectsImpossibleGpsJumpAndCountsRejectedSegments() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let report = TripQualityEngine.report(
            completedTrip: completedTrip(start: start),
            samples: impossibleJumpSamples(start: start),
            vehicleType: .moto
        )

        XCTAssertEqual(report.confidence, .rejected)
        XCTAssertTrue(report.reasonCodes.contains(.impossibleSpeed))
        XCTAssertTrue(report.reasonCodes.contains(.tooManyRejectedSegments))
        XCTAssertGreaterThan(report.rejectedSegmentCount, 0)
        XCTAssertFalse(report.shouldPersist)
    }

    func testLongTripWithFewRejectedSegmentsRemainsPersistable() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let samples = longRouteWithTwoRejectedSegments(start: start)
        let report = TripQualityEngine.report(
            completedTrip: CompletedDetectedTrip(
                id: UUID(),
                startedAt: start,
                endedAt: start.addingTimeInterval(3_600),
                distanceMeters: 1_200,
                sampleCount: samples.count
            ),
            samples: samples,
            vehicleType: .moto
        )

        // Scan par ancre : le point aberrant unique ne coute qu'un segment rejete.
        XCTAssertEqual(report.rejectedSegmentCount, 1)
        XCTAssertFalse(report.reasonCodes.contains(.tooManyRejectedSegments))
        XCTAssertTrue(report.shouldPersist)
    }

    func testStationaryTailIsExcludedFromActiveDrivingDuration() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let movingSamples = samples(start: start)
        guard let finalMovingSample = movingSamples.last else {
            return XCTFail("La fixture doit contenir un point de conduite")
        }
        let routeSamples = movingSamples + [
            sample(
                latitude: finalMovingSample.latitude,
                longitude: finalMovingSample.longitude,
                speed: 0,
                accuracy: 5,
                timestamp: start.addingTimeInterval(3 * 3_600)
            )
        ]
        let report = TripQualityEngine.report(
            completedTrip: CompletedDetectedTrip(
                id: UUID(),
                startedAt: start,
                endedAt: start.addingTimeInterval(3 * 3_600),
                distanceMeters: 1_200,
                sampleCount: routeSamples.count
            ),
            samples: routeSamples,
            vehicleType: .moto
        )

        XCTAssertEqual(report.activeDurationSec, 600)
        XCTAssertEqual(report.stationaryTailSec, 10_200)
        XCTAssertEqual(report.confidence, .reliable)
        XCTAssertTrue(report.shouldPersist)
    }

    func testRejectedSegmentRatioAboveThresholdRejectsTrip() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        // Deux points aberrants distincts sur six : le scan par ancre compte
        // deux segments rejetes sur cinq (40 %), au-dessus du seuil de 20 %.
        let samples = [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 10, accuracy: 5, timestamp: start),
            sample(latitude: 12.3724, longitude: -1.5187, speed: 10, accuracy: 5, timestamp: start.addingTimeInterval(120)),
            sample(latitude: 13.3724, longitude: -1.5187, speed: 10, accuracy: 5, timestamp: start.addingTimeInterval(130)),
            sample(latitude: 12.3734, longitude: -1.5177, speed: 10, accuracy: 5, timestamp: start.addingTimeInterval(240)),
            sample(latitude: 13.3744, longitude: -1.5167, speed: 10, accuracy: 5, timestamp: start.addingTimeInterval(250)),
            sample(latitude: 12.3744, longitude: -1.5157, speed: 10, accuracy: 5, timestamp: start.addingTimeInterval(360))
        ]
        let report = TripQualityEngine.report(
            completedTrip: completedTrip(start: start),
            samples: samples,
            vehicleType: .moto
        )

        XCTAssertEqual(report.rejectedSegmentCount, 2)
        XCTAssertTrue(report.reasonCodes.contains(.tooManyRejectedSegments))
        XCTAssertFalse(report.shouldPersist)
    }

    private func completedTrip(start: Date) -> CompletedDetectedTrip {
        CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 1_200,
            sampleCount: 5
        )
    }

    private func samples(start: Date, accuracy: CLLocationAccuracy = 5) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 0, accuracy: accuracy, timestamp: start),
            sample(latitude: 12.3734, longitude: -1.5177, speed: 5, accuracy: accuracy, timestamp: start.addingTimeInterval(150)),
            sample(latitude: 12.3754, longitude: -1.5157, speed: 6, accuracy: accuracy, timestamp: start.addingTimeInterval(300)),
            sample(latitude: 12.3774, longitude: -1.5137, speed: 5, accuracy: accuracy, timestamp: start.addingTimeInterval(450)),
            sample(latitude: 12.3794, longitude: -1.5117, speed: 4, accuracy: accuracy, timestamp: start.addingTimeInterval(600))
        ]
    }

    private func impossibleJumpSamples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 10, accuracy: 5, timestamp: start),
            sample(latitude: 12.4714, longitude: -1.5197, speed: 10, accuracy: 5, timestamp: start.addingTimeInterval(10)),
            sample(latitude: 12.4724, longitude: -1.5187, speed: 10, accuracy: 5, timestamp: start.addingTimeInterval(20)),
            sample(latitude: 12.4734, longitude: -1.5177, speed: 10, accuracy: 5, timestamp: start.addingTimeInterval(30)),
            sample(latitude: 12.4744, longitude: -1.5167, speed: 10, accuracy: 5, timestamp: start.addingTimeInterval(40))
        ]
    }

    private func longRouteWithTwoRejectedSegments(start: Date) -> [LocationSample] {
        var routeSamples: [LocationSample] = []

        for index in 0...25 {
            routeSamples.append(
                sample(
                    latitude: 12.3714 + Double(index) * 0.0001,
                    longitude: -1.5197 + Double(index) * 0.0001,
                    speed: 10,
                    accuracy: 5,
                    timestamp: start.addingTimeInterval(Double(index) * 60)
                )
            )
        }

        routeSamples.append(
            sample(
                latitude: 13.3714,
                longitude: -1.5197,
                speed: 10,
                accuracy: 5,
                timestamp: start.addingTimeInterval(26 * 60)
            )
        )

        for index in 26...50 {
            routeSamples.append(
                sample(
                    latitude: 12.3714 + Double(index) * 0.0001,
                    longitude: -1.5197 + Double(index) * 0.0001,
                    speed: 10,
                    accuracy: 5,
                    timestamp: start.addingTimeInterval(Double(index + 1) * 60)
                )
            )
        }

        return routeSamples
    }

    private func sample(
        latitude: Double,
        longitude: Double,
        speed: CLLocationSpeed,
        accuracy: CLLocationAccuracy,
        timestamp: Date
    ) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            speedKmh: speed * 3.6,
            horizontalAccuracy: accuracy,
            speedAccuracy: 1
        )
    }
}
