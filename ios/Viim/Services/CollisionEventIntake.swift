import CryptoKit
import Foundation

/// Origine minimale d'un evenement remis a l'inbox. Le cas de simulation n'est
/// branche a aucune vue ni argument de lancement : il existe uniquement pour
/// exercer le meme chemin persistant dans les tests Debug.
enum CollisionEventSource: String, Codable, Equatable {
    case safetyKit
    case simulatedTest
}

/// Preuve minimale recue avant toute decision. Elle ne contient ni contact,
/// fiche medicale, trace GPS, URL reseau ou promesse de livraison.
struct CollisionEventEvidence: Codable, Equatable, Identifiable {
    static let schemaVersion = 1

    let eventID: UUID
    let source: CollisionEventSource
    let sourceEventDate: Date
    let receivedAt: Date
    let latitude: Double?
    let longitude: Double?
    let schemaVersion: Int

    var id: UUID { eventID }

    init(
        source: CollisionEventSource,
        sourceEventDate: Date,
        receivedAt: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.source = source
        self.sourceEventDate = sourceEventDate
        self.receivedAt = receivedAt
        self.latitude = latitude
        self.longitude = longitude
        self.schemaVersion = schemaVersion
        eventID = Self.deterministicID(source: source, sourceEventDate: sourceEventDate)
    }

    var isStructurallyValid: Bool {
        let sourceTimestamp = sourceEventDate.timeIntervalSince1970
        let receiptTimestamp = receivedAt.timeIntervalSince1970
        guard Self.sourceMilliseconds(sourceEventDate) != nil else { return false }
        let coordinatesAreAbsent = latitude == nil && longitude == nil
        let coordinatesAreValid = latitude.map { $0.isFinite && (-90...90).contains($0) } == true &&
            longitude.map { $0.isFinite && (-180...180).contains($0) } == true
        return schemaVersion == Self.schemaVersion &&
            sourceTimestamp.isFinite &&
            receiptTimestamp.isFinite &&
            eventID == Self.deterministicID(source: source, sourceEventDate: sourceEventDate) &&
            (coordinatesAreAbsent || coordinatesAreValid)
    }

    /// Un replay SafetyKit arrive plus tard et porte donc un autre `receivedAt`.
    /// Cette date de reception ne doit pas transformer le meme evenement source
    /// en conflit. Une position differente reste en revanche un conflit ferme.
    func representsSameSourceEvent(as other: Self) -> Bool {
        source == other.source &&
            Self.sourceMilliseconds(sourceEventDate) == Self.sourceMilliseconds(other.sourceEventDate) &&
            latitude == other.latitude &&
            longitude == other.longitude &&
            schemaVersion == other.schemaVersion
    }

    static func deterministicID(
        source: CollisionEventSource,
        sourceEventDate: Date
    ) -> UUID {
        let timestampComponent = sourceMilliseconds(sourceEventDate).map(String.init) ?? "invalid"
        let material = "viim-collision-event-v1|\(source.rawValue)|\(timestampComponent)"
        var bytes = Array(SHA256.hash(data: Data(material.utf8)).prefix(16))
        // UUID v5-like : l'identite est deterministe, sans pretendre utiliser
        // l'algorithme SHA-1 normalise de RFC 4122.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func sourceMilliseconds(_ date: Date) -> Int64? {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
        guard milliseconds.isFinite,
              milliseconds >= Double(Int64.min),
              milliseconds <= Double(Int64.max) else {
            return nil
        }
        return Int64(milliseconds)
    }
}

enum CollisionEventIntakePhase: String, Codable, Equatable {
    case received
    case awaitingUserDecision
    case cancelledByUser
    case helpRequested
    case expiredNoDecision

    var isTerminal: Bool {
        switch self {
        case .cancelledByUser, .helpRequested, .expiredNoDecision:
            true
        case .received, .awaitingUserDecision:
            false
        }
    }
}

enum CollisionEventIntakeTransitionError: Error, Equatable {
    case invalidEvidence
    case invalidDeadline
    case invalidTransition
    case nonMonotonicTimestamp
    case decisionWindowClosed
    case decisionWindowOpen
}

struct CollisionEventIntakeRecord: Codable, Equatable, Identifiable {
    static let maximumDecisionWindow: TimeInterval = 60

    let evidence: CollisionEventEvidence
    let decisionDeadline: Date
    private(set) var phase: CollisionEventIntakePhase
    private(set) var updatedAt: Date

    var id: UUID { evidence.id }

