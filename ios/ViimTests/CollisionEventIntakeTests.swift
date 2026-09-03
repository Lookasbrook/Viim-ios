import XCTest
@testable import Viim

final class CollisionEventIntakeTests: XCTestCase {
    func testIdentityIsStableAcrossReplayAndSeparatedBySource() {
        let eventDate = Date(timeIntervalSince1970: 2_000_000_000.1231)
        let first = evidence(eventDate: eventDate, receivedAt: eventDate)
        let replay = evidence(
            eventDate: eventDate.addingTimeInterval(0.0002),
            receivedAt: eventDate.addingTimeInterval(30)
        )
        let simulated = CollisionEventEvidence(
            source: .simulatedTest,
            sourceEventDate: eventDate,
            receivedAt: eventDate
        )

        XCTAssertEqual(first.id, replay.id)
        XCTAssertTrue(first.representsSameSourceEvent(as: replay))
        XCTAssertNotEqual(first.id, simulated.id)
    }

    func testJournalDeduplicatesReplayAcrossInstancesWithoutExtendingDeadline() throws {
        let fileURL = try temporaryFileURL()
        let eventDate = Date(timeIntervalSince1970: 2_000_000_000)
        let firstEvidence = evidence(eventDate: eventDate, receivedAt: eventDate)
        let first = try CollisionEventIntakeRecord(evidence: firstEvidence)
        let journal = CollisionEventJournal(fileURL: fileURL)
        _ = try journal.ingest(first, now: eventDate)
        _ = try journal.beginUserDecision(id: first.id, at: eventDate)

        let replayEvidence = evidence(
            eventDate: eventDate,
            receivedAt: eventDate.addingTimeInterval(30)
        )
        let replay = try CollisionEventIntakeRecord(evidence: replayEvidence)
        let relaunchedJournal = CollisionEventJournal(fileURL: fileURL)
        let stored = try relaunchedJournal.ingest(replay, now: replayEvidence.receivedAt)

        XCTAssertEqual(try relaunchedJournal.load().count, 1)
        XCTAssertEqual(stored.phase, .awaitingUserDecision)
        XCTAssertEqual(stored.decisionDeadline, eventDate.addingTimeInterval(60))
        XCTAssertEqual(stored.evidence.receivedAt, eventDate)
    }

    func testConflictingReplayFailsClosedAndKeepsOriginalBytes() throws {
        let fileURL = try temporaryFileURL()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let original = try CollisionEventIntakeRecord(evidence: evidence(eventDate: now, receivedAt: now))
        let journal = CollisionEventJournal(fileURL: fileURL)
        _ = try journal.ingest(original, now: now)
        let originalData = try Data(contentsOf: fileURL)
        let conflict = try CollisionEventIntakeRecord(
            evidence: evidence(
                eventDate: now,
                receivedAt: now.addingTimeInterval(1),
                latitude: 45,
                longitude: -73
            )
        )

        XCTAssertThrowsError(try journal.ingest(conflict, now: now.addingTimeInterval(1))) {
            XCTAssertEqual($0 as? CollisionEventJournal.IntegrityError, .conflictingIdentifier)
        }
        XCTAssertFalse(journal.storageAvailable)
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
        XCTAssertEqual(try CollisionEventJournal(fileURL: fileURL).load(), [original])
    }

