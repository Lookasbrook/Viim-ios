import CoreLocation
import XCTest
@testable import Viim

final class ScoreEngineTests: XCTestCase {
    func testReceiptClockCannotInflateSparseGPSCoverage() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(id: UUID(), startedAt: start,
                                        endedAt: start.addingTimeInterval(100),
                                        distanceMeters: 1_200, sampleCount: 11)
        let samples = (0...10).map { index in
            LocationSample(timestamp: start.addingTimeInterval(Double(index)),
                           latitude: 45, longitude: -73, speedKmh: 50,
                           horizontalAccuracy: 5, speedAccuracy: 1,
                           receivedAt: start.addingTimeInterval(Double(index) * 10))
        }
        XCTAssertEqual(ScoreEngine.scores(for: trip, samples: samples, vehicleType: .voiture), .unavailable)
    }

    func testCoverageBoundaryAndInvalidSpeedsDoNotCreateFalseScore() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(id: UUID(), startedAt: start,
                                        endedAt: start.addingTimeInterval(100),
                                        distanceMeters: 1_200, sampleCount: 11)
        let continuous = (0...10).map { sample(speedKmh: 50, timestamp: start.addingTimeInterval(Double($0) * 10)) }
        XCTAssertNotNil(ScoreEngine.scores(for: trip, samples: Array(continuous.prefix(9)), vehicleType: .voiture).score)
        XCTAssertNil(ScoreEngine.scores(for: trip, samples: Array(continuous.prefix(8)), vehicleType: .voiture).score)
        for speed in [Double.nan, Double.infinity, -1] {
            let invalid = (0...10).map { sample(speedKmh: speed, timestamp: start.addingTimeInterval(Double($0) * 10)) }
            XCTAssertEqual(ScoreEngine.scores(for: trip, samples: invalid, vehicleType: .voiture), .unavailable)
        }
    }

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
            endedAt: start.addingTimeInterval(16),
            distanceMeters: 1_200,
            sampleCount: 4
        )

        let scores = ScoreEngine.scores(
            for: trip,
            samples: [
                sample(speedKmh: 60, timestamp: start),
                sample(speedKmh: 130, timestamp: start.addingTimeInterval(5)),
                sample(speedKmh: 80, timestamp: start.addingTimeInterval(6)),
                sample(speedKmh: 70, timestamp: start.addingTimeInterval(16))
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
            endedAt: start.addingTimeInterval(16),
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

    func testSparseHighSpeedSamplesWithLargeGapsYieldNoSpeedScore() {
        // Trois points sur 10 minutes, deux au-dessus du seuil : aucune paire
        // n'a d'intervalle exploitable. On ne sait pas ce qui s'est passe entre
        // les points, donc pas de score plutot qu'un 100 non fonde.
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

        XCTAssertNil(scores.scoreVitesse)
        XCTAssertNil(scores.score)
    }

    func testBriefLowSpeedBurstCannotGivePerfectScoreToTenMinuteTrip() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(600),
            distanceMeters: 4_000, sampleCount: 4
        )
        for offsets in [[0.0, 5, 300, 600], [0.0, 200, 400, 600]] {
            let samples = offsets.map { sample(speedKmh: 50, timestamp: start.addingTimeInterval($0)) }
            XCTAssertEqual(ScoreEngine.scores(for: trip, samples: samples, vehicleType: .voiture), .unavailable)
        }
    }

    func testPartialOverspeedProducesIntermediateSpeedScore() {
        // 100 s a 95 km/h (sous le seuil), puis 100 s a 118 km/h (13 km/h
        // au-dessus du seuil technique 105). Le score doit atterrir loin de
        // 100 sans s'effondrer a 0.
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(200),
            distanceMeters: 4_000,
            sampleCount: 41
        )

        var samples: [LocationSample] = []
        for step in 0...20 {
            samples.append(sample(speedKmh: 95, timestamp: start.addingTimeInterval(Double(step) * 5)))
        }
        for step in 1...20 {
            samples.append(sample(speedKmh: 118, timestamp: start.addingTimeInterval(100 + Double(step) * 5)))
        }

        let score = ScoreEngine.scores(for: trip, samples: samples, vehicleType: .voiture).scoreVitesse
        let unwrapped = try? XCTUnwrap(score)
        XCTAssertNotNil(unwrapped)
        XCTAssertLessThan(unwrapped ?? 100, 100)
        XCTAssertGreaterThan(unwrapped ?? 0, 30)
    }

    func testModerateAccelerationTextureLowersFluidityBelowPerfect() {
        let calm = DrivingDynamics(
            meanMovingSpeedKmh: 50,
            idleRatio: 0.05,
            hardAccelerationCount: 0,
            hardBrakingCount: 0,
            accelerationRms: 0.3,
            analyzedDurationSec: 600,
            distanceKm: 10
        )
        let textured = DrivingDynamics(
            meanMovingSpeedKmh: 50,
            idleRatio: 0.05,
            hardAccelerationCount: 0,
            hardBrakingCount: 0,
            accelerationRms: 1.1,
            analyzedDurationSec: 600,
            distanceKm: 10
        )

        let calmScore = ScoreEngine.scores(maxSpeedKmh: 80, vehicleType: .voiture, dynamics: calm).scoreFluidite
        let texturedScore = ScoreEngine.scores(maxSpeedKmh: 80, vehicleType: .voiture, dynamics: textured).scoreFluidite

        XCTAssertEqual(calmScore, 100)
        XCTAssertLessThan(texturedScore ?? 100, 100)
        XCTAssertGreaterThan(texturedScore ?? 0, 60)
    }

    func testEcoScoreTracksAverageSpeedContinuously() {
        func dynamics(meanSpeed: Double) -> DrivingDynamics {
            DrivingDynamics(
                meanMovingSpeedKmh: meanSpeed,
                idleRatio: 0,
                hardAccelerationCount: 0,
                hardBrakingCount: 0,
                accelerationRms: 0.3,
                analyzedDurationSec: 600,
                distanceKm: 12
            )
        }

        let slow = ScoreEngine.scores(maxSpeedKmh: 80, vehicleType: .voiture, dynamics: dynamics(meanSpeed: 30)).scoreEco
        let middling = ScoreEngine.scores(maxSpeedKmh: 80, vehicleType: .voiture, dynamics: dynamics(meanSpeed: 48)).scoreEco
        let cruise = ScoreEngine.scores(maxSpeedKmh: 80, vehicleType: .voiture, dynamics: dynamics(meanSpeed: 70)).scoreEco

        XCTAssertLessThan(slow ?? 100, middling ?? 100)
        XCTAssertLessThan(middling ?? 100, cruise ?? 100)
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