    init(
        evidence: CollisionEventEvidence,
        decisionDeadline: Date? = nil
    ) throws {
        let deadline = decisionDeadline ?? evidence.receivedAt.addingTimeInterval(Self.maximumDecisionWindow)
        guard evidence.isStructurallyValid else {
            throw CollisionEventIntakeTransitionError.invalidEvidence
        }
        guard deadline >= evidence.receivedAt,
              deadline.timeIntervalSince(evidence.receivedAt) <= Self.maximumDecisionWindow else {
            throw CollisionEventIntakeTransitionError.invalidDeadline
        }
        self.evidence = evidence
        self.decisionDeadline = deadline
        phase = .received
        updatedAt = evidence.receivedAt
    }

    var isStructurallyValid: Bool {
        guard evidence.isStructurallyValid,
              decisionDeadline >= evidence.receivedAt,
              decisionDeadline.timeIntervalSince(evidence.receivedAt) <= Self.maximumDecisionWindow,
              updatedAt >= evidence.receivedAt else {
            return false
        }
        switch phase {
        case .received:
            return updatedAt == evidence.receivedAt
        case .awaitingUserDecision, .cancelledByUser, .helpRequested:
            return updatedAt < decisionDeadline
        case .expiredNoDecision:
            return updatedAt >= decisionDeadline
        }
    }

    mutating func beginUserDecision(at date: Date) throws {
        if phase == .awaitingUserDecision { return }
        guard phase == .received else {
            throw CollisionEventIntakeTransitionError.invalidTransition
        }
        try validateMonotonic(date)
        guard date < decisionDeadline else {
            throw CollisionEventIntakeTransitionError.decisionWindowClosed
        }
        phase = .awaitingUserDecision
        updatedAt = date
    }

    mutating func cancel(at date: Date) throws {
        if phase == .cancelledByUser { return }
        guard phase == .received || phase == .awaitingUserDecision else {
            throw CollisionEventIntakeTransitionError.invalidTransition
        }
        try validateMonotonic(date)
        guard date < decisionDeadline else {
            throw CollisionEventIntakeTransitionError.decisionWindowClosed
        }
        phase = .cancelledByUser
        updatedAt = date
    }

    mutating func requestHelp(at date: Date) throws {
        if phase == .helpRequested { return }
        guard phase == .received || phase == .awaitingUserDecision else {
            throw CollisionEventIntakeTransitionError.invalidTransition
        }
        try validateMonotonic(date)
        guard date < decisionDeadline else {
            throw CollisionEventIntakeTransitionError.decisionWindowClosed
        }
        phase = .helpRequested
        updatedAt = date
    }

    mutating func expire(at date: Date) throws {
        if phase == .expiredNoDecision { return }
        guard phase == .received || phase == .awaitingUserDecision else {
            throw CollisionEventIntakeTransitionError.invalidTransition
        }
        try validateMonotonic(date)
        guard date >= decisionDeadline else {
            throw CollisionEventIntakeTransitionError.decisionWindowOpen
        }
        phase = .expiredNoDecision
        updatedAt = date
    }

    private func validateMonotonic(_ date: Date) throws {
        guard date.timeIntervalSince1970.isFinite, date >= updatedAt else {
            throw CollisionEventIntakeTransitionError.nonMonotonicTimestamp
        }
    }
}

protocol CollisionEventJournaling: AnyObject {
    var storageAvailable: Bool { get }
    func load() throws -> [CollisionEventIntakeRecord]
    func ingest(_ record: CollisionEventIntakeRecord, now: Date) throws -> CollisionEventIntakeRecord
    func beginUserDecision(id: UUID, at date: Date) throws -> CollisionEventIntakeRecord
    func cancel(id: UUID, at date: Date) throws -> CollisionEventIntakeRecord
    func requestHelp(id: UUID, at date: Date) throws -> CollisionEventIntakeRecord
    func expire(id: UUID, at date: Date) throws -> CollisionEventIntakeRecord
    func expireDue(at date: Date) throws -> [CollisionEventIntakeRecord]
}

