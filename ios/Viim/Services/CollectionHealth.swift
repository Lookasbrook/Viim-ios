import Foundation

extension Notification.Name {
    static let viimCollectionHealthDidChange = Notification.Name(
        "com.yamstack.viim.collection-health-did-change"
    )
}

enum CollectionHealthEventKind: String, Codable, CaseIterable, Equatable {
    case trackingReady
    case trackingNotReady
    case passiveWakeupReceived
    case motionMovementDetected
    case locationBatchReceived
    case acceptedSample
    case tripStarted
    case tripOutcome
    case persistenceFailure
}

enum CollectionHealthTripOutcome: String, Codable, Equatable {
    case persisted
    case rejected
    case recovered
    case failedRetryable
}

/// Codes fermes uniquement. Un message d'erreur libre risquerait de faire
/// entrer une coordonnee ou une autre donnee utilisateur dans le journal.
enum CollectionHealthPersistenceFailure: String, Codable, Equatable {
    case healthJournalRead
    case healthJournalWrite
    case activeTripJournalRead
    case activeTripJournalWrite
    case tripStoreRead
    case tripStoreWrite
    case unknown
}

/// Evenement minimal de sante. Il ne contient ni position, ni vitesse, ni
/// identifiant de trajet, ni contact.
struct CollectionHealthEvent: Codable, Equatable, Identifiable {
    static let schemaVersion = 1

    let id: UUID
    let occurredAt: Date
    let evidenceAt: Date?
    let systemUptime: TimeInterval
    let bootAnchor: TimeInterval
    let kind: CollectionHealthEventKind
    let tripOutcome: CollectionHealthTripOutcome?
    let persistenceFailure: CollectionHealthPersistenceFailure?
    let version: Int

    init(
        id: UUID = UUID(),
        occurredAt: Date,
        evidenceAt: Date? = nil,
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        bootAnchor: TimeInterval? = nil,
        kind: CollectionHealthEventKind,
        tripOutcome: CollectionHealthTripOutcome? = nil,
        persistenceFailure: CollectionHealthPersistenceFailure? = nil,
        version: Int = CollectionHealthEvent.schemaVersion
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.evidenceAt = evidenceAt
        self.systemUptime = systemUptime
        self.bootAnchor = bootAnchor ?? occurredAt.timeIntervalSince1970 - systemUptime
        self.kind = kind
        self.tripOutcome = tripOutcome
        self.persistenceFailure = persistenceFailure
        self.version = version
    }

    static func outcome(
        _ outcome: CollectionHealthTripOutcome,
        at date: Date,
        evidenceAt: Date? = nil,
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        bootAnchor: TimeInterval? = nil,
        id: UUID = UUID()
    ) -> Self {
        Self(
            id: id,
            occurredAt: date,
            evidenceAt: evidenceAt,
            systemUptime: systemUptime,
            bootAnchor: bootAnchor,
            kind: .tripOutcome,
            tripOutcome: outcome
        )
    }

    static func persistenceFailure(
        _ failure: CollectionHealthPersistenceFailure,
        at date: Date,
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        bootAnchor: TimeInterval? = nil,
        id: UUID = UUID()
    ) -> Self {
        Self(
            id: id,
            occurredAt: date,
            systemUptime: systemUptime,
            bootAnchor: bootAnchor,
            kind: .persistenceFailure,
            persistenceFailure: failure
        )
    }

    var isStructurallyValid: Bool {
        guard version == Self.schemaVersion,
              occurredAt.timeIntervalSinceReferenceDate.isFinite,
              evidenceAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
              systemUptime.isFinite,
              systemUptime >= 0,
              bootAnchor.isFinite else {
            return false
        }

        switch kind {
        case .tripOutcome:
            return tripOutcome != nil && persistenceFailure == nil
        case .persistenceFailure:
            return persistenceFailure != nil && tripOutcome == nil
        default:
            return tripOutcome == nil && persistenceFailure == nil
        }
    }
}

