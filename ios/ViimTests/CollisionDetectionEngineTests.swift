import XCTest
@testable import Viim

final class CollisionDetectionEngineTests: XCTestCase {
    func testShadowMonitorRunsOnlyForActiveMotorizedTripsWithHardware() {
        XCTAssertTrue(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: true,
                vehicleType: .voiture,
                locationCollectionActive: true,
                deviceMotionAvailable: true
            )
        )
        XCTAssertTrue(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: true,
                vehicleType: .moto,
                locationCollectionActive: true,
                deviceMotionAvailable: true
            )
        )
        XCTAssertFalse(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: true,
                vehicleType: .velo,
                locationCollectionActive: true,
                deviceMotionAvailable: true
            )
        )
        XCTAssertFalse(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: false,
                vehicleType: .voiture,
                locationCollectionActive: true,
                deviceMotionAvailable: true
            )
        )
        XCTAssertFalse(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: true,
                vehicleType: .voiture,
                locationCollectionActive: true,
                deviceMotionAvailable: false
            )
        )
        XCTAssertFalse(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: true,
                vehicleType: .voiture,
                locationCollectionActive: false,
                deviceMotionAvailable: true
            )
        )
        XCTAssertFalse(
            CollisionShadowMonitor.shouldMonitor(
                tripActive: true,
                vehicleType: nil,
                locationCollectionActive: true,
                deviceMotionAvailable: true
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
        XCTAssertEqual(candidate.preImpactSpeedAccuracyKmh, 3)
        XCTAssertEqual(candidate.postImpactSpeedAccuracyKmh, 4)
        XCTAssertFalse(engine.hasPendingImpact)
    }

    func testApparentSpeedLossInsideCombinedGPSUncertaintyIsRejected() {
        var engine = CollisionDetectionEngine()
        let impactAt = Date(timeIntervalSinceReferenceDate: 3_500)

        XCTAssertNil(
            engine.ingest(
                frame(
                    at: impactAt,
                    accelerationG: 4.2,
                    speedKmh: 60,
                    speedAccuracyKmh: 9,
                    speedTimestamp: impactAt
                )
            )
        )

        XCTAssertNil(
            engine.ingest(
                frame(
                    at: impactAt.addingTimeInterval(2),
                    accelerationG: 0.2,
                    speedKmh: 48,
                    speedAccuracyKmh: 9,
                    speedTimestamp: impactAt.addingTimeInterval(2)
                )
            )
        )
        XCTAssertTrue(engine.hasPendingImpact)
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

    func testShadowJournalQuarantinesMalformedEvidenceAndKeepsRecording() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-shadow.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let malformedEvidence = Data("{truncated".utf8)
        try malformedEvidence.write(to: fileURL)

        let journal = CollisionShadowJournal(fileURL: fileURL)
        let candidate = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 10))
        try journal.append(candidate)

        XCTAssertEqual(try journal.load(), [candidate])
        let quarantineURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        XCTAssertEqual(quarantineURLs.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(quarantineURLs.first)), malformedEvidence)
    }

    func testShadowJournalQuarantinesOversizedEvidenceAndKeepsRecording() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-shadow.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oversizedEvidence = Data(repeating: 0x41, count: 513)
        try oversizedEvidence.write(to: fileURL)

        let journal = CollisionShadowJournal(
            fileURL: fileURL,
            maximumFileBytes: 512
        )
        let candidate = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 20))
        try journal.append(candidate)

        let quarantineURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        XCTAssertEqual(quarantineURLs.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(quarantineURLs.first)), oversizedEvidence)
        XCTAssertEqual(try journal.load(), [candidate])
    }

    func testShadowJournalRejectsImpossibleCandidateWithoutTouchingExistingEvidence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-shadow.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = CollisionShadowJournal(fileURL: fileURL)
        let validCandidate = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 30))
        try journal.append(validCandidate)
        let originalData = try Data(contentsOf: fileURL)

        let invalidCandidate = CollisionShadowCandidate(
            id: UUID(),
            algorithmVersion: CollisionDetectionEngine.algorithmVersion,
            impactAt: Date(timeIntervalSinceReferenceDate: 40),
            confirmedAt: Date(timeIntervalSinceReferenceDate: 41),
            peakUserAccelerationG: 4,
            peakRotationRate: 1,
            preImpactSpeedKmh: 50,
            postImpactSpeedKmh: 5,
            speedLossKmh: 1
        )

        XCTAssertThrowsError(try journal.append(invalidCandidate)) { error in
            XCTAssertEqual(error as? CollisionShadowJournal.IntegrityError, .invalidEvidence)
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
        XCTAssertEqual(try journal.load(), [validCandidate])
    }

    func testShadowJournalQuarantinesDuplicateIdentifiers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-shadow.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let duplicate = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 50))
        try JSONEncoder().encode([duplicate, duplicate]).write(to: fileURL)

        let journal = CollisionShadowJournal(fileURL: fileURL)
        let nextCandidate = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 60))
        try journal.append(nextCandidate)

        XCTAssertEqual(try journal.load(), [nextCandidate])
        let quarantineCount = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }.count
        XCTAssertEqual(quarantineCount, 1)
    }

    func testShadowJournalAppendIsIdempotentForSameCandidate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-shadow.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = CollisionShadowJournal(fileURL: fileURL)
        let candidate = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 70))

        try journal.append(candidate)
        try journal.append(candidate)

        XCTAssertEqual(try journal.load(), [candidate])
    }

    func testShadowJournalRejectsConflictingPayloadForSameIdentifier() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-shadow.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = CollisionShadowJournal(fileURL: fileURL)
        let candidate = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 75))
        try journal.append(candidate)
        let originalData = try Data(contentsOf: fileURL)
        let conflicting = CollisionShadowCandidate(
            id: candidate.id,
            algorithmVersion: candidate.algorithmVersion,
            impactAt: candidate.impactAt,
            confirmedAt: candidate.confirmedAt,
            peakUserAccelerationG: 5,
            peakRotationRate: candidate.peakRotationRate,
            preImpactSpeedKmh: candidate.preImpactSpeedKmh,
            postImpactSpeedKmh: candidate.postImpactSpeedKmh,
            speedLossKmh: candidate.speedLossKmh
        )

        XCTAssertThrowsError(try journal.append(conflicting)) { error in
            XCTAssertEqual(
                error as? CollisionShadowJournal.IntegrityError,
                .conflictingIdentifier
            )
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
        XCTAssertEqual(try journal.load(), [candidate])
    }

    func testShadowJournalWritesAtomicallyWithBackgroundReadableProtection() {
        XCTAssertTrue(CollisionShadowJournal.protectedWriteOptions.contains(.atomic))
        XCTAssertTrue(
            CollisionShadowJournal.protectedWriteOptions.contains(
                .completeFileProtectionUntilFirstUserAuthentication
            )
        )
    }

    private func shadowCandidate(at impactAt: Date) -> CollisionShadowCandidate {
        CollisionShadowCandidate(
            id: UUID(),
            algorithmVersion: CollisionDetectionEngine.algorithmVersion,
            impactAt: impactAt,
            confirmedAt: impactAt.addingTimeInterval(1),
            peakUserAccelerationG: 4,
            peakRotationRate: 1,
            preImpactSpeedKmh: 50,
            postImpactSpeedKmh: 5,
            speedLossKmh: 45
        )
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
