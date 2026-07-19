import CoreLocation
import XCTest
@testable import Viim

final class DrivingDynamicsTests: XCTestCase {
    func testSmoothCruiseYieldsCalmDynamics() throws {
        // 10 minutes a 60 km/h constants, un point toutes les 2 s.
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let samples = (0...300).map { index in
            sample(speedKmh: 60, timestamp: start.addingTimeInterval(Double(index) * 2))
        }

        let dynamics = try XCTUnwrap(
            DrivingDynamicsAnalyzer.dynamics(samples: samples, vehicleType: .voiture, distanceKm: 10)
        )

        XCTAssertEqual(dynamics.meanMovingSpeedKmh, 60, accuracy: 0.5)
        XCTAssertEqual(dynamics.idleRatio, 0, accuracy: 0.001)
        XCTAssertEqual(dynamics.hardAccelerationCount, 0)
        XCTAssertEqual(dynamics.hardBrakingCount, 0)
        XCTAssertEqual(dynamics.accelerationRms, 0, accuracy: 0.001)
        XCTAssertLessThan(dynamics.fuelConsumptionMultiplier, 1.0)
    }

    func testStopAndGoDetectsHardEventsAndIdle() throws {
        // Cycle urbain : arrets prolonges + demarrages et freinages brutaux.
        // 0→50 km/h en 4 s ≈ 3.5 m/s2 (> 2.5) puis 50→0 en 4 s ≈ -3.5 m/s2.
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        var samples: [LocationSample] = []
        var time = 0.0
        for _ in 0..<8 {
            for second in 0...10 {
                samples.append(sample(speedKmh: 0, timestamp: start.addingTimeInterval(time + Double(second))))
            }
            time += 10
            samples.append(sample(speedKmh: 50, timestamp: start.addingTimeInterval(time + 4)))
            time += 4
            samples.append(sample(speedKmh: 0, timestamp: start.addingTimeInterval(time + 4)))
            time += 4
        }

        let dynamics = try XCTUnwrap(
            DrivingDynamicsAnalyzer.dynamics(samples: samples, vehicleType: .voiture, distanceKm: 2)
        )

        XCTAssertGreaterThanOrEqual(dynamics.hardAccelerationCount, 5)
        XCTAssertGreaterThanOrEqual(dynamics.hardBrakingCount, 5)
        XCTAssertGreaterThan(dynamics.idleRatio, 0.3)
        XCTAssertGreaterThan(dynamics.fuelConsumptionMultiplier, 1.1)
    }

    func testInsufficientCoverageReturnsNil() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let samples = [
            sample(speedKmh: 40, timestamp: start),
            sample(speedKmh: 45, timestamp: start.addingTimeInterval(5))
        ]

        XCTAssertNil(
            DrivingDynamicsAnalyzer.dynamics(samples: samples, vehicleType: .voiture, distanceKm: 0.1)
        )
    }

    func testInaccurateSamplesAreIgnored() {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let samples = (0...100).map { index in
            LocationSample(
                timestamp: start.addingTimeInterval(Double(index) * 2),
                latitude: 12.3714,
                longitude: -1.5197,
                speedKmh: 60,
                horizontalAccuracy: 500,
                speedAccuracy: 1
            )
        }

        XCTAssertNil(
            DrivingDynamicsAnalyzer.dynamics(samples: samples, vehicleType: .voiture, distanceKm: 3)
        )
    }

    func testLegacyRoutePointsWithoutSpeedAccuracyStillProduceDynamics() throws {
        // Les anciens encodages de trace ne persistaient pas speedAccuracy
        // (-1 au decodage) : ces points ont deja passe le filtre qualite a
        // l'enregistrement et doivent alimenter le recalcul historique.
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let routePoints = (0...120).map { index in
            TripRoutePoint(
                timestamp: start.addingTimeInterval(Double(index) * 2),
                latitude: 12.3714,
                longitude: -1.5197,
                speedKmh: 50,
                horizontalAccuracy: 5,
                speedAccuracy: -1
            )
        }

        let dynamics = try XCTUnwrap(
            DrivingDynamicsAnalyzer.dynamics(routePoints: routePoints, vehicleType: .voiture, distanceKm: 3)
        )
        XCTAssertEqual(dynamics.meanMovingSpeedKmh, 50, accuracy: 0.5)

        // Le flux temps reel, lui, reste strict : sans precision de vitesse
        // rapportee, pas de dynamique.
        let liveSamples = (0...120).map { index in
            LocationSample(
                timestamp: start.addingTimeInterval(Double(index) * 2),
                latitude: 12.3714,
                longitude: -1.5197,
                speedKmh: 50,
                horizontalAccuracy: 5,
                speedAccuracy: -1
            )
        }
        XCTAssertNil(
            DrivingDynamicsAnalyzer.dynamics(samples: liveSamples, vehicleType: .voiture, distanceKm: 3)
        )
    }

    func testRoutePointsProduceSameShapeOfDynamics() throws {
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let routePoints = (0...120).map { index in
            TripRoutePoint(
                timestamp: start.addingTimeInterval(Double(index) * 2),
                latitude: 12.3714,
                longitude: -1.5197,
                speedKmh: 45,
                horizontalAccuracy: 5,
                speedAccuracy: 1
            )
        }

        let dynamics = try XCTUnwrap(
            DrivingDynamicsAnalyzer.dynamics(routePoints: routePoints, vehicleType: .voiture, distanceKm: 3)
        )
        XCTAssertEqual(dynamics.meanMovingSpeedKmh, 45, accuracy: 0.5)
    }

    func testScoreEngineActivatesFluidityAndEcoScores() {
        let calmDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 60,
            idleRatio: 0.05,
            hardAccelerationCount: 0,
            hardBrakingCount: 0,
            accelerationRms: 0.3,
            analyzedDurationSec: 600,
            distanceKm: 10
        )
        let harshDynamics = DrivingDynamics(
            meanMovingSpeedKmh: 20,
            idleRatio: 0.3,
            hardAccelerationCount: 8,
            hardBrakingCount: 7,
            accelerationRms: 1.6,
            analyzedDurationSec: 600,
            distanceKm: 10
        )

        let calmScores = ScoreEngine.scores(maxSpeedKmh: 80, vehicleType: .voiture, dynamics: calmDynamics)
        let harshScores = ScoreEngine.scores(maxSpeedKmh: 80, vehicleType: .voiture, dynamics: harshDynamics)

        XCTAssertEqual(calmScores.scoreFluidite, 100)
        XCTAssertEqual(calmScores.scoreEco, 100)
        XCTAssertLessThan(harshScores.scoreFluidite ?? 100, 100)
        XCTAssertLessThan(harshScores.scoreEco ?? 100, 100)
        XCTAssertNotNil(calmScores.score)
        // Sans dynamique mesurable, les scores fluidite et eco restent absents.
        let withoutDynamics = ScoreEngine.scores(maxSpeedKmh: 80, vehicleType: .voiture)
        XCTAssertNil(withoutDynamics.scoreFluidite)
        XCTAssertNil(withoutDynamics.scoreEco)
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
