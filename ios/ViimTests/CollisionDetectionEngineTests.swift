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

    func testShadowMonitorResetsWhenTripOrVehicleContextChanges() {
        let tripA = UUID()
        let tripB = UUID()

        XCTAssertFalse(
            CollisionShadowMonitor.shouldResetMonitoringContext(
                currentTripID: tripA,
                nextTripID: tripA,
                currentVehicleType: .voiture,
                nextVehicleType: .voiture
            )
        )
        XCTAssertTrue(
            CollisionShadowMonitor.shouldResetMonitoringContext(
                currentTripID: tripA,
                nextTripID: tripB,
                currentVehicleType: .voiture,
                nextVehicleType: .voiture
            )
        )
        XCTAssertTrue(
            CollisionShadowMonitor.shouldResetMonitoringContext(
                currentTripID: tripA,
                nextTripID: tripA,
                currentVehicleType: .voiture,
                nextVehicleType: .moto
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

    func testLegacyShadowCandidateDecodesWithoutTripContext() throws {
        let original = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 80))
            .contextualized(tripID: UUID(), vehicleType: .moto)
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "tripID")
        object.removeValue(forKey: "vehicleType")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            CollisionShadowCandidate.self,
            from: legacyData
        )

        XCTAssertNil(decoded.tripID)
        XCTAssertNil(decoded.vehicleType)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertTrue(decoded.isStructurallyValid)
    }

    func testContextualizedShadowCandidateRoundTripsExactTripAndVehicle() throws {
        let tripID = UUID()
        let candidate = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 90))
            .contextualized(tripID: tripID, vehicleType: .voiture)

        let data = try JSONEncoder().encode(candidate)
        let decoded = try JSONDecoder().decode(CollisionShadowCandidate.self, from: data)

        XCTAssertEqual(decoded, candidate)
        XCTAssertEqual(decoded.tripID, tripID)
        XCTAssertEqual(decoded.vehicleType, .voiture)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("latitude"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("longitude"))
    }

    func testReviewJournalDoesNotRewriteRawEvidence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let candidateURL = directory.appendingPathComponent("collision-shadow.json")
        let reviewURL = directory.appendingPathComponent("collision-reviews.json")
        let candidate = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 100))
        let candidateJournal = CollisionShadowJournal(fileURL: candidateURL)
        let reviewJournal = CollisionShadowReviewJournal(fileURL: reviewURL)
        try candidateJournal.append(candidate)
        let rawEvidenceBeforeReview = try Data(contentsOf: candidateURL)

        try reviewJournal.setReview(
            candidateID: candidate.id,
            label: .roadImpact,
            reviewedAt: Date(timeIntervalSinceReferenceDate: 101)
        )

        XCTAssertEqual(try Data(contentsOf: candidateURL), rawEvidenceBeforeReview)
        XCTAssertEqual(
            try reviewJournal.load(),
            [
                CollisionShadowReviewAnnotation(
                    candidateID: candidate.id,
                    label: .roadImpact,
                    reviewedAt: Date(timeIntervalSinceReferenceDate: 101)
                )
            ]
        )
    }

    func testReviewJournalIdempotentRetryPreservesOriginalReviewDate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reviewURL = directory.appendingPathComponent("collision-reviews.json")
        let journal = CollisionShadowReviewJournal(fileURL: reviewURL)
        let candidateID = UUID()
        let originalDate = Date(timeIntervalSinceReferenceDate: 110)

        try journal.setReview(
            candidateID: candidateID,
            label: .hardBraking,
            reviewedAt: originalDate
        )
        try journal.setReview(
            candidateID: candidateID,
            label: .hardBraking,
            reviewedAt: originalDate.addingTimeInterval(60)
        )

        XCTAssertEqual(try journal.load().first?.reviewedAt, originalDate)
    }

    @MainActor
    func testPendingReviewExcludesReviewedCandidatesAndSortsNewestFirst() {
        let older = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 120))
        let reviewed = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 130))
        let newer = shadowCandidate(at: Date(timeIntervalSinceReferenceDate: 140))
        let annotations = [
            CollisionShadowReviewAnnotation(
                candidateID: reviewed.id,
                label: .noUnusualEvent,
                reviewedAt: Date(timeIntervalSinceReferenceDate: 150)
            ),
            CollisionShadowReviewAnnotation(
                candidateID: UUID(),
                label: .uncertain,
                reviewedAt: Date(timeIntervalSinceReferenceDate: 150)
            )
        ]

        XCTAssertEqual(
            CollisionCalibrationReviewStore.pending(
                candidates: [older, reviewed, newer],
                annotations: annotations
            ),
            [newer, older]
        )
    }

    @MainActor
    func testReviewStoreRejectsCandidateAbsentFromEvidenceJournal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let candidateJournal = CollisionShadowJournal(
            fileURL: directory.appendingPathComponent("collision-shadow.json")
        )
        let reviewJournal = CollisionShadowReviewJournal(
            fileURL: directory.appendingPathComponent("collision-reviews.json")
        )
        let store = CollisionCalibrationReviewStore(
            candidateJournal: candidateJournal,
            reviewJournal: reviewJournal,
            coverageJournal: CollisionShadowCoverageJournal(
                fileURL: directory.appendingPathComponent("collision-coverage.json")
            )
        )

        XCTAssertThrowsError(
            try store.review(candidateID: UUID(), label: .uncertain)
        ) { error in
            XCTAssertEqual(
                error as? CollisionCalibrationReviewStore.ReviewError,
                .candidateMissing
            )
        }
        XCTAssertEqual(try reviewJournal.load(), [])
    }

    func testReviewJournalQuarantinesMalformedAnnotationsAndKeepsRecording() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-reviews.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let malformed = Data("{truncated".utf8)
        try malformed.write(to: fileURL)
        let journal = CollisionShadowReviewJournal(fileURL: fileURL)
        let candidateID = UUID()

        try journal.setReview(candidateID: candidateID, label: .phoneMovement)

        XCTAssertEqual(try journal.load().map(\.candidateID), [candidateID])
        let quarantineURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        XCTAssertEqual(quarantineURLs.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(quarantineURLs.first)), malformed)
    }

    func testCollisionPolicyQualifiesOnlyFreshAccurateGPSSpeed() {
        let now = Date(timeIntervalSinceReferenceDate: 200)
        let valid = frame(
            at: now,
            accelerationG: 0,
            speedKmh: 45,
            speedAccuracyKmh: 4,
            speedTimestamp: now.addingTimeInterval(-1)
        )
        let stale = frame(
            at: now,
            accelerationG: 0,
            speedKmh: 45,
            speedAccuracyKmh: 4,
            speedTimestamp: now.addingTimeInterval(-4)
        )
        let inaccurate = frame(
            at: now,
            accelerationG: 0,
            speedKmh: 45,
            speedAccuracyKmh: 10,
            speedTimestamp: now
        )

        XCTAssertEqual(CollisionDetectionPolicy.shadowV2.qualifiedSpeed(from: valid)?.value, 45)
        XCTAssertNil(CollisionDetectionPolicy.shadowV2.qualifiedSpeed(from: stale))
        XCTAssertNil(CollisionDetectionPolicy.shadowV2.qualifiedSpeed(from: inaccurate))
    }

    func testCoverageAccumulatorMeasuresFramesGPSGapsCandidatesAndErrors() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 300)
        var accumulator = CollisionShadowCoverageAccumulator(
            context: CollisionShadowTripContext(
                id: UUID(),
                startedAt: startedAt.addingTimeInterval(-10)
            ),
            vehicleType: .voiture,
            startedAt: startedAt,
            sessionID: UUID()
        )

        XCTAssertFalse(
            accumulator.ingest(
                frame: frame(
                    at: startedAt.addingTimeInterval(0.1),
                    accelerationG: 0,
                    speedKmh: 40,
                    speedTimestamp: startedAt.addingTimeInterval(0.1)
                ),
                hasQualifiedGPS: true
            )
        )
        XCTAssertFalse(
            accumulator.ingest(
                frame: frame(
                    at: startedAt.addingTimeInterval(0.2),
                    accelerationG: 0,
                    speedKmh: nil,
                    speedTimestamp: nil
                ),
                hasQualifiedGPS: false
            )
        )
        XCTAssertTrue(
            accumulator.ingest(
                frame: frame(
                    at: startedAt.addingTimeInterval(2),
                    accelerationG: 0,
                    speedKmh: 40,
                    speedTimestamp: startedAt.addingTimeInterval(2)
                ),
                hasQualifiedGPS: true
            )
        )
        accumulator.noteCandidate(at: startedAt.addingTimeInterval(2))
        accumulator.noteMotionError(at: startedAt.addingTimeInterval(2.5))
        accumulator.finish(at: startedAt.addingTimeInterval(3), reason: .tripEnded)

        let record = accumulator.record
        XCTAssertEqual(record.frameCount, 3)
        XCTAssertEqual(record.qualifiedGPSFrameCount, 2)
        XCTAssertEqual(record.gapCount, 1)
        XCTAssertEqual(record.missingMotionDuration, 1.78, accuracy: 0.000_001)
        XCTAssertEqual(record.maximumMotionGap, 1.8, accuracy: 0.000_001)
        XCTAssertEqual(record.candidateCount, 1)
        XCTAssertEqual(record.motionErrorCount, 1)
        XCTAssertEqual(record.endReason, .tripEnded)
        XCTAssertEqual(record.endedAt, startedAt.addingTimeInterval(3))
        XCTAssertTrue(record.isStructurallyValid)
    }

    func testCoverageAccumulatorRejectsRegressingFrameWithoutCorruptingCounters() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 400)
        var accumulator = CollisionShadowCoverageAccumulator(
            context: CollisionShadowTripContext(
                id: UUID(),
                startedAt: startedAt
            ),
            vehicleType: .moto,
            startedAt: startedAt
        )
        let first = frame(
            at: startedAt.addingTimeInterval(1),
            accelerationG: 0,
            speedKmh: nil,
            speedTimestamp: nil
        )
        let regressing = frame(
            at: startedAt.addingTimeInterval(0.5),
            accelerationG: 0,
            speedKmh: nil,
            speedTimestamp: nil
        )

        _ = accumulator.ingest(frame: first, hasQualifiedGPS: false)
        _ = accumulator.ingest(frame: regressing, hasQualifiedGPS: false)

        XCTAssertEqual(accumulator.record.frameCount, 1)
        XCTAssertEqual(accumulator.record.lastCheckpointAt, first.timestamp)
        XCTAssertTrue(accumulator.record.isStructurallyValid)
    }

    func testCoverageJournalPersistsUnfinishedCheckpointAndMonotonicFinalRecord() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-coverage.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = CollisionShadowCoverageJournal(fileURL: fileURL)
        let startedAt = Date(timeIntervalSinceReferenceDate: 500)
        var accumulator = CollisionShadowCoverageAccumulator(
            context: CollisionShadowTripContext(
                id: UUID(),
                startedAt: startedAt.addingTimeInterval(-5)
            ),
            vehicleType: .voiture,
            startedAt: startedAt,
            sessionID: UUID()
        )

        try journal.upsert(accumulator.record)
        XCTAssertNil(try journal.load().first?.endedAt)

        _ = accumulator.ingest(
            frame: frame(
                at: startedAt.addingTimeInterval(1),
                accelerationG: 0,
                speedKmh: 30,
                speedTimestamp: startedAt.addingTimeInterval(1)
            ),
            hasQualifiedGPS: true
        )
        try journal.upsert(accumulator.record)
        accumulator.finish(at: startedAt.addingTimeInterval(2), reason: .tripEnded)
        try journal.upsert(accumulator.record)

        let persisted = try XCTUnwrap(journal.load().first)
        XCTAssertEqual(persisted, accumulator.record)
        XCTAssertEqual(persisted.frameCount, 1)
        XCTAssertEqual(persisted.endReason, .tripEnded)
        XCTAssertTrue(persisted.isStructurallyValid)
    }

    func testCoverageJournalRejectsRegressionAndNeverReopensFinalSession() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-coverage.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = CollisionShadowCoverageJournal(fileURL: fileURL)
        let startedAt = Date(timeIntervalSinceReferenceDate: 600)
        var accumulator = CollisionShadowCoverageAccumulator(
            context: CollisionShadowTripContext(id: UUID(), startedAt: startedAt),
            vehicleType: .voiture,
            startedAt: startedAt,
            sessionID: UUID()
        )
        _ = accumulator.ingest(
            frame: frame(
                at: startedAt.addingTimeInterval(1),
                accelerationG: 0,
                speedKmh: nil,
                speedTimestamp: nil
            ),
            hasQualifiedGPS: false
        )
        let checkpoint = accumulator.record
        try journal.upsert(checkpoint)
        accumulator.finish(at: startedAt.addingTimeInterval(2), reason: .tripEnded)
        let final = accumulator.record
        try journal.upsert(final)

        XCTAssertThrowsError(try journal.upsert(checkpoint)) { error in
            XCTAssertEqual(
                error as? CollisionShadowCoverageJournal.IntegrityError,
                .conflictingSession
            )
        }
        XCTAssertEqual(try journal.load(), [final])
    }

    func testCoverageJournalIsBoundedProtectedAndContainsNoCoordinates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-coverage.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = CollisionShadowCoverageJournal(fileURL: fileURL, retentionLimit: 2)
        let baseDate = Date(timeIntervalSinceReferenceDate: 700)

        for offset in 0..<3 {
            let startedAt = baseDate.addingTimeInterval(Double(offset))
            let accumulator = CollisionShadowCoverageAccumulator(
                context: CollisionShadowTripContext(id: UUID(), startedAt: startedAt),
                vehicleType: .voiture,
                startedAt: startedAt,
                sessionID: UUID()
            )
            try journal.upsert(accumulator.record)
        }

        let data = try Data(contentsOf: fileURL)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(try journal.load().count, 2)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("latitude"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("longitude"))
        XCTAssertTrue(CollisionShadowJournal.protectedWriteOptions.contains(.atomic))
        XCTAssertTrue(
            CollisionShadowJournal.protectedWriteOptions.contains(
                .completeFileProtectionUntilFirstUserAuthentication
            )
        )
    }

    func testCoverageJournalQuarantinesMalformedDataAndKeepsRecording() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("collision-coverage.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let malformed = Data("{truncated".utf8)
        try malformed.write(to: fileURL)
        let journal = CollisionShadowCoverageJournal(fileURL: fileURL)
        let startedAt = Date(timeIntervalSinceReferenceDate: 800)
        let accumulator = CollisionShadowCoverageAccumulator(
            context: CollisionShadowTripContext(id: UUID(), startedAt: startedAt),
            vehicleType: .moto,
            startedAt: startedAt
        )

        try journal.upsert(accumulator.record)

        XCTAssertEqual(try journal.load(), [accumulator.record])
        let quarantineURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        XCTAssertEqual(quarantineURLs.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(quarantineURLs.first)), malformed)
    }

    func testCoverageSummaryKeepsCollectionAndDetectionCountersSeparate() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 900)
        var completed = CollisionShadowCoverageAccumulator(
            context: CollisionShadowTripContext(id: UUID(), startedAt: startedAt),
            vehicleType: .voiture,
            startedAt: startedAt
        )
        _ = completed.ingest(
            frame: frame(
                at: startedAt.addingTimeInterval(1),
                accelerationG: 0,
                speedKmh: 30,
                speedTimestamp: startedAt.addingTimeInterval(1)
            ),
            hasQualifiedGPS: true
        )
        completed.noteCandidate(at: startedAt.addingTimeInterval(1))
        completed.finish(at: startedAt.addingTimeInterval(2), reason: .tripEnded)

        var unfinished = CollisionShadowCoverageAccumulator(
            context: CollisionShadowTripContext(id: UUID(), startedAt: startedAt),
            vehicleType: .moto,
            startedAt: startedAt
        )
        _ = unfinished.ingest(
            frame: frame(
                at: startedAt.addingTimeInterval(1),
                accelerationG: 0,
                speedKmh: nil,
                speedTimestamp: nil
            ),
            hasQualifiedGPS: false
        )
        unfinished.noteMotionError(at: startedAt.addingTimeInterval(2))

        let summary = CollisionShadowCoverageSummary.summarize([
            completed.record,
            unfinished.record
        ])

        XCTAssertEqual(summary.sessionCount, 2)
        XCTAssertEqual(summary.completedSessionCount, 1)
        XCTAssertEqual(summary.unfinishedSessionCount, 1)
        XCTAssertEqual(summary.frameCount, 2)
        XCTAssertEqual(summary.qualifiedGPSFrameCount, 1)
        XCTAssertEqual(summary.qualifiedGPSRatio, 0.5)
        XCTAssertEqual(summary.candidateCount, 1)
        XCTAssertEqual(summary.motionErrorCount, 1)
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