    func testEvidenceAcceptsNoPositionAndRejectsPartialOrInvalidCoordinates() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertTrue(evidence(eventDate: now, receivedAt: now).isStructurallyValid)
        XCTAssertFalse(evidence(eventDate: now, receivedAt: now, latitude: 45).isStructurallyValid)
        XCTAssertFalse(
            evidence(eventDate: now, receivedAt: now, latitude: .nan, longitude: -73)
                .isStructurallyValid
        )
        XCTAssertFalse(
            evidence(eventDate: now, receivedAt: now, latitude: 91, longitude: -73)
                .isStructurallyValid
        )
    }

    func testCoordinatorPersistsBeforePublishingPendingState() throws {
        let fileURL = try temporaryFileURL()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let journal = CollisionEventJournal(fileURL: fileURL)
        let coordinator = CollisionEventCoordinator(journal: journal, clock: { now })
        var publishedState: CollisionEventCoordinatorState?
        coordinator.onStateChange = { state in
            let persisted = try? CollisionEventJournal(fileURL: fileURL).load()
            XCTAssertEqual(persisted?.first?.phase, .awaitingUserDecision)
            publishedState = state
        }

        coordinator.receive(evidence(eventDate: now, receivedAt: now))

        guard case .pending(let record) = publishedState else {
            return XCTFail("Expected a persisted pending decision")
        }
        XCTAssertEqual(record.decisionDeadline, now.addingTimeInterval(60))
    }

    func testStorageFailureNeverPublishesPendingState() throws {
        let directory = try temporaryDirectory()
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blockingFile, options: .atomic)
        let journal = CollisionEventJournal(
            fileURL: blockingFile.appendingPathComponent("inbox.json")
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let coordinator = CollisionEventCoordinator(journal: journal, clock: { now })

        coordinator.receive(evidence(eventDate: now, receivedAt: now))

        XCTAssertEqual(coordinator.state, .storageUnavailable)
        XCTAssertFalse(journal.storageAvailable)
        XCTAssertEqual(try Data(contentsOf: blockingFile), Data("block".utf8))
    }

    func testHistoricalAndFarFutureEventsNeverOpenANewDecisionWindow() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oldJournal = CollisionEventJournal(fileURL: try temporaryFileURL())
        let oldCoordinator = CollisionEventCoordinator(journal: oldJournal, clock: { now })
        oldCoordinator.receive(
            evidence(eventDate: now.addingTimeInterval(-301), receivedAt: now)
        )
        guard case .terminal(let expired) = oldCoordinator.state else {
            return XCTFail("Historical event must be terminal")
        }
        XCTAssertEqual(expired.phase, .expiredNoDecision)
        XCTAssertEqual(expired.decisionDeadline, now)

        let futureJournal = CollisionEventJournal(fileURL: try temporaryFileURL())
        let futureCoordinator = CollisionEventCoordinator(journal: futureJournal, clock: { now })
        futureCoordinator.receive(
            evidence(eventDate: now.addingTimeInterval(301), receivedAt: now)
        )
        XCTAssertEqual(futureCoordinator.state, .invalidEvent)
        XCTAssertTrue(try futureJournal.load().isEmpty)
    }

    func testRelaunchRestoresDeadlineAndExpiresWithoutExtendingIt() throws {
        let fileURL = try temporaryFileURL()
        let startedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let first = CollisionEventCoordinator(
            journal: CollisionEventJournal(fileURL: fileURL),
            clock: { startedAt }
        )
        first.receive(evidence(eventDate: startedAt, receivedAt: startedAt))

        let relaunched = CollisionEventCoordinator(
            journal: CollisionEventJournal(fileURL: fileURL),
            clock: { startedAt.addingTimeInterval(30) }
        )
        relaunched.restore()
        guard case .pending(let pending) = relaunched.state else {
            return XCTFail("Expected restored pending event")
        }
        XCTAssertEqual(pending.decisionDeadline, startedAt.addingTimeInterval(60))

        let afterDeadline = CollisionEventCoordinator(
            journal: CollisionEventJournal(fileURL: fileURL),
            clock: { startedAt.addingTimeInterval(61) }
        )
        afterDeadline.restore()
        guard case .terminal(let expired) = afterDeadline.state else {
            return XCTFail("Expected terminal expiration")
        }
        XCTAssertEqual(expired.phase, .expiredNoDecision)
        XCTAssertEqual(expired.decisionDeadline, startedAt.addingTimeInterval(60))
    }

    func testCancellationIsIdempotentAndHelpRequestIsTerminal() throws {
        let fileURL = try temporaryFileURL()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let record = try CollisionEventIntakeRecord(evidence: evidence(eventDate: now, receivedAt: now))
        let journal = CollisionEventJournal(fileURL: fileURL)
        _ = try journal.ingest(record, now: now)
        _ = try journal.beginUserDecision(id: record.id, at: now)
        let cancelled = try journal.cancel(id: record.id, at: now.addingTimeInterval(10))
        let repeated = try journal.cancel(id: record.id, at: now.addingTimeInterval(20))

        XCTAssertEqual(cancelled, repeated)
        XCTAssertThrowsError(try journal.requestHelp(id: record.id, at: now.addingTimeInterval(20))) {
            XCTAssertEqual($0 as? CollisionEventIntakeTransitionError, .invalidTransition)
        }

        let helpFileURL = try temporaryFileURL()
        let helpRecord = try CollisionEventIntakeRecord(
            evidence: evidence(eventDate: now.addingTimeInterval(100), receivedAt: now.addingTimeInterval(100))
        )
        let helpJournal = CollisionEventJournal(fileURL: helpFileURL)
        _ = try helpJournal.ingest(helpRecord, now: helpRecord.evidence.receivedAt)
        _ = try helpJournal.beginUserDecision(id: helpRecord.id, at: helpRecord.evidence.receivedAt)
        let requested = try helpJournal.requestHelp(
            id: helpRecord.id,
            at: helpRecord.evidence.receivedAt.addingTimeInterval(10)
        )
        XCTAssertEqual(requested.phase, .helpRequested)
        XCTAssertTrue(requested.phase.isTerminal)
    }

    func testLateDecisionExpiresInsteadOfReportingStorageFailure() throws {
        let fileURL = try temporaryFileURL()
        let startedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let coordinator = CollisionEventCoordinator(
            journal: CollisionEventJournal(fileURL: fileURL),
            clock: { startedAt }
        )
        coordinator.receive(evidence(eventDate: startedAt, receivedAt: startedAt))

        coordinator.requestHelpForCurrent(at: startedAt.addingTimeInterval(60))

        guard case .terminal(let expired) = coordinator.state else {
            return XCTFail("A decision at the deadline must expire locally")
        }
        XCTAssertEqual(expired.phase, .expiredNoDecision)
        XCTAssertEqual(expired.updatedAt, startedAt.addingTimeInterval(60))
        XCTAssertTrue(CollisionEventJournal(fileURL: fileURL).storageAvailable)
    }

    func testCorruptOrOversizedJournalIsNeverOverwritten() throws {
        let malformedURL = try temporaryFileURL()
        let malformed = Data("{not-json".utf8)
        try malformed.write(to: malformedURL, options: .atomic)
        let malformedJournal = CollisionEventJournal(fileURL: malformedURL)
        XCTAssertThrowsError(try malformedJournal.load()) {
            XCTAssertEqual($0 as? CollisionEventJournal.IntegrityError, .malformed)
        }
        XCTAssertEqual(try Data(contentsOf: malformedURL), malformed)

        let oversizedURL = try temporaryFileURL()
        let oversized = Data(repeating: 0x41, count: 17)
        try oversized.write(to: oversizedURL, options: .atomic)
        let oversizedJournal = CollisionEventJournal(
            fileURL: oversizedURL,
            maximumFileBytes: 16
        )
        XCTAssertThrowsError(try oversizedJournal.load()) {
            XCTAssertEqual($0 as? CollisionEventJournal.IntegrityError, .oversized)
        }
        XCTAssertEqual(try Data(contentsOf: oversizedURL), oversized)
    }

    func testBoundedJournalNeverEvictsPendingRecord() throws {
        let fileURL = try temporaryFileURL()
        let firstDate = Date(timeIntervalSince1970: 2_000_000_000)
        let first = try CollisionEventIntakeRecord(
            evidence: evidence(eventDate: firstDate, receivedAt: firstDate)
        )
        let secondDate = firstDate.addingTimeInterval(10)
        let second = try CollisionEventIntakeRecord(
            evidence: evidence(eventDate: secondDate, receivedAt: secondDate)
        )
        let journal = CollisionEventJournal(fileURL: fileURL, maximumRecordCount: 1)
        _ = try journal.ingest(first, now: firstDate)

        XCTAssertThrowsError(try journal.ingest(second, now: secondDate)) {
            XCTAssertEqual($0 as? CollisionEventJournal.IntegrityError, .tooManyRecords)
        }
        XCTAssertEqual(try CollisionEventJournal(fileURL: fileURL).load(), [first])
    }

    func testInboxCannotChangePublicCollisionReadiness() {
        let snapshot = ProtectionReadinessSnapshot.evaluate(
            locationReadiness: .ready,
            isLocationMonitoring: true,
            isPassiveWakeupMonitoring: true,
            emergencyContacts: [],
            isOnline: true
        )
        XCTAssertEqual(snapshot.automaticCollision, .unavailable)
        XCTAssertTrue(
            CollisionEventJournal.protectedWriteOptions.contains(.atomic)
        )
        XCTAssertTrue(
            CollisionEventJournal.protectedWriteOptions.contains(
                .completeFileProtectionUntilFirstUserAuthentication
            )
        )
    }

    private func evidence(
        eventDate: Date,
        receivedAt: Date,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> CollisionEventEvidence {
        CollisionEventEvidence(
            source: .safetyKit,
            sourceEventDate: eventDate,
            receivedAt: receivedAt,
            latitude: latitude,
            longitude: longitude
        )
    }

    private func temporaryFileURL() throws -> URL {
        try temporaryDirectory().appendingPathComponent("collision-inbox.json")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CollisionEventIntakeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