protocol CollectionHealthJournaling {
    var storageAvailable: Bool { get }
    func load(now: Date) throws -> [CollectionHealthEvent]
    func append(_ event: CollectionHealthEvent, now: Date) throws
}

extension CollectionHealthJournaling {
    var storageAvailable: Bool { true }

    func load() throws -> [CollectionHealthEvent] {
        try load(now: Date())
    }

    func append(_ event: CollectionHealthEvent) throws {
        try append(event, now: Date())
    }
}

final class CollectionHealthJournal: CollectionHealthJournaling {
    static let retentionDuration: TimeInterval = 7 * 24 * 60 * 60
    static let heartbeatCoalescingInterval: TimeInterval = 5 * 60
    static let defaultMaximumEventCount = 512
    static let defaultMaximumFileBytes = 256_000
    static let protectedWriteOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUntilFirstUserAuthentication
    ]

    enum IntegrityError: Error, Equatable {
        case oversized
        case malformed
        case invalidEvent
        case duplicateIdentifier
        case tooManyEvents
    }

    private let fileURL: URL
    private let maximumEventCount: Int
    private let maximumFileBytes: Int
    private static let processLock = NSLock()
    private var storageIsAvailable = true

    var storageAvailable: Bool {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        return storageIsAvailable
    }

    init(
        fileURL: URL = CollectionHealthJournal.defaultFileURL(),
        maximumEventCount: Int = CollectionHealthJournal.defaultMaximumEventCount,
        maximumFileBytes: Int = CollectionHealthJournal.defaultMaximumFileBytes
    ) {
        self.fileURL = fileURL
        self.maximumEventCount = max(1, maximumEventCount)
        self.maximumFileBytes = max(1, maximumFileBytes)
    }

    func load(now: Date) throws -> [CollectionHealthEvent] {
        Self.processLock.lock()
        do {
            let stored = try loadUnlocked()
            let retained = retainedEvents(from: stored, now: now)
            if retained != stored {
                try writeUnlocked(retained)
                storageIsAvailable = true
            }
            Self.processLock.unlock()
            return retained
        } catch let error as IntegrityError {
            do {
                try quarantineCorruptFileUnlocked()
            } catch {
                storageIsAvailable = false
                Self.processLock.unlock()
                throw error
            }
            storageIsAvailable = false
            Self.processLock.unlock()
            throw error
        } catch {
            storageIsAvailable = false
            Self.processLock.unlock()
            throw error
        }
    }

    func append(_ event: CollectionHealthEvent, now: Date) throws {
        guard event.isStructurallyValid else {
            throw IntegrityError.invalidEvent
        }

        Self.processLock.lock()
        do {
            var events: [CollectionHealthEvent]
            do {
                events = try loadUnlocked()
            } catch let error as IntegrityError {
                try quarantineCorruptFileUnlocked()
                events = [
                    .persistenceFailure(
                        .healthJournalRead,
                        at: now
                    )
                ]
                ViimDiagnostics.log(
                    "collection.health.journal.recovered reason=\(String(describing: error)) quarantine=true"
                )
            }

            events = retainedEvents(from: events, now: now)
            guard !events.contains(where: { $0.id == event.id }) else {
                Self.processLock.unlock()
                return
            }
            guard !shouldCoalesce(event, into: events) else {
                Self.processLock.unlock()
                return
            }

            events.append(event)
            events = retainedEvents(from: events, now: now)
            try writeUnlocked(events)
            storageIsAvailable = true
            Self.processLock.unlock()
            NotificationCenter.default.post(name: .viimCollectionHealthDidChange, object: nil)
        } catch {
            storageIsAvailable = false
            Self.processLock.unlock()
            NotificationCenter.default.post(name: .viimCollectionHealthDidChange, object: nil)
            throw error
        }
    }

    private func loadUnlocked() throws -> [CollectionHealthEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else {
            throw IntegrityError.oversized
        }

        let events: [CollectionHealthEvent]
        do {
            events = try JSONDecoder().decode([CollectionHealthEvent].self, from: data)
        } catch {
            throw IntegrityError.malformed
        }

        guard events.count <= maximumEventCount else {
            throw IntegrityError.tooManyEvents
        }
        guard events.allSatisfy(\.isStructurallyValid) else {
            throw IntegrityError.invalidEvent
        }
        guard Set(events.map(\.id)).count == events.count else {
            throw IntegrityError.duplicateIdentifier
        }
        return events.sorted(by: Self.eventsAreOrdered)
    }

    private func retainedEvents(
        from events: [CollectionHealthEvent],
        now: Date
    ) -> [CollectionHealthEvent] {
        let cutoff = now.addingTimeInterval(-Self.retentionDuration)
        let recent = events
            .filter { $0.occurredAt >= cutoff }
            .sorted(by: Self.eventsAreOrdered)
        // Le detail reste borne a sept jours. Deux ancres non sensibles sont
        // conservees au-dela de la fenetre afin qu'un nouveau lancement ne
        // transforme pas huit jours sans donnees en "premiere observation".
        let older = events.filter { $0.occurredAt < cutoff }
        let observationAnchor = older.first(where: { $0.kind == .trackingReady })
        let evidenceAnchor = older.last(where: {
            $0.kind == .acceptedSample ||
                ($0.kind == .tripOutcome && $0.tripOutcome == .persisted)
        })
        let anchors = [observationAnchor, evidenceAnchor]
            .compactMap { $0 }
            .reduce(into: [CollectionHealthEvent]()) { result, event in
                guard !result.contains(where: { $0.id == event.id }) else { return }
                result.append(event)
            }
        let recentLimit = max(0, maximumEventCount - anchors.count)
        return (anchors + recent.suffix(recentLimit))
            .sorted(by: Self.eventsAreOrdered)
    }

    private func shouldCoalesce(
        _ event: CollectionHealthEvent,
        into events: [CollectionHealthEvent]
    ) -> Bool {
        guard event.kind == .locationBatchReceived ||
                event.kind == .acceptedSample ||
                event.kind == .motionMovementDetected,
              let latest = events.last(where: { $0.kind == event.kind }) else {
            return false
        }
        let elapsed = event.occurredAt.timeIntervalSince(latest.occurredAt)
        return elapsed >= 0 && elapsed < Self.heartbeatCoalescingInterval
    }

    private func writeUnlocked(_ events: [CollectionHealthEvent]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(events)
        guard data.count <= maximumFileBytes else {
            throw IntegrityError.oversized
        }
        try data.write(to: fileURL, options: Self.protectedWriteOptions)
    }

    private func quarantineCorruptFileUnlocked() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let quarantineURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            "\(fileURL.deletingPathExtension().lastPathComponent).corrupt-\(UUID().uuidString).json"
        )
        try fileManager.moveItem(at: fileURL, to: quarantineURL)
    }

    private static func eventsAreOrdered(
        _ lhs: CollectionHealthEvent,
        _ rhs: CollectionHealthEvent
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt < rhs.occurredAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func defaultFileURL() -> URL {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            preconditionFailure("Application Support indisponible pour le journal de sante")
        }
        return directory.appendingPathComponent("ViimCollectionHealth.json")
    }
}