final class CollisionEventJournal: CollisionEventJournaling {
    static let schemaVersion = 1
    static let defaultMaximumRecordCount = 128
    static let defaultMaximumFileBytes = 256_000
    static let terminalRetention: TimeInterval = 30 * 24 * 60 * 60
    static let protectedWriteOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUntilFirstUserAuthentication
    ]

    enum IntegrityError: Error, Equatable {
        case oversized
        case malformed
        case unsupportedSchema
        case invalidRecord
        case duplicateIdentifier
        case conflictingIdentifier
        case tooManyRecords
        case recordNotFound
    }

    private struct Payload: Codable {
        let schemaVersion: Int
        let records: [CollisionEventIntakeRecord]
    }

    private let fileURL: URL
    private let maximumRecordCount: Int
    private let maximumFileBytes: Int
    private static let processLock = NSLock()
    private let storageLock = NSLock()
    private var storageIsAvailable = true

    var storageAvailable: Bool {
        storageLock.lock()
        defer { storageLock.unlock() }
        return storageIsAvailable
    }

    init(
        fileURL: URL = CollisionEventJournal.defaultFileURL(),
        maximumRecordCount: Int = CollisionEventJournal.defaultMaximumRecordCount,
        maximumFileBytes: Int = CollisionEventJournal.defaultMaximumFileBytes
    ) {
        self.fileURL = fileURL
        self.maximumRecordCount = max(1, maximumRecordCount)
        self.maximumFileBytes = max(1, maximumFileBytes)
    }

    func load() throws -> [CollisionEventIntakeRecord] {
        try locked { try loadUnlocked() }
    }

    func ingest(
        _ record: CollisionEventIntakeRecord,
        now: Date
    ) throws -> CollisionEventIntakeRecord {
        try locked {
            guard record.isStructurallyValid, record.phase == .received else {
                throw IntegrityError.invalidRecord
            }
            var records = try loadUnlocked()
            if let existing = records.first(where: { $0.id == record.id }) {
                guard existing.evidence.representsSameSourceEvent(as: record.evidence) else {
                    throw IntegrityError.conflictingIdentifier
                }
                return existing
            }
            let cutoff = now.addingTimeInterval(-Self.terminalRetention)
            records.removeAll { $0.phase.isTerminal && $0.updatedAt < cutoff }
            guard records.count < maximumRecordCount else {
                throw IntegrityError.tooManyRecords
            }
            records.append(record)
            try writeUnlocked(records)
            return record
        }
    }

    func beginUserDecision(id: UUID, at date: Date) throws -> CollisionEventIntakeRecord {
        try transition(id: id) { try $0.beginUserDecision(at: date) }
    }

    func cancel(id: UUID, at date: Date) throws -> CollisionEventIntakeRecord {
        try transition(id: id) { try $0.cancel(at: date) }
    }

    func requestHelp(id: UUID, at date: Date) throws -> CollisionEventIntakeRecord {
        try transition(id: id) { try $0.requestHelp(at: date) }
    }

    func expire(id: UUID, at date: Date) throws -> CollisionEventIntakeRecord {
        try transition(id: id) { try $0.expire(at: date) }
    }

    func expireDue(at date: Date) throws -> [CollisionEventIntakeRecord] {
        try locked {
            var records = try loadUnlocked()
            var changed = false
            for index in records.indices where
                !records[index].phase.isTerminal && records[index].decisionDeadline <= date {
                try records[index].expire(at: date)
                changed = true
            }
            if changed { try writeUnlocked(records) }
            return Self.sorted(records)
        }
    }

    private func transition(
        id: UUID,
        mutation: (inout CollisionEventIntakeRecord) throws -> Void
    ) throws -> CollisionEventIntakeRecord {
        try locked {
            var records = try loadUnlocked()
            guard let index = records.firstIndex(where: { $0.id == id }) else {
                throw IntegrityError.recordNotFound
            }
            try mutation(&records[index])
            guard records[index].isStructurallyValid else {
                throw IntegrityError.invalidRecord
            }
            try writeUnlocked(records)
            return records[index]
        }
    }

    private func loadUnlocked() throws -> [CollisionEventIntakeRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else { throw IntegrityError.oversized }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw IntegrityError.malformed
        }
        guard payload.schemaVersion == Self.schemaVersion else {
            throw IntegrityError.unsupportedSchema
        }
        guard payload.records.count <= maximumRecordCount else {
            throw IntegrityError.tooManyRecords
        }
        guard payload.records.allSatisfy(\.isStructurallyValid) else {
            throw IntegrityError.invalidRecord
        }
        guard Set(payload.records.map(\.id)).count == payload.records.count else {
            throw IntegrityError.duplicateIdentifier
        }
        return Self.sorted(payload.records)
    }

    private func writeUnlocked(_ records: [CollisionEventIntakeRecord]) throws {
        guard records.count <= maximumRecordCount,
              records.allSatisfy(\.isStructurallyValid),
              Set(records.map(\.id)).count == records.count else {
            throw IntegrityError.invalidRecord
        }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(
            Payload(schemaVersion: Self.schemaVersion, records: Self.sorted(records))
        )
        guard data.count <= maximumFileBytes else { throw IntegrityError.oversized }
        try data.write(to: fileURL, options: Self.protectedWriteOptions)
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        do {
            let value = try operation()
            setStorageAvailable(true)
            return value
        } catch {
            setStorageAvailable(false)
            throw error
        }
    }

    private func setStorageAvailable(_ available: Bool) {
        storageLock.lock()
        storageIsAvailable = available
        storageLock.unlock()
    }

    private static func sorted(
        _ records: [CollisionEventIntakeRecord]
    ) -> [CollisionEventIntakeRecord] {
        records.sorted {
            if $0.evidence.receivedAt != $1.evidence.receivedAt {
                return $0.evidence.receivedAt < $1.evidence.receivedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("ViimCollisionEventInbox.json")
    }
}

protocol CollisionEventReceiving: AnyObject {
    func receive(_ evidence: CollisionEventEvidence)
}

enum CollisionEventCoordinatorState: Equatable {
    case idle
    case pending(CollisionEventIntakeRecord)
    case terminal(CollisionEventIntakeRecord)
    case invalidEvent
    case storageUnavailable
}

/// Orchestrateur local uniquement. Il ne possede volontairement aucun transport,
/// aucune notification et aucun timer d'escalade. Toute transition est ecrite
/// avant d'etre publiee a une future interface.
final class CollisionEventCoordinator: CollisionEventReceiving {
    static let maximumFreshEventAge: TimeInterval = 5 * 60
    static let maximumFutureClockSkew: TimeInterval = 5 * 60

    private let journal: CollisionEventJournaling
    private let clock: () -> Date
    private(set) var state: CollisionEventCoordinatorState = .idle
    var onStateChange: ((CollisionEventCoordinatorState) -> Void)?

    init(
        journal: CollisionEventJournaling = CollisionEventJournal(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.journal = journal
        self.clock = clock
    }

    func restore() {
        do {
            let now = clock()
            let records = try journal.expireDue(at: now)
            guard var candidate = records.last(where: { !$0.phase.isTerminal }) else {
                publish(records.last.map(CollisionEventCoordinatorState.terminal) ?? .idle)
                return
            }
            if candidate.phase == .received {
                candidate = try journal.beginUserDecision(id: candidate.id, at: now)
            }
            publish(.pending(candidate))
        } catch {
            publish(.storageUnavailable)
        }
    }

    func receive(_ evidence: CollisionEventEvidence) {
        guard evidence.isStructurallyValid else {
            publish(.invalidEvent)
            return
        }
#if !DEBUG
        guard evidence.source == .safetyKit else {
            publish(.invalidEvent)
            return
        }
#endif
        let age = evidence.receivedAt.timeIntervalSince(evidence.sourceEventDate)
        guard age >= -Self.maximumFutureClockSkew else {
            publish(.invalidEvent)
            return
        }
        do {
            let isHistorical = age > Self.maximumFreshEventAge
            let deadline = isHistorical
                ? evidence.receivedAt
                : evidence.receivedAt.addingTimeInterval(CollisionEventIntakeRecord.maximumDecisionWindow)
            let newRecord = try CollisionEventIntakeRecord(
                evidence: evidence,
                decisionDeadline: deadline
            )
            var stored = try journal.ingest(newRecord, now: evidence.receivedAt)
            if stored.phase.isTerminal {
                publish(.terminal(stored))
                return
            }
            if stored.decisionDeadline <= evidence.receivedAt {
                stored = try journal.expire(id: stored.id, at: evidence.receivedAt)
                publish(.terminal(stored))
                return
            }
            if stored.phase == .received {
                stored = try journal.beginUserDecision(id: stored.id, at: evidence.receivedAt)
            }
            publish(.pending(stored))
        } catch {
            publish(.storageUnavailable)
        }
    }

    func cancelCurrent(at date: Date? = nil) {
        guard case .pending(let current) = state else { return }
        let decisionDate = date ?? clock()
        do {
            let updated = try journal.cancel(id: current.id, at: decisionDate)
            publish(.terminal(updated))
        } catch CollisionEventIntakeTransitionError.decisionWindowClosed {
            expireLateDecision(id: current.id, at: decisionDate)
        } catch {
            publish(.storageUnavailable)
        }
    }

    func requestHelpForCurrent(at date: Date? = nil) {
        guard case .pending(let current) = state else { return }
        let decisionDate = date ?? clock()
        do {
            let updated = try journal.requestHelp(id: current.id, at: decisionDate)
            publish(.terminal(updated))
        } catch CollisionEventIntakeTransitionError.decisionWindowClosed {
            expireLateDecision(id: current.id, at: decisionDate)
        } catch {
            publish(.storageUnavailable)
        }
    }

    func refresh() {
        restore()
    }

    private func publish(_ newState: CollisionEventCoordinatorState) {
        state = newState
        onStateChange?(newState)
    }

    private func expireLateDecision(id: UUID, at date: Date) {
        do {
            let expired = try journal.expire(id: id, at: date)
            publish(.terminal(expired))
        } catch {
            publish(.storageUnavailable)
        }
    }
}
