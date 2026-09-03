import XCTest
@testable import Viim

final class CollectionHealthTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let uptime: TimeInterval = 2_000_000

    func testEventSchemaRejectsPayloadThatDoesNotMatchKind() {
        XCTAssertFalse(
            event(
                .acceptedSample,
                secondsAgo: 0,
                tripOutcome: .persisted
            ).isStructurallyValid
        )
        XCTAssertFalse(
            event(.tripOutcome, secondsAgo: 0).isStructurallyValid
        )
        XCTAssertTrue(
            outcome(.persisted, secondsAgo: 0).isStructurallyValid
        )
    }

    func testJournalRoundTripsEveryEventWithoutPIIFields() throws {
        let fixture = try JournalFixture()
        let journal = fixture.journal
        let events = plainKinds.enumerated().map { index, kind in
            event(kind, secondsAgo: TimeInterval(plainKinds.count - index) * 301)
        } + [
            outcome(.persisted, secondsAgo: 150),
            failure(.tripStoreWrite, secondsAgo: 0)
        ]

        for value in events {
            try journal.append(value, now: now)
        }

        XCTAssertEqual(try journal.load(now: now), events.sorted(by: eventOrder))
        let json = try String(contentsOf: fixture.fileURL, encoding: .utf8).lowercased()
        XCTAssertFalse(json.contains("latitude"))
        XCTAssertFalse(json.contains("longitude"))
        XCTAssertFalse(json.contains("coordinate"))
        XCTAssertFalse(json.contains("phone"))
        XCTAssertFalse(json.contains("contact"))
        XCTAssertFalse(json.contains("speed"))
    }

    func testJournalCoalescesLocationAndAcceptedSampleHeartbeatsIndependently() throws {
        let fixture = try JournalFixture()
        let journal = fixture.journal

        try journal.append(event(.locationBatchReceived, secondsAgo: 600), now: now)
        try journal.append(event(.acceptedSample, secondsAgo: 590), now: now)
        try journal.append(event(.locationBatchReceived, secondsAgo: 500), now: now)
        try journal.append(event(.acceptedSample, secondsAgo: 490), now: now)
        try journal.append(event(.acceptedSample, secondsAgo: 289), now: now)

        let stored = try journal.load(now: now)
        XCTAssertEqual(stored.filter { $0.kind == .locationBatchReceived }.count, 1)
        XCTAssertEqual(stored.filter { $0.kind == .acceptedSample }.count, 2)
    }

    func testJournalCoalescesStrongMotionHeartbeats() throws {
        let fixture = try JournalFixture()

        try fixture.journal.append(
            event(.motionMovementDetected, secondsAgo: 600),
            now: now
        )
        try fixture.journal.append(
            event(.motionMovementDetected, secondsAgo: 500),
            now: now
        )
        try fixture.journal.append(
            event(.motionMovementDetected, secondsAgo: 299),
            now: now
        )

        XCTAssertEqual(
            try fixture.journal.load(now: now).filter {
                $0.kind == .motionMovementDetected
            }.count,
            2
        )
    }

    func testJournalBoundsRecentDetailWhilePreservingObservationAnchor() throws {
        let fixture = try JournalFixture(maximumEventCount: 3)
        let journal = fixture.journal

        try journal.append(
            event(.trackingReady, secondsAgo: CollectionHealthJournal.retentionDuration + 1),
            now: now
        )
        try journal.append(event(.trackingReady, secondsAgo: 4), now: now)
        try journal.append(event(.passiveWakeupReceived, secondsAgo: 3), now: now)
        try journal.append(event(.motionMovementDetected, secondsAgo: 2), now: now)
        try journal.append(event(.tripStarted, secondsAgo: 1), now: now)

        let stored = try journal.load(now: now)
        XCTAssertEqual(stored.count, 3)
        XCTAssertEqual(
            stored.map(\.kind),
            [.trackingReady, .motionMovementDetected, .tripStarted]
        )
    }

    func testJournalWritesAtomicallyWithBackgroundReadableProtection() {
        XCTAssertTrue(CollectionHealthJournal.protectedWriteOptions.contains(.atomic))
        XCTAssertTrue(
            CollectionHealthJournal.protectedWriteOptions.contains(
                .completeFileProtectionUntilFirstUserAuthentication
            )
        )
    }

    func testJournalWriteFailureIsImmediatelyExposedAsStorageUnavailable() throws {
        let fixture = try JournalFixture(maximumFileBytes: 1)

        XCTAssertThrowsError(
            try fixture.journal.append(event(.trackingReady, secondsAgo: 0), now: now)
        )
        XCTAssertFalse(fixture.journal.storageAvailable)
    }

    func testJournalQuarantinesMalformedJSON() throws {
        let fixture = try JournalFixture()
        try Data("not-json".utf8).write(to: fixture.fileURL, options: .atomic)

        XCTAssertThrowsError(try fixture.journal.load(now: now)) { error in
            XCTAssertEqual(error as? CollectionHealthJournal.IntegrityError, .malformed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        XCTAssertEqual(try fixture.quarantinedFiles().count, 1)
    }

    func testJournalQuarantinesOversizedInput() throws {
        let fixture = try JournalFixture(maximumFileBytes: 32)
        try Data(repeating: 0x41, count: 33).write(to: fixture.fileURL, options: .atomic)

        XCTAssertThrowsError(try fixture.journal.load(now: now)) { error in
            XCTAssertEqual(error as? CollectionHealthJournal.IntegrityError, .oversized)
        }
        XCTAssertEqual(try fixture.quarantinedFiles().count, 1)
    }

    func testAppendAfterCorruptionKeepsAVisiblePersistenceFailure() throws {
        let fixture = try JournalFixture()
        try Data("not-json".utf8).write(to: fixture.fileURL, options: .atomic)

        try fixture.journal.append(
            event(.trackingReady, secondsAgo: 0),
            now: now
        )

        let stored = try fixture.journal.load(now: now)
        XCTAssertTrue(
            stored.contains {
                $0.kind == .persistenceFailure &&
                    $0.persistenceFailure == .healthJournalRead
            }
        )
        XCTAssertEqual(try fixture.quarantinedFiles().count, 1)
    }

    func testJournalRejectsInvalidEventWithoutReplacingExistingEvidence() throws {
        let fixture = try JournalFixture()
        let valid = event(.trackingReady, secondsAgo: 10)
        try fixture.journal.append(valid, now: now)
        let invalid = CollectionHealthEvent(
            occurredAt: now,
            systemUptime: uptime,
            bootAnchor: bootAnchor,
            kind: .tripOutcome
        )

        XCTAssertThrowsError(try fixture.journal.append(invalid, now: now)) { error in
            XCTAssertEqual(error as? CollectionHealthJournal.IntegrityError, .invalidEvent)
        }
        XCTAssertEqual(try fixture.journal.load(now: now), [valid])
    }

    func testJournalIsThreadSafeAndKeepsAllNonHeartbeatEvents() throws {
        let fixture = try JournalFixture(maximumEventCount: 64)
        let errorLock = NSLock()
        var errors: [Error] = []

        DispatchQueue.concurrentPerform(iterations: 40) { index in
            do {
                try fixture.journal.append(
                    event(.tripStarted, secondsAgo: TimeInterval(index)),
                    now: now
                )
            } catch {
                errorLock.lock()
                errors.append(error)
                errorLock.unlock()
            }
        }

        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(try fixture.journal.load(now: now).count, 40)
    }

    func testStorageUnavailableHasHighestPriority() {
        let snapshot = evaluate(
            [outcome(.failedRetryable, secondsAgo: 60)],
            readiness: .permissionDenied,
            storageAvailable: false,
            hasStaleActiveDraft: true
        )

        XCTAssertEqual(snapshot.state, .unavailable)
    }

    func testConfigurationRequiredPrecedesPersistenceAndMovementFailures() {
        let snapshot = evaluate(
            [
                outcome(.failedRetryable, secondsAgo: 600),
                event(.motionMovementDetected, secondsAgo: 301)
            ],
            readiness: .foregroundOnly,
            hasStaleActiveDraft: true
        )

        XCTAssertEqual(snapshot.state, .configurationRequired(.foregroundOnly))
    }

    func testStaleActiveDraftPrecedesRetryableFailure() {
        let snapshot = evaluate(
            [outcome(.failedRetryable, secondsAgo: 600)],
            hasStaleActiveDraft: true
        )

        XCTAssertEqual(snapshot.state, .persistenceAtRisk(.staleActiveDraft))
    }

    func testUnresolvedRetryableOutcomeIsPersistenceRisk() {
        XCTAssertEqual(
            evaluate([outcome(.failedRetryable, secondsAgo: 60)]).state,
            .persistenceAtRisk(.failedRetryable)
        )
    }

    func testLaterSuccessfulOutcomeResolvesRetryableOutcome() {
        let success = outcome(.persisted, secondsAgo: 30)
        let snapshot = evaluate([
            outcome(.failedRetryable, secondsAgo: 60),
            success
        ])

        XCTAssertEqual(snapshot.state, .recentlyObserved(lastEvidenceAt: success.occurredAt))
    }

    func testRecoveredOutcomeDoesNotRefreshLiveCollectionHealth() {
        let recovered = outcome(.recovered, secondsAgo: 30)

        XCTAssertEqual(evaluate([recovered]).state, .awaitingFirstEvidence)
        XCTAssertEqual(evaluate([recovered]).summary.recoveredTripCount, 1)
    }

    func testRecoveredOutcomeKeepsRecoveryTimeAndOriginalEvidenceTimeSeparate() {
        let recoveredAt = now.addingTimeInterval(-60)
        let originalTripAt = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let recovered = CollectionHealthEvent.outcome(
            .recovered,
            at: recoveredAt,
            evidenceAt: originalTripAt,
            systemUptime: uptime - 60,
            bootAnchor: bootAnchor
        )

        let snapshot = evaluate([recovered])
        XCTAssertEqual(snapshot.state, .awaitingFirstEvidence)
        XCTAssertEqual(snapshot.summary.recoveredTripCount, 1)
        XCTAssertNil(snapshot.lastSuccessfulTripAt)
    }

    func testPersistenceFailureCannotBeClearedByLaterGpsSample() {
        XCTAssertEqual(
            evaluate([
                event(.acceptedSample, secondsAgo: 120),
                failure(.tripStoreWrite, secondsAgo: 60)
            ]).state,
            .persistenceAtRisk(.persistenceFailure)
        )

        let recoveredSample = event(.acceptedSample, secondsAgo: 30)
        XCTAssertEqual(
            evaluate([
                failure(.tripStoreWrite, secondsAgo: 60),
                recoveredSample
            ]).state,
            .persistenceAtRisk(.persistenceFailure)
        )
    }

    func testMovementWithoutSampleIsNotFailureBeforeFiveMinutes() {
        let movement = event(.motionMovementDetected, secondsAgo: 299)

        XCTAssertEqual(evaluate([movement]).state, .awaitingFirstEvidence)
    }

    func testMovementWithoutSampleBecomesProbableLossAtFiveMinutes() {
        let movement = event(.motionMovementDetected, secondsAgo: 300)

        XCTAssertEqual(
            evaluate([movement]).state,
            .probableDataLoss(movementDetectedAt: movement.occurredAt)
        )
    }

    func testRepeatedMovementHeartbeatsDoNotPostponeProbableLoss() {
        let firstMovement = event(.motionMovementDetected, secondsAgo: 600)
        let latestMovement = event(.motionMovementDetected, secondsAgo: 10)

        XCTAssertEqual(
            evaluate([firstMovement, latestMovement]).state,
            .probableDataLoss(movementDetectedAt: firstMovement.occurredAt)
        )
    }

    func testAcceptedSampleAfterMovementClearsProbableLoss() {
        let sample = event(.acceptedSample, secondsAgo: 60)
        let snapshot = evaluate([
            event(.motionMovementDetected, secondsAgo: 600),
            sample
        ])

        XCTAssertEqual(
            snapshot.state,
            .receivingFreshSamples(lastAcceptedSampleAt: sample.occurredAt)
        )
    }

    func testLocationBatchWithoutAcceptedSampleDoesNotClearProbableLoss() {
        let movement = event(.motionMovementDetected, secondsAgo: 600)
        let snapshot = evaluate([
            movement,
            event(.locationBatchReceived, secondsAgo: 60)
        ])

        XCTAssertEqual(
            snapshot.state,
            .probableDataLoss(movementDetectedAt: movement.occurredAt)
        )
    }

    func testClockDivergentSampleDoesNotClearMovementLoss() {
        let movement = event(.motionMovementDetected, secondsAgo: 600)
        let divergentSample = CollectionHealthEvent(
            occurredAt: now.addingTimeInterval(-60),
            systemUptime: uptime - 60,
            bootAnchor: bootAnchor + 3_600,
            kind: .acceptedSample
        )

        XCTAssertEqual(
            evaluate([movement, divergentSample]).state,
            .probableDataLoss(movementDetectedAt: movement.occurredAt)
        )
    }

    func testFreshSampleMustBeStrictlyYoungerThanTwentyFourHours() {
        let fresh = event(
            .acceptedSample,
            secondsAgo: CollectionHealthSnapshot.freshSampleInterval - 1
        )
        let boundary = event(
            .acceptedSample,
            secondsAgo: CollectionHealthSnapshot.freshSampleInterval
        )

        XCTAssertEqual(
            evaluate([fresh]).state,
            .receivingFreshSamples(lastAcceptedSampleAt: fresh.occurredAt)
        )
        XCTAssertEqual(
            evaluate([boundary]).state,
            .recentlyObserved(lastEvidenceAt: boundary.occurredAt)
        )
    }

    func testSuccessfulHistoricalOutcomeIsRecentForStrictlyLessThanSevenDays() {
        let recent = outcome(
            .persisted,
            secondsAgo: CollectionHealthSnapshot.recentEvidenceInterval - 1
        )

        XCTAssertEqual(
            evaluate([recent]).state,
            .recentlyObserved(lastEvidenceAt: recent.occurredAt)
        )
    }

    func testEvidenceAtSevenDaysIsNoLongerRecent() {
        let old = outcome(
            .persisted,
            secondsAgo: CollectionHealthSnapshot.recentEvidenceInterval
        )

        XCTAssertEqual(
            evaluate([old]).state,
            .noRecentEvidence(lastEvidenceAt: old.occurredAt)
        )
    }

    func testNoEvidenceAwaitsFirstProofAndRejectedTripDoesNotCountAsProof() {
        XCTAssertEqual(evaluate([]).state, .awaitingFirstEvidence)
        XCTAssertEqual(
            evaluate([outcome(.rejected, secondsAgo: 60)]).state,
            .awaitingFirstEvidence
        )
    }

    func testReadyForMoreThanTwentyFourHoursWithoutEvidenceIsVisible() {
        let ready = event(.trackingReady, secondsAgo: 24 * 60 * 60)

        XCTAssertEqual(
            evaluate([ready]).state,
            .noRecentEvidence(lastEvidenceAt: nil)
        )
    }

    func testJournalKeepsNonSensitiveObservationAnchorBeyondSevenDayDetailWindow() throws {
        let fixture = try JournalFixture()
        let journal = fixture.journal
        let started = event(.trackingReady, secondsAgo: 8 * 24 * 60 * 60)
        try journal.append(started, now: started.occurredAt)

        let events = try journal.load(now: now)

        XCTAssertEqual(events, [started])
        XCTAssertEqual(
            evaluate(events).state,
            .noRecentEvidence(lastEvidenceAt: nil)
        )
    }

    func testFutureDatedSampleIsNeverFresh() {
        let future = event(.acceptedSample, secondsAgo: -60)

        XCTAssertEqual(evaluate([future]).state, .awaitingFirstEvidence)
    }

    func testClockDivergenceDemotesSampleFromFreshEvidence() {
        let sample = CollectionHealthEvent(
            occurredAt: now.addingTimeInterval(-60),
            systemUptime: uptime - 60,
            bootAnchor: bootAnchor + 3_600,
            kind: .acceptedSample
        )

        XCTAssertEqual(
            evaluate([sample]).state,
            .clockUntrusted(lastEvidenceAt: sample.occurredAt)
        )
    }

    func testPreviousBootEvidenceIsHistoricalButNeverFresh() {
        let sample = CollectionHealthEvent(
            occurredAt: now.addingTimeInterval(-60),
            systemUptime: 10,
            bootAnchor: bootAnchor - 3_600,
            kind: .acceptedSample
        )

        XCTAssertEqual(
            evaluate([sample]).state,
            .clockUntrusted(lastEvidenceAt: sample.occurredAt)
        )
    }

    func testSummaryCountsEachSevenDayOutcomeWithoutTreatingRejectAsSuccess() {
        let snapshot = evaluate([
            event(.passiveWakeupReceived, secondsAgo: 90),
            event(.locationBatchReceived, secondsAgo: 80),
            event(.acceptedSample, secondsAgo: 70),
            event(.tripStarted, secondsAgo: 60),
            outcome(.persisted, secondsAgo: 50),
            outcome(.rejected, secondsAgo: 40),
            outcome(.recovered, secondsAgo: 30),
            outcome(.failedRetryable, secondsAgo: 20),
            failure(.activeTripJournalWrite, secondsAgo: 10)
        ])

        XCTAssertEqual(snapshot.summary.passiveWakeupCount, 1)
        XCTAssertEqual(snapshot.summary.locationBatchCount, 1)
        XCTAssertEqual(snapshot.summary.acceptedSampleHeartbeatCount, 1)
        XCTAssertEqual(snapshot.summary.tripStartedCount, 1)
        XCTAssertEqual(snapshot.summary.persistedTripCount, 1)
        XCTAssertEqual(snapshot.summary.rejectedTripCount, 1)
        XCTAssertEqual(snapshot.summary.recoveredTripCount, 1)
        XCTAssertEqual(snapshot.summary.failedRetryableTripCount, 1)
        XCTAssertEqual(snapshot.summary.persistenceFailureCount, 1)
    }

    private var bootAnchor: TimeInterval {
        now.timeIntervalSince1970 - uptime
    }

    private var plainKinds: [CollectionHealthEventKind] {
        [
            .trackingReady,
            .trackingNotReady,
            .passiveWakeupReceived,
            .motionMovementDetected,
            .locationBatchReceived,
            .acceptedSample,
            .tripStarted
        ]
    }

    private func event(
        _ kind: CollectionHealthEventKind,
        secondsAgo: TimeInterval,
        tripOutcome: CollectionHealthTripOutcome? = nil
    ) -> CollectionHealthEvent {
        CollectionHealthEvent(
            occurredAt: now.addingTimeInterval(-secondsAgo),
            systemUptime: uptime - secondsAgo,
            bootAnchor: bootAnchor,
            kind: kind,
            tripOutcome: tripOutcome
        )
    }

    private func outcome(
        _ value: CollectionHealthTripOutcome,
        secondsAgo: TimeInterval
    ) -> CollectionHealthEvent {
        CollectionHealthEvent.outcome(
            value,
            at: now.addingTimeInterval(-secondsAgo),
            systemUptime: uptime - secondsAgo,
            bootAnchor: bootAnchor
        )
    }

    private func failure(
        _ value: CollectionHealthPersistenceFailure,
        secondsAgo: TimeInterval
    ) -> CollectionHealthEvent {
        CollectionHealthEvent.persistenceFailure(
            value,
            at: now.addingTimeInterval(-secondsAgo),
            systemUptime: uptime - secondsAgo,
            bootAnchor: bootAnchor
        )
    }

    private func evaluate(
        _ events: [CollectionHealthEvent],
        readiness: LocationCollectionReadiness = .ready,
        storageAvailable: Bool = true,
        hasStaleActiveDraft: Bool = false
    ) -> CollectionHealthSnapshot {
        CollectionHealthSnapshot.evaluate(
            events: events,
            collectionReadiness: readiness,
            storageAvailable: storageAvailable,
            hasStaleActiveDraft: hasStaleActiveDraft,
            now: now,
            systemUptime: uptime,
            bootAnchor: bootAnchor
        )
    }

    private func eventOrder(
        _ lhs: CollectionHealthEvent,
        _ rhs: CollectionHealthEvent
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt < rhs.occurredAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private final class JournalFixture {
    let directoryURL: URL
    let fileURL: URL
    let journal: CollectionHealthJournal

    init(
        maximumEventCount: Int = CollectionHealthJournal.defaultMaximumEventCount,
        maximumFileBytes: Int = CollectionHealthJournal.defaultMaximumFileBytes
    ) throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "viim-collection-health-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        fileURL = directoryURL.appendingPathComponent("health.json")
        journal = CollectionHealthJournal(
            fileURL: fileURL,
            maximumEventCount: maximumEventCount,
            maximumFileBytes: maximumFileBytes
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func quarantinedFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("health.corrupt-") }
    }
}