enum CollectionHealthPersistenceRisk: String, Equatable {
    case failedRetryable
    case staleActiveDraft
    case persistenceFailure
}

enum CollectionHealthState: Equatable {
    case unavailable
    case configurationRequired(LocationCollectionReadiness)
    case persistenceAtRisk(CollectionHealthPersistenceRisk)
    case probableDataLoss(movementDetectedAt: Date)
    case receivingFreshSamples(lastAcceptedSampleAt: Date)
    case recentlyObserved(lastEvidenceAt: Date)
    case clockUntrusted(lastEvidenceAt: Date?)
    case noRecentEvidence(lastEvidenceAt: Date?)
    case awaitingFirstEvidence
}

struct CollectionHealthWindowSummary: Equatable {
    let passiveWakeupCount: Int
    let locationBatchCount: Int
    let acceptedSampleHeartbeatCount: Int
    let tripStartedCount: Int
    let persistedTripCount: Int
    let rejectedTripCount: Int
    let recoveredTripCount: Int
    let failedRetryableTripCount: Int
    let persistenceFailureCount: Int
}

struct CollectionHealthSnapshot: Equatable {
    static let movementSampleDeadline: TimeInterval = 5 * 60
    static let freshSampleInterval: TimeInterval = 24 * 60 * 60
    static let recentEvidenceInterval: TimeInterval = 7 * 24 * 60 * 60
    static let clockDivergenceTolerance: TimeInterval = 5

