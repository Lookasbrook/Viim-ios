import XCTest
@testable import Viim

final class CollisionDetectionEngineTests: XCTestCase {
    func testAutomaticCollisionActivationIsFailClosed() {
        XCTAssertFalse(CollisionActivationPrerequisites.safeDefault.canActivate)
        XCTAssertEqual(
            Set(CollisionActivationPrerequisites.safeDefault.blockers),
            Set(CollisionActivationBlocker.allCases)
        )

        let otherwiseReady = CollisionActivationPrerequisites(
            serverKillSwitchEnabled: false,
            hasSafetyKitEntitlement: true,
            hasNotificationPermission: true,
            hasEmergencyConsent: true,
            isProviderDeliveryVerified: true
        )
        XCTAssertFalse(otherwiseReady.canActivate)
        XCTAssertEqual(otherwiseReady.blockers, [.serverKillSwitchDisabled])

        let controlledTestReady = CollisionActivationPrerequisites(
            serverKillSwitchEnabled: true,
            hasSafetyKitEntitlement: true,
            hasNotificationPermission: true,
            hasEmergencyConsent: true,
            isProviderDeliveryVerified: true
        )
        XCTAssertTrue(controlledTestReady.canActivate)
        XCTAssertTrue(controlledTestReady.blockers.isEmpty)
    }

