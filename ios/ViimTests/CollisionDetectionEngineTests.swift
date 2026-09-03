import XCTest
@testable import Viim

final class CollisionDetectionEngineTests: XCTestCase {
    func testShadowMonitorRunsOnlyForActiveMotorizedTripsWithHardware() {
        XCTAssertTrue(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: true,
                vehicleType: .voiture,
                deviceMotionAvailable: true
            )
        )
        XCTAssertTrue(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: true,
                vehicleType: .moto,
                deviceMotionAvailable: true
            )
        )
        XCTAssertFalse(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: true,
                vehicleType: .velo,
                deviceMotionAvailable: true
            )
        )
        XCTAssertFalse(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: false,
                vehicleType: .voiture,
                deviceMotionAvailable: true
            )
        )
        XCTAssertFalse(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: true,
                vehicleType: .voiture,
                deviceMotionAvailable: false
            )
        )
    }

    func testImpactAtRestDoesNotArmCollisionCandidate() {
        var engine = CollisionDetectionEngine()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        let candidate = engine.ingest(
            frame(
                at: now,
                accelerationG: 5,
                speedKmh: 0,
                speedTimestamp: now
            )
        )

        XCTAssertNil(candidate)
        XCTAssertFalse(engine.hasPendingImpact)
    }

    func testMovingImpactWithoutReliableSpeedLossExpires() {
        var engine = CollisionDetectionEngine()
        let impactAt = Date(timeIntervalSinceReferenceDate: 2_000)

        XCTAssertNil(
            engine.ingest(
                frame(
                    at: impactAt,
                    accelerationG: 4.5,
                    speedKmh: 52,
                    speedTimestamp: impactAt
                )
            )
        )
        XCTAssertTrue(engine.hasPendingImpact)

        XCTAssertNil(
            engine.ingest(
                frame(
                    at: impactAt.addingTimeInterval(6),
                    accelerationG: 0.1,
                    speedKmh: 48,
                    speedTimestamp: impactAt.addingTimeInterval(6)
                )
            )
        )
        XCTAssertFalse(engine.hasPendingImpact)
    }

    func testImpactAndReliableSpeedLossCreatesShadowCandidate() throws {
        var engine = CollisionDetectionEngine()
        let impactAt = Date(timeIntervalSinceReferenceDate: 3_000)

        XCTAssertNil(
            engine.ingest(
                frame(
                    at: impactAt,
                    accelerationG: 4.2,
                    rotationRate: 2.4,
                    speedKmh: 54,
                    speedAccuracyKmh: 3,
                    speedTimestamp: impactAt
                )
            )
        )

        let candidate = try XCTUnwrap(
            engine.ingest(
                frame(
                    at: impactAt.addingTimeInterval(2),
                    accelerationG: 0.3,
                    rotationRate: 0.2,
                    speedKmh: 8,
                    speedAccuracyKmh: 4,
                    speedTimestamp: impactAt.addingTimeInterval(2)
                )
            )
        )

        XCTAssertEqual(candidate.algorithmVersion, CollisionDetectionEngine.algorithmVersion)
        XCTAssertEqual(candidate.impactAt, impactAt)
        XCTAssertEqual(candidate.confirmedAt, impactAt.addingTimeInterval(2))
        XCTAssertEqual(candidate.peakUserAccelerationG, 4.2, accuracy: 0.000_001)
        XCTAssertEqual(candidate.peakRotationRate, 2.4, accuracy: 0.000_001)
        XCTAssertEqual(candidate.preImpactSpeedKmh, 54, accuracy: 0.000_001)
        XCTAssertEqual(candidate.postImpactSpeedKmh, 8, accuracy: 0.000_001)
        XCTAssertEqual(candidate.speedLossKmh, 46, accuracy: 0.000_001)
        XCTAssertFalse(engine.hasPendingImpact)
    }

    func testStaleOrInaccurateGPSSpeedCannotArmCandidate() {
        let now = Date(timeIntervalSinceReferenceDate: 4_000)
        var staleEngine = CollisionDetectionEngine()
        var inaccurateEngine = CollisionDetectionEngine()

        XCTAssertNil(
            staleEngine.ingest(
                frame(
                    at: now,
                    accelerationG: 5,
                    speedKmh: 60,
                    speedAccuracyKmh: 2,
                    speedTimestamp: now.addingTimeInterval(-4)
                )
            )
        )
        XCTAssertFalse(staleEngine.hasPendingImpact)

        XCTAssertNil(
            inaccurateEngine.ingest(
                frame(
                    at: now,
                    accelerationG: 5,
                    speedKmh: 60,
                    speedAccuracyKmh: 12,
                    speedTimestamp: now
                )
            )
        )
        XCTAssertFalse(inaccurateEngine.hasPendingImpact)
    }

    func testCooldownSuppressesDuplicateCandidates() throws {
        var engine = CollisionDetectionEngine()
        let firstImpact = Date(timeIntervalSinceReferenceDate: 5_000)

        _ = engine.ingest(
            frame(
                at: firstImpact,
                accelerationG: 4,
                speedKmh: 50,
                speedTimestamp: firstImpact
            )
        )
        _ = try XCTUnwrap(
            engine.ingest(
                frame(
                    at: firstImpact.addingTimeInterval(1),
                    accelerationG: 0.2,
                    speedKmh: 5,
                    speedTimestamp: firstImpact.addingTimeInterval(1)
                )
            )
        )

        let secondImpact = firstImpact.addingTimeInterval(10)
        XCTAssertNil(
            engine.ingest(
                frame(
                    at: secondImpact,
                    accelerationG: 5,
                    speedKmh: 55,
                    speedTimestamp: secondImpact
                )
            )
        )
        XCTAssertFalse(engine.hasPendingImpact)
    }

    func testShadowJournalIsBoundedAndDoesNotPersistCoordinates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-shadow.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = CollisionShadowJournal(fileURL: fileURL, retentionLimit: 2)

        for offset in 0..<3 {
            let date = Date(timeIntervalSinceReferenceDate: Double(offset))
            try journal.append(
                CollisionShadowCandidate(
                    id: UUID(),
                    algorithmVersion: CollisionDetectionEngine.algorithmVersion,
                    impactAt: date,
                    confirmedAt: date,
                    peakUserAccelerationG: 4,
                    peakRotationRate: 1,
                    preImpactSpeedKmh: 50,
                    postImpactSpeedKmh: 5,
                    speedLossKmh: 45
                )
            )
        }

        let events = try journal.load()
        let data = try Data(contentsOf: fileURL)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.impactAt, Date(timeIntervalSinceReferenceDate: 1))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("latitude"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("longitude"))
    }

    private func frame(
        at timestamp: Date,
        accelerationG: Double,
        rotationRate: Double = 0,
        speedKmh: Double?,
        speedAccuracyKmh: Double = 3,
        speedTimestamp: Date?
    ) -> CollisionSensorFrame {
        CollisionSensorFrame(
            timestamp: timestamp,
            userAccelerationMagnitudeG: accelerationG,
            rotationRateMagnitude: rotationRate,
            gpsSpeedKmh: speedKmh,
            gpsSpeedAccuracyKmh: speedKmh == nil ? nil : speedAccuracyKmh,
            gpsTimestamp: speedTimestamp
        )
    }
}