    let state: CollectionHealthState
    let lastPassiveWakeupAt: Date?
    let lastMovementDetectedAt: Date?
    let lastLocationBatchAt: Date?
    let lastAcceptedSampleAt: Date?
    let lastSuccessfulTripAt: Date?
    let summary: CollectionHealthWindowSummary

    static let unavailable = Self(
        state: .unavailable,
        lastPassiveWakeupAt: nil,
        lastMovementDetectedAt: nil,
        lastLocationBatchAt: nil,
        lastAcceptedSampleAt: nil,
        lastSuccessfulTripAt: nil,
        summary: CollectionHealthWindowSummary(
            passiveWakeupCount: 0,
            locationBatchCount: 0,
            acceptedSampleHeartbeatCount: 0,
            tripStartedCount: 0,
            persistedTripCount: 0,
            rejectedTripCount: 0,
            recoveredTripCount: 0,
            failedRetryableTripCount: 0,
            persistenceFailureCount: 0
        )
    )

    static func evaluate(
        events: [CollectionHealthEvent],
        collectionReadiness: LocationCollectionReadiness,
        storageAvailable: Bool,
        hasStaleActiveDraft: Bool,
        now: Date,
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        bootAnchor: TimeInterval? = nil
    ) -> Self {
        let currentBootAnchor = bootAnchor ?? now.timeIntervalSince1970 - systemUptime
        let windowStart = now.addingTimeInterval(-recentEvidenceInterval)
        let retainedEvents = events
            .filter {
                $0.isStructurallyValid &&
                    $0.occurredAt >= windowStart &&
                    $0.occurredAt <= now
            }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt < $1.occurredAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }

        let lastPassiveWakeupAt = latestDate(for: .passiveWakeupReceived, in: retainedEvents)
        let lastMovementDetectedAt = latestDate(for: .motionMovementDetected, in: retainedEvents)
        let lastLocationBatchAt = latestDate(for: .locationBatchReceived, in: retainedEvents)
        let lastAcceptedSampleAt = latestDate(for: .acceptedSample, in: retainedEvents)
        let successfulTripEvents = retainedEvents.filter {
            $0.kind == .tripOutcome &&
                $0.tripOutcome == .persisted
        }
        let lastSuccessfulTripAt = successfulTripEvents.last.map {
            $0.evidenceAt ?? $0.occurredAt
        }
        let summary = summarize(retainedEvents)
        let observingSince = events
            .filter { $0.isStructurallyValid && $0.kind == .trackingReady && $0.occurredAt <= now }
            .map(\.occurredAt)
            .min()