    func testCollisionEnvelopeHasStableIdempotencyKeyAndOptionalLocation() throws {
        let eventID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let detectedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let envelope = CollisionEscalationEnvelope(
            eventID: eventID,
            detectedAt: detectedAt,
            confirmationDeadline: detectedAt.addingTimeInterval(60),
            consentVersion: "emergency-consent-v1"
        )

        XCTAssertTrue(envelope.isStructurallyValid)
        XCTAssertEqual(envelope.idempotencyKey, "viim-collision-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertEqual(try JSONDecoder().decode(CollisionEscalationEnvelope.self, from: JSONEncoder().encode(envelope)), envelope)
    }

    func testCollisionEscalationCannotDeliverBeforeConfirmationDeadline() throws {
        let detectedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let envelope = CollisionEscalationEnvelope(
            eventID: UUID(),
            detectedAt: detectedAt,
            confirmationDeadline: detectedAt.addingTimeInterval(60),
            latitude: 45,
            longitude: -73,
            consentVersion: "emergency-consent-v1"
        )
        var record = try CollisionEscalationRecord(envelope: envelope)

        XCTAssertThrowsError(try record.releaseForDelivery(at: detectedAt.addingTimeInterval(59))) {
            XCTAssertEqual($0 as? CollisionEscalationTransitionError, .confirmationWindowOpen)
        }
        try record.releaseForDelivery(at: envelope.confirmationDeadline)
        XCTAssertEqual(record.phase, .readyForDelivery)
        try record.markProviderAccepted(messageID: "provider-123", at: envelope.confirmationDeadline)
        try record.markDelivered(at: envelope.confirmationDeadline)
        XCTAssertEqual(record.phase, .delivered)
        XCTAssertEqual(record.providerMessageID, "provider-123")
    }

    func testCancelledCollisionCanNeverBeReleasedForDelivery() throws {
        let detectedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let envelope = CollisionEscalationEnvelope(
            eventID: UUID(),
            detectedAt: detectedAt,
            confirmationDeadline: detectedAt.addingTimeInterval(60),
            consentVersion: "emergency-consent-v1"
        )
        var record = try CollisionEscalationRecord(envelope: envelope)

        try record.cancel(at: detectedAt.addingTimeInterval(30))
        XCTAssertEqual(record.phase, .cancelled)
        XCTAssertThrowsError(try record.releaseForDelivery(at: envelope.confirmationDeadline)) {
            XCTAssertEqual($0 as? CollisionEscalationTransitionError, .invalidTransition)
        }
    }

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

    @MainActor
    func testReviewStoreExportsAnIntegrityCheckedAggregateWithoutCoordinates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CollisionCalibrationReviewStore(
            candidateJournal: CollisionShadowJournal(
                fileURL: directory.appendingPathComponent("collision-shadow.json")
            ),
            reviewJournal: CollisionShadowReviewJournal(
                fileURL: directory.appendingPathComponent("collision-reviews.json")
            ),
            coverageJournal: CollisionShadowCoverageJournal(
                fileURL: directory.appendingPathComponent("collision-coverage.json")
            )
        )

        store.reload(trips: [])
        let fileURL = try store.createCalibrationReportExport()
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let report = try decoder.decode(
            CollisionShadowCalibrationReportEnvelope.self,
            from: data
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(report.hasValidIntegrity)
        XCTAssertEqual(report.payload.instrumentationStatus, .insufficientEvidence)
        XCTAssertFalse(text.contains("latitude"))
        XCTAssertFalse(text.contains("longitude"))
        XCTAssertFalse(text.contains("tripID"))
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

    func testCoverageSummaryJoinsFinalizedTripsWithoutDoubleCountingSessions() throws {
        let origin = Date(timeIntervalSinceReferenceDate: 10_000)
        let tripID = UUID()
        let first = coverageRecord(
            tripID: tripID,
            tripStartedAt: origin,
            vehicleType: .voiture,
            startedAt: origin,
            endedAt: origin.addingTimeInterval(60),
            candidateCount: 1
        )
        let overlapping = coverageRecord(
            tripID: tripID,
            tripStartedAt: origin,
            vehicleType: .voiture,
            startedAt: origin.addingTimeInterval(30),
            endedAt: origin.addingTimeInterval(90),
            candidateCount: 2
        )
        let unmatched = coverageRecord(
            tripID: UUID(),
            tripStartedAt: origin,
            vehicleType: .moto,
            startedAt: origin,
            endedAt: origin.addingTimeInterval(50),
            candidateCount: 1
        )
        let trips = [
            CollisionShadowFinalizedTripEvidence(
                id: tripID,
                startDate: origin,
                endDate: origin.addingTimeInterval(100),
                drivingDuration: 100,
                distanceKm: 10,
                vehicleType: .voiture
            ),
            CollisionShadowFinalizedTripEvidence(
                id: UUID(),
                startDate: origin.addingTimeInterval(200),
                endDate: origin.addingTimeInterval(300),
                drivingDuration: 100,
                distanceKm: 20,
                vehicleType: .voiture
            )
        ]
        let realCollision = shadowCandidate(at: origin.addingTimeInterval(40))
            .contextualized(tripID: tripID, vehicleType: .voiture)
        let roadImpact = shadowCandidate(at: origin.addingTimeInterval(70))
            .contextualized(tripID: tripID, vehicleType: .voiture)
        let annotations = [
            CollisionShadowReviewAnnotation(
                candidateID: realCollision.id,
                label: .realCollision,
                reviewedAt: origin.addingTimeInterval(400)
            ),
            CollisionShadowReviewAnnotation(
                candidateID: roadImpact.id,
                label: .roadImpact,
                reviewedAt: origin.addingTimeInterval(400)
            )
        ]

        let summary = CollisionShadowCoverageSummary.summarize(
            [first, overlapping, unmatched],
            finalizedTrips: trips,
            candidates: [realCollision, roadImpact],
            annotations: annotations,
            observationEndedAt: origin.addingTimeInterval(500)
        )

        XCTAssertEqual(summary.eligibleTripCount, 2)
        XCTAssertEqual(summary.coveredTripCount, 1)
        XCTAssertEqual(summary.unmatchedSessionCount, 1)
        XCTAssertEqual(summary.eligibleDrivingDuration, 200)
        XCTAssertEqual(summary.monitoredDrivingDuration, 90)
        XCTAssertEqual(summary.monitoringCoverageRatio, 0.45)
        XCTAssertEqual(summary.estimatedMonitoredDistanceKm, 9, accuracy: 0.001)
        XCTAssertEqual(summary.matchedCandidateCount, 2)
        XCTAssertEqual(
            try XCTUnwrap(summary.candidatesPerThousandMonitoredKm),
            2_000 / 9,
            accuracy: 0.001
        )
        XCTAssertEqual(summary.reviewedCandidateCount, 2)
        XCTAssertEqual(summary.realCollisionReviewCount, 1)
        XCTAssertEqual(summary.realCollisionRatioAmongReviewed, 0.5)
    }

    func testCoverageSummaryRejectsVehicleMismatchAndItsReviews() {
        let origin = Date(timeIntervalSinceReferenceDate: 20_000)
        let tripID = UUID()
        let record = coverageRecord(
            tripID: tripID,
            tripStartedAt: origin,
            vehicleType: .moto,
            startedAt: origin,
            endedAt: origin.addingTimeInterval(60),
            candidateCount: 1
        )
        let trip = CollisionShadowFinalizedTripEvidence(
            id: tripID,
            startDate: origin,
            endDate: origin.addingTimeInterval(60),
            drivingDuration: 60,
            distanceKm: 1,
            vehicleType: .voiture
        )
        let candidate = shadowCandidate(at: origin.addingTimeInterval(30))
            .contextualized(tripID: tripID, vehicleType: .moto)
        let annotation = CollisionShadowReviewAnnotation(
            candidateID: candidate.id,
            label: .realCollision,
            reviewedAt: origin.addingTimeInterval(70)
        )

        let summary = CollisionShadowCoverageSummary.summarize(
            [record],
            finalizedTrips: [trip],
            candidates: [candidate],
            annotations: [annotation],
            observationEndedAt: origin.addingTimeInterval(100)
        )

        XCTAssertEqual(summary.eligibleTripCount, 1)
        XCTAssertEqual(summary.coveredTripCount, 0)
        XCTAssertEqual(summary.unmatchedSessionCount, 1)
        XCTAssertEqual(summary.monitoredDrivingDuration, 0)
        XCTAssertNil(summary.candidatesPerThousandMonitoredKm)
        XCTAssertEqual(summary.reviewedCandidateCount, 0)
        XCTAssertNil(summary.realCollisionRatioAmongReviewed)
    }

    func testCoverageSummaryDoesNotPublishCandidateRateWhenEvidenceJournalFailed() {
        let origin = Date(timeIntervalSinceReferenceDate: 30_000)
        let tripID = UUID()
        let record = coverageRecord(
            tripID: tripID,
            tripStartedAt: origin,
            vehicleType: .voiture,
            startedAt: origin,
            endedAt: origin.addingTimeInterval(60),
            candidateCount: 1
        )
        let trip = CollisionShadowFinalizedTripEvidence(
            id: tripID,
            startDate: origin,
            endDate: origin.addingTimeInterval(60),
            drivingDuration: 60,
            distanceKm: 1,
            vehicleType: .voiture
        )

        let summary = CollisionShadowCoverageSummary.summarize(
            [record],
            finalizedTrips: [trip],
            candidateEvidenceAvailable: false,
            observationEndedAt: origin.addingTimeInterval(100)
        )

        XCTAssertEqual(summary.candidateCount, 1)
        XCTAssertNil(summary.candidatesPerThousandMonitoredKm)
    }

    func testCoverageSummaryDoesNotTreatAnEmptyOpenSessionAsMonitoredTime() {
        let origin = Date(timeIntervalSinceReferenceDate: 40_000)
        let tripID = UUID()
        let emptySession = CollisionShadowCoverageRecord(
            id: UUID(),
            tripID: tripID,
            tripStartedAt: origin,
            vehicleType: .voiture,
            algorithmVersion: CollisionDetectionEngine.algorithmVersion,
            shadowStartedAt: origin,
            lastCheckpointAt: origin.addingTimeInterval(60),
            endedAt: origin.addingTimeInterval(60),
            endReason: .tripEnded,
            frameCount: 0,
            qualifiedGPSFrameCount: 0,
            gapCount: 0,
            missingMotionDuration: 0,
            maximumMotionGap: 0,
            candidateCount: 0,
            motionErrorCount: 1,
            version: CollisionShadowCoverageRecord.schemaVersion
        )
        let trip = CollisionShadowFinalizedTripEvidence(
            id: tripID,
            startDate: origin,
            endDate: origin.addingTimeInterval(60),
            drivingDuration: 60,
            distanceKm: 1,
            vehicleType: .voiture
        )

        let summary = CollisionShadowCoverageSummary.summarize(
            [emptySession],
            finalizedTrips: [trip],
            observationEndedAt: origin.addingTimeInterval(100)
        )

        XCTAssertEqual(summary.eligibleTripCount, 1)
        XCTAssertEqual(summary.coveredTripCount, 0)
        XCTAssertEqual(summary.monitoredDrivingDuration, 0)
        XCTAssertEqual(summary.monitoringCoverageRatio, 0)
    }

    func testCalibrationPolicyPassesOnlyWithPredeclaredVolumeAndQuality() throws {
        let passingSummary = calibrationSummary()
        let generatedAt = Date(timeIntervalSinceReferenceDate: 500_000)
        let report = try CollisionShadowCalibrationReportEnvelope.make(
            summary: passingSummary,
            algorithmVersion: CollisionDetectionEngine.algorithmVersion,
            generatedAt: generatedAt
        )

        XCTAssertEqual(report.payload.instrumentationStatus, .passed)
        XCTAssertEqual(report.payload.candidateReviewStatus, .passed)
        XCTAssertEqual(report.payload.policyVersion, CollisionShadowCalibrationPolicy.version)
        XCTAssertEqual(report.payload.metrics.eligibleTripCount, 100)
        XCTAssertEqual(report.payload.metrics.estimatedMonitoredDistanceKm, 1_000, accuracy: 0.001)
        XCTAssertEqual(report.payload.metrics.matchedCandidateCount, 30)
        XCTAssertEqual(report.payload.metrics.reviewedCandidateCount, 27)
        XCTAssertTrue(report.hasValidIntegrity)

        let insufficient = CollisionShadowCoverageSummary.summarize([])
        XCTAssertEqual(
            CollisionShadowCalibrationPolicy.current.instrumentationStatus(for: insufficient),
            .insufficientEvidence
        )
        XCTAssertEqual(
            CollisionShadowCalibrationPolicy.current.candidateReviewStatus(for: insufficient),
            .insufficientEvidence
        )
    }

    func testCalibrationPolicyFailsClosedAfterEnoughPoorQualityEvidence() {
        let poorGPSSummary = calibrationSummary(qualifiedGPSRatio: 0.5)

        XCTAssertEqual(
            CollisionShadowCalibrationPolicy.current.instrumentationStatus(for: poorGPSSummary),
            .failed
        )
        XCTAssertEqual(
            CollisionShadowCalibrationPolicy.current.candidateReviewStatus(for: poorGPSSummary),
            .passed
        )
    }

    func testCalibrationReportContainsNoTripIdentifiersAndDetectsTampering() throws {
        let report = try CollisionShadowCalibrationReportEnvelope.make(
            summary: calibrationSummary(),
            algorithmVersion: CollisionDetectionEngine.algorithmVersion,
            generatedAt: Date(timeIntervalSinceReferenceDate: 600_000)
        )
        let data = try report.encodedData()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(text.contains("tripID"))
        XCTAssertFalse(text.contains("latitude"))
        XCTAssertFalse(text.contains("longitude"))
        XCTAssertFalse(text.contains("routePoints"))
        XCTAssertTrue(text.contains("sha256_integrity_is_not_authenticity"))

        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var payload = try XCTUnwrap(root["payload"] as? [String: Any])
        var metrics = try XCTUnwrap(payload["metrics"] as? [String: Any])
        metrics["sessionCount"] = 999
        payload["metrics"] = metrics
        root["payload"] = payload
        let tamperedData = try JSONSerialization.data(withJSONObject: root)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let tampered = try decoder.decode(
            CollisionShadowCalibrationReportEnvelope.self,
            from: tamperedData
        )

        XCTAssertFalse(tampered.hasValidIntegrity)
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

    private func coverageRecord(
        tripID: UUID,
        tripStartedAt: Date,
        vehicleType: VehicleType,
        startedAt: Date,
        endedAt: Date,
        candidateCount: Int,
        qualifiedGPSRatio: Double = 1
    ) -> CollisionShadowCoverageRecord {
        let frameCount = max(
            candidateCount,
            Int(endedAt.timeIntervalSince(startedAt) /
                CollisionShadowCoverageAccumulator.expectedFrameInterval)
        )
        return CollisionShadowCoverageRecord(
            id: UUID(),
            tripID: tripID,
            tripStartedAt: tripStartedAt,
            vehicleType: vehicleType,
            algorithmVersion: CollisionDetectionEngine.algorithmVersion,
            shadowStartedAt: startedAt,
            lastCheckpointAt: endedAt,
            endedAt: endedAt,
            endReason: .tripEnded,
            frameCount: frameCount,
            qualifiedGPSFrameCount: Int(Double(frameCount) * qualifiedGPSRatio),
            gapCount: 0,
            missingMotionDuration: 0,
            maximumMotionGap: 0,
            candidateCount: candidateCount,
            motionErrorCount: 0,
            version: CollisionShadowCoverageRecord.schemaVersion
        )
    }

    private func calibrationSummary(
        qualifiedGPSRatio: Double = 1
    ) -> CollisionShadowCoverageSummary {
        let origin = Date(timeIntervalSinceReferenceDate: 100_000)
        var records: [CollisionShadowCoverageRecord] = []
        var trips: [CollisionShadowFinalizedTripEvidence] = []
        var candidates: [CollisionShadowCandidate] = []
        var annotations: [CollisionShadowReviewAnnotation] = []

        for index in 0..<100 {
            let startedAt = origin.addingTimeInterval(Double(index) * 1_000)
            let endedAt = startedAt.addingTimeInterval(600)
            let tripID = UUID()
            let hasCandidate = index < 30
            records.append(
                coverageRecord(
                    tripID: tripID,
                    tripStartedAt: startedAt,
                    vehicleType: .voiture,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    candidateCount: hasCandidate ? 1 : 0,
                    qualifiedGPSRatio: qualifiedGPSRatio
                )
            )
            trips.append(
                CollisionShadowFinalizedTripEvidence(
                    id: tripID,
                    startDate: startedAt,
                    endDate: endedAt,
                    drivingDuration: 600,
                    distanceKm: 10,
                    vehicleType: .voiture
                )
            )
            if hasCandidate {
                let candidate = shadowCandidate(at: startedAt.addingTimeInterval(300))
                    .contextualized(tripID: tripID, vehicleType: .voiture)
                candidates.append(candidate)
                if index < 27 {
                    annotations.append(
                        CollisionShadowReviewAnnotation(
                            candidateID: candidate.id,
                            label: .roadImpact,
                            reviewedAt: endedAt.addingTimeInterval(1)
                        )
                    )
                }
            }
        }

        return CollisionShadowCoverageSummary.summarize(
            records,
            finalizedTrips: trips,
            candidates: candidates,
            annotations: annotations,
            observationEndedAt: origin.addingTimeInterval(100_000)
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
