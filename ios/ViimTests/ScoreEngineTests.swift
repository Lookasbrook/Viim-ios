import CoreLocation
import XCTest
@testable import Viim

final class ScoreEngineTests: XCTestCase {
    func testSpeedScorePenalizesVehicleOverspeed() {
        let safeScore = ScoreEngine.scores(maxSpeedKmh: 95, vehicleType: .voiture)
        let fastScore = ScoreEngine.scores(maxSpeedKmh: 130, vehicleType: .voiture)

        XCTAssertEqual(safeScore.scoreVitesse, 100)
        XCTAssertLessThan(try XCTUnwrap(fastScore.scoreVitesse), try XCTUnwrap(safeScore.scoreVitesse))
        XCTAssertEqual(fastScore.score, fastScore.scoreVitesse)
    }

    func testScoreIsUnavailableWhenSamplesAreMissing() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            distanceMeters: 120_000,
            sampleCount: 0
        )

        let scores = ScoreEngine.scores(for: trip, samples: [], vehicleType: .voiture)

        XCTAssertNil(scores.score)
        XCTAssertNil(scores.scoreVitesse)
    }

    func testBriefSpeedSpikeDoesNotPenalizeScore() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            distanceMeters: 1_200,
            sampleCount: 4
        )

        let scores = ScoreEngine.scores(
            for: trip,
            samples: [
                sample(speedKmh: 60, timestamp: start),
                sample(speedKmh: 130, timestamp: start.addingTimeInterval(5)),
                sample(speedKmh: 80, timestamp: start.addingTimeInterval(6)),
                sample(speedKmh: 70, timestamp: start.addingTimeInterval(120))
            ],
            vehicleType: .voiture
        )

        XCTAssertEqual(scores.scoreVitesse, 100)
        XCTAssertEqual(scores.score, 100)
    }

    func testSustainedOverspeedPenalizesScore() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            distanceMeters: 1_200,
            sampleCount: 4
        )

        let scores = ScoreEngine.scores(
            for: trip,
            samples: [
                sample(speedKmh: 60, timestamp: start),
                sample(speedKmh: 130, timestamp: start.addingTimeInterval(5)),
                sample(speedKmh: 132, timestamp: start.addingTimeInterval(12)),
                sample(speedKmh: 128, timestamp: start.addingTimeInterval(16))
            ],
            vehicleType: .voiture
        )

        XCTAssertLessThan(try XCTUnwrap(scores.scoreVitesse), 100)
        XCTAssertEqual(scores.score, scores.scoreVitesse)
    }

    func testLargeGpsGapDoesNotCreateFalseSustainedOverspeed() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 1_200,
            sampleCount: 3
        )

        let scores = ScoreEngine.scores(
            for: trip,
            samples: [
                sample(speedKmh: 130, timestamp: start),
                sample(speedKmh: 132, timestamp: start.addingTimeInterval(300)),
                sample(speedKmh: 80, timestamp: start.addingTimeInterval(600))
            ],
            vehicleType: .voiture
        )

        XCTAssertEqual(scores.scoreVitesse, 100)
    }

    private func sample(speedKmh: Double, timestamp: Date) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            latitude: 12.3714,
            longitude: -1.5197,
            speedKmh: speedKmh,
            horizontalAccuracy: 5,
            speedAccuracy: 1
        )
    }
}