        let state: CollectionHealthState
        if !storageAvailable {
            state = .unavailable
        } else if collectionReadiness != .ready {
            state = .configurationRequired(collectionReadiness)
        } else if hasStaleActiveDraft {
            state = .persistenceAtRisk(.staleActiveDraft)
        } else if hasUnresolvedRetryableFailure(in: retainedEvents) {
            state = .persistenceAtRisk(.failedRetryable)
        } else if hasUnresolvedPersistenceFailure(in: retainedEvents) {
            state = .persistenceAtRisk(.persistenceFailure)
        } else if let movementEvent = earliestUnansweredMovement(
            in: retainedEvents,
            now: now,
            systemUptime: systemUptime,
            bootAnchor: currentBootAnchor
        ) {
            state = .probableDataLoss(movementDetectedAt: movementEvent.occurredAt)
        } else if let sampleEvent = retainedEvents.last(where: { $0.kind == .acceptedSample }),
                  let sampleAge = reliableAge(
                      of: sampleEvent,
                      now: now,
                      systemUptime: systemUptime,
                      bootAnchor: currentBootAnchor
                  ),
                  sampleAge < freshSampleInterval {
            let sampleAt = sampleEvent.occurredAt
            state = .receivingFreshSamples(lastAcceptedSampleAt: sampleAt)
        } else if let evidenceEvent = latestLiveEvidenceEvent(in: retainedEvents),
                  reliableAge(
                    of: evidenceEvent,
                    now: now,
                    systemUptime: systemUptime,
                    bootAnchor: currentBootAnchor
                  ) == nil {
            state = .clockUntrusted(lastEvidenceAt: evidenceEvent.occurredAt)
        } else if let evidenceAt = [lastAcceptedSampleAt, lastSuccessfulTripAt]
            .compactMap({ $0 })
            .max(),
                  now.timeIntervalSince(evidenceAt) < recentEvidenceInterval {
            state = .recentlyObserved(lastEvidenceAt: evidenceAt)
        } else if let historicalEvidenceAt = latestHistoricalEvidenceDate(
            in: events,
            now: now
        ) {
            state = .noRecentEvidence(lastEvidenceAt: historicalEvidenceAt)
        } else if let observingSince,
                  now.timeIntervalSince(observingSince) >= freshSampleInterval {
            state = .noRecentEvidence(lastEvidenceAt: nil)
        } else {
            state = .awaitingFirstEvidence
        }

        return Self(
            state: state,
            lastPassiveWakeupAt: lastPassiveWakeupAt,
            lastMovementDetectedAt: lastMovementDetectedAt,
            lastLocationBatchAt: lastLocationBatchAt,
            lastAcceptedSampleAt: lastAcceptedSampleAt,
            lastSuccessfulTripAt: lastSuccessfulTripAt,
            summary: summary
        )
    }

    private static func latestDate(
        for kind: CollectionHealthEventKind,
        in events: [CollectionHealthEvent]
    ) -> Date? {
        events.last(where: { $0.kind == kind })?.occurredAt
    }

    private static func latestHistoricalEvidenceDate(
        in events: [CollectionHealthEvent],
        now: Date
    ) -> Date? {
        events
            .filter { event in
                event.kind == .acceptedSample ||
                    (event.kind == .tripOutcome &&
                        event.tripOutcome == .persisted)
            }
            .map { $0.evidenceAt ?? $0.occurredAt }
            .filter { $0 <= now }
            .max()
    }

    private static func latestLiveEvidenceEvent(
        in events: [CollectionHealthEvent]
    ) -> CollectionHealthEvent? {
        events.last {
            $0.kind == .acceptedSample ||
                ($0.kind == .tripOutcome && $0.tripOutcome == .persisted)
        }
    }

    /// Une preuve fraiche doit etre rattachee au boot courant. L'age retenu est
    /// le plus pessimiste entre l'horloge murale et l'uptime. Toute date future
    /// ou divergence entre les deux horloges invalide la fraicheur.
    private static func reliableAge(
        of event: CollectionHealthEvent,
        now: Date,
        systemUptime: TimeInterval,
        bootAnchor: TimeInterval
    ) -> TimeInterval? {
        let wallAge = now.timeIntervalSince(event.occurredAt)
        let uptimeAge = systemUptime - event.systemUptime
        guard wallAge >= 0,
              uptimeAge >= 0,
              abs(event.bootAnchor - bootAnchor) <= clockDivergenceTolerance,
              abs(wallAge - uptimeAge) <= clockDivergenceTolerance else {
            return nil
        }
        return max(wallAge, uptimeAge)
    }

    private static func hasReliableAcceptedSample(
        after movement: CollectionHealthEvent,
        in events: [CollectionHealthEvent],
        now: Date,
        systemUptime: TimeInterval,
        bootAnchor: TimeInterval
    ) -> Bool {
        events.contains { event in
            event.kind == .acceptedSample &&
                event.systemUptime >= movement.systemUptime &&
                reliableAge(
                    of: event,
                    now: now,
                    systemUptime: systemUptime,
                    bootAnchor: bootAnchor
                ) != nil
        }
    }

    private static func earliestUnansweredMovement(
        in events: [CollectionHealthEvent],
        now: Date,
        systemUptime: TimeInterval,
        bootAnchor: TimeInterval
    ) -> CollectionHealthEvent? {
        events.first { event in
            guard event.kind == .motionMovementDetected,
                  let age = reliableAge(
                    of: event,
                    now: now,
                    systemUptime: systemUptime,
                    bootAnchor: bootAnchor
                  ),
                  age >= movementSampleDeadline else {
                return false
            }
            return !hasReliableAcceptedSample(
                after: event,
                in: events,
                now: now,
                systemUptime: systemUptime,
                bootAnchor: bootAnchor
            )
        }
    }

    private static func hasUnresolvedRetryableFailure(
        in events: [CollectionHealthEvent]
    ) -> Bool {
        guard let failure = events.last(where: {
            $0.kind == .tripOutcome && $0.tripOutcome == .failedRetryable
        }) else {
            return false
        }
        return !events.contains {
            $0.occurredAt > failure.occurredAt &&
                $0.kind == .tripOutcome &&
                ($0.tripOutcome == .persisted || $0.tripOutcome == .recovered)
        }
    }

    private static func hasUnresolvedPersistenceFailure(
        in events: [CollectionHealthEvent]
    ) -> Bool {
        // Un callback GPS ulterieur ne prouve pas que Core Data ou le journal
        // de trajet ont recommence a ecrire. Faute d'evenement de retablissement
        // specifique et durable, la panne reste visible pendant la fenetre de
        // retention. Cela evite un faux vert apres une perte de persistance.
        events.contains { $0.kind == .persistenceFailure }
    }

    private static func summarize(
        _ events: [CollectionHealthEvent]
    ) -> CollectionHealthWindowSummary {
        CollectionHealthWindowSummary(
            passiveWakeupCount: events.lazy.filter { $0.kind == .passiveWakeupReceived }.count,
            locationBatchCount: events.lazy.filter { $0.kind == .locationBatchReceived }.count,
            acceptedSampleHeartbeatCount: events.lazy.filter { $0.kind == .acceptedSample }.count,
            tripStartedCount: events.lazy.filter { $0.kind == .tripStarted }.count,
            persistedTripCount: events.lazy.filter {
                $0.kind == .tripOutcome && $0.tripOutcome == .persisted
            }.count,
            rejectedTripCount: events.lazy.filter {
                $0.kind == .tripOutcome && $0.tripOutcome == .rejected
            }.count,
            recoveredTripCount: events.lazy.filter {
                $0.kind == .tripOutcome && $0.tripOutcome == .recovered
            }.count,
            failedRetryableTripCount: events.lazy.filter {
                $0.kind == .tripOutcome && $0.tripOutcome == .failedRetryable
            }.count,
            persistenceFailureCount: events.lazy.filter { $0.kind == .persistenceFailure }.count
        )
    }
}
