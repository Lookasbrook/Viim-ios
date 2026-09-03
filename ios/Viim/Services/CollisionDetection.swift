import CoreLocation
import CoreMotion
import Foundation

/// Echantillon minimal du moteur de calibration collision. Les coordonnees ne
/// font volontairement pas partie du modele : aucun trace haute frequence ni
/// emplacement n'est persiste par ce composant.
struct CollisionSensorFrame: Equatable {
    let timestamp: Date
    let userAccelerationMagnitudeG: Double
    let rotationRateMagnitude: Double
    let gpsSpeedKmh: Double?
    let gpsSpeedAccuracyKmh: Double?
    let gpsTimestamp: Date?
}

enum CollisionShadowReviewLabel: String, Codable, CaseIterable, Equatable {
    case noUnusualEvent
    case hardBraking
    case roadImpact
    case phoneMovement
    case realCollision
    case uncertain
}

struct CollisionShadowCandidate: Codable, Equatable, Identifiable {
    let id: UUID
    let algorithmVersion: String
    let impactAt: Date
    let confirmedAt: Date
    let peakUserAccelerationG: Double
    let peakRotationRate: Double
    let preImpactSpeedKmh: Double
    let postImpactSpeedKmh: Double
    let speedLossKmh: Double
    let preImpactSpeedAccuracyKmh: Double?
    let postImpactSpeedAccuracyKmh: Double?
    let tripID: UUID?
    let vehicleType: VehicleType?

    init(
        id: UUID,
        algorithmVersion: String,
        impactAt: Date,
        confirmedAt: Date,
        peakUserAccelerationG: Double,
        peakRotationRate: Double,
        preImpactSpeedKmh: Double,
        postImpactSpeedKmh: Double,
        speedLossKmh: Double,
        preImpactSpeedAccuracyKmh: Double? = nil,
        postImpactSpeedAccuracyKmh: Double? = nil,
        tripID: UUID? = nil,
        vehicleType: VehicleType? = nil
    ) {
        self.id = id
        self.algorithmVersion = algorithmVersion
        self.impactAt = impactAt
        self.confirmedAt = confirmedAt
        self.peakUserAccelerationG = peakUserAccelerationG
        self.peakRotationRate = peakRotationRate
        self.preImpactSpeedKmh = preImpactSpeedKmh
        self.postImpactSpeedKmh = postImpactSpeedKmh
        self.speedLossKmh = speedLossKmh
        self.preImpactSpeedAccuracyKmh = preImpactSpeedAccuracyKmh
        self.postImpactSpeedAccuracyKmh = postImpactSpeedAccuracyKmh
        self.tripID = tripID
        self.vehicleType = vehicleType
    }

    /// Validation volontairement large : elle rejette uniquement les donnees
    /// impossibles ou incoherentes. Les seuils de detection restent portes par
    /// CollisionDetectionPolicy afin de pouvoir recalibrer l'algorithme sans
    /// rendre illisibles les observations historiques.
    var isStructurallyValid: Bool {
        let impactTimestamp = impactAt.timeIntervalSinceReferenceDate
        let confirmationTimestamp = confirmedAt.timeIntervalSinceReferenceDate
        let confirmationDelay = confirmedAt.timeIntervalSince(impactAt)
        let expectedSpeedLoss = preImpactSpeedKmh - postImpactSpeedKmh

        return !algorithmVersion.isEmpty && algorithmVersion.utf8.count <= 128 &&
            impactTimestamp.isFinite && confirmationTimestamp.isFinite &&
            confirmationDelay >= 0 && confirmationDelay <= 60 &&
            peakUserAccelerationG.isFinite &&
            (0...100).contains(peakUserAccelerationG) &&
            peakRotationRate.isFinite && (0...1_000).contains(peakRotationRate) &&
            preImpactSpeedKmh.isFinite && (0...600).contains(preImpactSpeedKmh) &&
            postImpactSpeedKmh.isFinite && (0...600).contains(postImpactSpeedKmh) &&
            speedLossKmh.isFinite && (0...600).contains(speedLossKmh) &&
            postImpactSpeedKmh <= preImpactSpeedKmh &&
            abs(expectedSpeedLoss - speedLossKmh) <= 0.1 &&
            Self.isValidAccuracy(preImpactSpeedAccuracyKmh) &&
            Self.isValidAccuracy(postImpactSpeedAccuracyKmh)
    }

    private static func isValidAccuracy(_ accuracyKmh: Double?) -> Bool {
        guard let accuracyKmh else { return true }
        return accuracyKmh.isFinite && (0...100).contains(accuracyKmh)
    }

    func contextualized(tripID: UUID, vehicleType: VehicleType) -> Self {
        Self(
            id: id,
            algorithmVersion: algorithmVersion,
            impactAt: impactAt,
            confirmedAt: confirmedAt,
            peakUserAccelerationG: peakUserAccelerationG,
            peakRotationRate: peakRotationRate,
            preImpactSpeedKmh: preImpactSpeedKmh,
            postImpactSpeedKmh: postImpactSpeedKmh,
            speedLossKmh: speedLossKmh,
            preImpactSpeedAccuracyKmh: preImpactSpeedAccuracyKmh,
            postImpactSpeedAccuracyKmh: postImpactSpeedAccuracyKmh,
            tripID: tripID,
            vehicleType: vehicleType
        )
    }
}

struct CollisionDetectionPolicy: Equatable {
    /// Les seuils automobiles publies concernent des capteurs rigidement fixes
    /// au vehicule. Un telephone pouvant bouger dans l'habitacle, ce moteur de
    /// calibration exige un pic plus fort ET une perte de vitesse GPS fiable.
    let minimumImpactG: Double
    let minimumPreImpactSpeedKmh: Double
    let minimumSpeedLossKmh: Double
    let maximumGPSSpeedAccuracyKmh: Double
    let maximumGPSAge: TimeInterval
    let confirmationWindow: TimeInterval
    let candidateCooldown: TimeInterval

    static let shadowV2 = CollisionDetectionPolicy(
        minimumImpactG: 3.5,
        minimumPreImpactSpeedKmh: 20,
        minimumSpeedLossKmh: 12,
        maximumGPSSpeedAccuracyKmh: 9,
        maximumGPSAge: 3,
        confirmationWindow: 5,
        candidateCooldown: 60
    )

    func qualifiedSpeed(
        from frame: CollisionSensorFrame
    ) -> (value: Double, accuracy: Double)? {
        guard let speed = frame.gpsSpeedKmh,
              let accuracy = frame.gpsSpeedAccuracyKmh,
              let gpsTimestamp = frame.gpsTimestamp,
              speed.isFinite,
              speed >= 0,
              accuracy.isFinite,
              accuracy >= 0,
              accuracy <= maximumGPSSpeedAccuracyKmh else {
            return nil
        }

        let age = frame.timestamp.timeIntervalSince(gpsTimestamp)
        guard age >= -0.5, age <= maximumGPSAge else {
            return nil
        }
        return (speed, accuracy)
    }
}

struct CollisionDetectionEngine {
    static let algorithmVersion = "collision-shadow-v2-impact-gps-uncertainty"

    private struct PendingImpact {
        let impactAt: Date
        let preImpactSpeedKmh: Double
        let preImpactSpeedAccuracyKmh: Double
        var peakUserAccelerationG: Double
        var peakRotationRate: Double
    }

    private let policy: CollisionDetectionPolicy
    private var pendingImpact: PendingImpact?
    private var lastCandidateAt: Date?
    private var lastFrameAt: Date?

    init(policy: CollisionDetectionPolicy = .shadowV2) {
        self.policy = policy
    }

    var hasPendingImpact: Bool {
        pendingImpact != nil
    }

    mutating func reset() {
        pendingImpact = nil
        lastFrameAt = nil
    }

    mutating func ingest(_ frame: CollisionSensorFrame) -> CollisionShadowCandidate? {
        guard frame.timestamp.timeIntervalSinceReferenceDate.isFinite,
              frame.userAccelerationMagnitudeG.isFinite,
              frame.userAccelerationMagnitudeG >= 0,
              frame.rotationRateMagnitude.isFinite,
              frame.rotationRateMagnitude >= 0 else {
            return nil
        }

        if let lastFrameAt, frame.timestamp < lastFrameAt {
            // Une discontinuite d'horloge rendrait la fenetre de confirmation
            // non fiable. On abandonne uniquement le candidat en memoire.
            pendingImpact = nil
        }
        lastFrameAt = frame.timestamp

        if let lastCandidateAt,
           frame.timestamp.timeIntervalSince(lastCandidateAt) < policy.candidateCooldown {
            pendingImpact = nil
            return nil
        }

        if var pending = pendingImpact {
            let elapsed = frame.timestamp.timeIntervalSince(pending.impactAt)
            if elapsed > policy.confirmationWindow {
                pendingImpact = nil
            } else if elapsed >= 0 {
                pending.peakUserAccelerationG = max(
                    pending.peakUserAccelerationG,
                    frame.userAccelerationMagnitudeG
                )
                pending.peakRotationRate = max(
                    pending.peakRotationRate,
                    frame.rotationRateMagnitude
                )
                pendingImpact = pending

                if let postSpeed = policy.qualifiedSpeed(from: frame),
                   let gpsTimestamp = frame.gpsTimestamp,
                   gpsTimestamp > pending.impactAt {
                    let speedLoss = pending.preImpactSpeedKmh - postSpeed.value
                    // Les deux vitesses sont des estimations GPS. Confirmer
                    // uniquement si la perte reste suffisante apres avoir
                    // retranche l'incertitude avant et ajoute celle d'apres.
                    let conservativeSpeedLoss =
                        (pending.preImpactSpeedKmh - pending.preImpactSpeedAccuracyKmh) -
                        (postSpeed.value + postSpeed.accuracy)
                    if conservativeSpeedLoss >= policy.minimumSpeedLossKmh {
                        let candidate = CollisionShadowCandidate(
                            id: UUID(),
                            algorithmVersion: Self.algorithmVersion,
                            impactAt: pending.impactAt,
                            confirmedAt: frame.timestamp,
                            peakUserAccelerationG: pending.peakUserAccelerationG,
                            peakRotationRate: pending.peakRotationRate,
                            preImpactSpeedKmh: pending.preImpactSpeedKmh,
                            postImpactSpeedKmh: postSpeed.value,
                            speedLossKmh: speedLoss,
                            preImpactSpeedAccuracyKmh: pending.preImpactSpeedAccuracyKmh,
                            postImpactSpeedAccuracyKmh: postSpeed.accuracy
                        )
                        pendingImpact = nil
                        lastCandidateAt = frame.timestamp
                        return candidate
                    }
                }
                return nil
            }
        }

        guard frame.userAccelerationMagnitudeG >= policy.minimumImpactG,
              let preImpactSpeed = policy.qualifiedSpeed(from: frame),
              preImpactSpeed.value >= policy.minimumPreImpactSpeedKmh else {
            return nil
        }

        pendingImpact = PendingImpact(
            impactAt: frame.timestamp,
            preImpactSpeedKmh: preImpactSpeed.value,
            preImpactSpeedAccuracyKmh: preImpactSpeed.accuracy,
            peakUserAccelerationG: frame.userAccelerationMagnitudeG,
            peakRotationRate: frame.rotationRateMagnitude
        )
        return nil
    }

}

final class CollisionShadowJournal {
    static let defaultRetentionLimit = 100
    static let defaultMaximumFileBytes = 512_000
    static let protectedWriteOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUntilFirstUserAuthentication
    ]

    enum IntegrityError: Error, Equatable {
        case oversized
        case malformed
        case invalidEvidence
        case duplicateIdentifier
        case conflictingIdentifier

        var diagnosticReason: String {
            switch self {
            case .oversized: "oversized"
            case .malformed: "malformed"
            case .invalidEvidence: "invalidEvidence"
            case .duplicateIdentifier: "duplicateIdentifier"
            case .conflictingIdentifier: "conflictingIdentifier"
            }
        }
    }

    private let fileURL: URL
    private let retentionLimit: Int
    private let maximumFileBytes: Int
    private static let processLock = NSLock()

    init(
        fileURL: URL = CollisionShadowJournal.defaultFileURL(),
        retentionLimit: Int = CollisionShadowJournal.defaultRetentionLimit,
        maximumFileBytes: Int = CollisionShadowJournal.defaultMaximumFileBytes
    ) {
        self.fileURL = fileURL
        self.retentionLimit = max(1, retentionLimit)
        self.maximumFileBytes = max(1, maximumFileBytes)
    }

    func load() throws -> [CollisionShadowCandidate] {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        return try loadUnlocked()
    }

    func append(_ candidate: CollisionShadowCandidate) throws {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }

        guard candidate.isStructurallyValid else {
            throw IntegrityError.invalidEvidence
        }

        var candidates: [CollisionShadowCandidate]
        do {
            candidates = try loadUnlocked()
        } catch let error as IntegrityError {
            try quarantineCorruptFileUnlocked()
            candidates = []
            ViimDiagnostics.log(
                "collision.shadow.journal.recovered reason=\(error.diagnosticReason) quarantine=true"
            )
        }

        // Un meme evenement peut etre rejoue apres une reprise. Le rendre
        // idempotent evite de transformer un retry sain en corruption.
        if let existing = candidates.first(where: { $0.id == candidate.id }) {
            guard existing != candidate else { return }
            throw IntegrityError.conflictingIdentifier
        }

        candidates.append(candidate)
        if candidates.count > retentionLimit {
            candidates = Array(candidates.suffix(retentionLimit))
        }

        try writeUnlocked(candidates)
    }

    private func writeUnlocked(_ candidates: [CollisionShadowCandidate]) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(candidates)
        guard data.count <= maximumFileBytes else {
            throw IntegrityError.oversized
        }
        try data.write(to: fileURL, options: Self.protectedWriteOptions)
    }

    private func loadUnlocked() throws -> [CollisionShadowCandidate] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else {
            throw IntegrityError.oversized
        }

        let candidates: [CollisionShadowCandidate]
        do {
            candidates = try JSONDecoder().decode([CollisionShadowCandidate].self, from: data)
        } catch {
            throw IntegrityError.malformed
        }

        guard candidates.allSatisfy(\.isStructurallyValid) else {
            throw IntegrityError.invalidEvidence
        }
        guard Set(candidates.map(\.id)).count == candidates.count else {
            throw IntegrityError.duplicateIdentifier
        }
        return candidates
    }

    /// Ne jamais ecraser une preuve illisible. Elle est deplacee a cote du
    /// journal actif afin de rester extractible pour le diagnostic terrain.
    private func quarantineCorruptFileUnlocked() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let quarantineURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(
                "\(baseName).corrupt-\(UUID().uuidString).json"
            )
        try fileManager.moveItem(at: fileURL, to: quarantineURL)
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("ViimCollisionShadow.json")
    }
}

struct CollisionShadowReviewAnnotation: Codable, Equatable, Identifiable {
    static let schemaVersion = 1

    let candidateID: UUID
    let label: CollisionShadowReviewLabel
    let reviewedAt: Date
    let version: Int

    var id: UUID { candidateID }

    init(
        candidateID: UUID,
        label: CollisionShadowReviewLabel,
        reviewedAt: Date,
        version: Int = Self.schemaVersion
    ) {
        self.candidateID = candidateID
        self.label = label
        self.reviewedAt = reviewedAt
        self.version = version
    }

    var isStructurallyValid: Bool {
        version == Self.schemaVersion && reviewedAt.timeIntervalSinceReferenceDate.isFinite
    }
}

/// Les reponses utilisateur sont separees de la preuve capteur brute : corriger
/// une etiquette ne reecrit jamais le journal des candidats.
final class CollisionShadowReviewJournal {
    static let defaultRetentionLimit = CollisionShadowJournal.defaultRetentionLimit
    static let defaultMaximumFileBytes = 128_000

    enum IntegrityError: Error, Equatable {
        case oversized
        case malformed
        case invalidAnnotation
        case duplicateIdentifier

        var diagnosticReason: String {
            switch self {
            case .oversized: "oversized"
            case .malformed: "malformed"
            case .invalidAnnotation: "invalidAnnotation"
            case .duplicateIdentifier: "duplicateIdentifier"
            }
        }
    }

    private let fileURL: URL
    private let retentionLimit: Int
    private let maximumFileBytes: Int
    private static let processLock = NSLock()

    init(
        fileURL: URL = CollisionShadowReviewJournal.defaultFileURL(),
        retentionLimit: Int = CollisionShadowReviewJournal.defaultRetentionLimit,
        maximumFileBytes: Int = CollisionShadowReviewJournal.defaultMaximumFileBytes
    ) {
        self.fileURL = fileURL
        self.retentionLimit = max(1, retentionLimit)
        self.maximumFileBytes = max(1, maximumFileBytes)
    }

    func load() throws -> [CollisionShadowReviewAnnotation] {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        return try loadUnlocked()
    }

    func setReview(
        candidateID: UUID,
        label: CollisionShadowReviewLabel,
        reviewedAt: Date = Date()
    ) throws {
        let annotation = CollisionShadowReviewAnnotation(
            candidateID: candidateID,
            label: label,
            reviewedAt: reviewedAt
        )
        guard annotation.isStructurallyValid else {
            throw IntegrityError.invalidAnnotation
        }

        Self.processLock.lock()
        defer { Self.processLock.unlock() }

        var annotations: [CollisionShadowReviewAnnotation]
        do {
            annotations = try loadUnlocked()
        } catch let error as IntegrityError {
            try quarantineCorruptFileUnlocked()
            annotations = []
            ViimDiagnostics.log(
                "collision.shadow.reviewJournal.recovered reason=\(error.diagnosticReason) quarantine=true"
            )
        }

        if let index = annotations.firstIndex(where: { $0.candidateID == candidateID }) {
            guard annotations[index].label != label else { return }
            annotations[index] = annotation
        } else {
            annotations.append(annotation)
        }
        annotations.sort { $0.reviewedAt < $1.reviewedAt }
        if annotations.count > retentionLimit {
            annotations = Array(annotations.suffix(retentionLimit))
        }
        try writeUnlocked(annotations)
    }

    private func loadUnlocked() throws -> [CollisionShadowReviewAnnotation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else { throw IntegrityError.oversized }

        let annotations: [CollisionShadowReviewAnnotation]
        do {
            annotations = try JSONDecoder().decode(
                [CollisionShadowReviewAnnotation].self,
                from: data
            )
        } catch {
            throw IntegrityError.malformed
        }
        guard annotations.allSatisfy(\.isStructurallyValid) else {
            throw IntegrityError.invalidAnnotation
        }
        guard Set(annotations.map(\.candidateID)).count == annotations.count else {
            throw IntegrityError.duplicateIdentifier
        }
        return annotations
    }

    private func writeUnlocked(_ annotations: [CollisionShadowReviewAnnotation]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(annotations)
        guard data.count <= maximumFileBytes else { throw IntegrityError.oversized }
        try data.write(to: fileURL, options: CollisionShadowJournal.protectedWriteOptions)
    }

    private func quarantineCorruptFileUnlocked() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let quarantineURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName).corrupt-\(UUID().uuidString).json")
        try fileManager.moveItem(at: fileURL, to: quarantineURL)
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("ViimCollisionShadowReviews.json")
    }
}

struct CollisionShadowTripContext: Equatable {
    let id: UUID
    let startedAt: Date
}

enum CollisionShadowSessionEndReason: String, Codable, Equatable {
    case tripEnded
    case tripChanged
    case vehicleChanged
    case locationCollectionStopped
    case unsupportedVehicle
    case deviceMotionUnavailable
    case coordinatorStopped
}

struct CollisionShadowCoverageRecord: Codable, Equatable, Identifiable {
    static let schemaVersion = 1
    static let maximumSessionDuration: TimeInterval = 7 * 24 * 60 * 60
    static let maximumFrameCount = 100_000_000

    let id: UUID
    let tripID: UUID
    let tripStartedAt: Date
    let vehicleType: VehicleType
    let algorithmVersion: String
    let shadowStartedAt: Date
    var lastCheckpointAt: Date
    var endedAt: Date?
    var endReason: CollisionShadowSessionEndReason?
    var frameCount: Int
    var qualifiedGPSFrameCount: Int
    var gapCount: Int
    var missingMotionDuration: TimeInterval
    var maximumMotionGap: TimeInterval
    var candidateCount: Int
    var motionErrorCount: Int
    let version: Int

    var elapsedShadowDuration: TimeInterval {
        max(0, lastCheckpointAt.timeIntervalSince(shadowStartedAt))
    }

    var isStructurallyValid: Bool {
        let datesAreFinite = [tripStartedAt, shadowStartedAt, lastCheckpointAt]
            .allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite }
        let optionalEndIsFinite = endedAt?.timeIntervalSinceReferenceDate.isFinite ?? true
        let endStateIsConsistent = (endedAt == nil) == (endReason == nil)
        let endIsOrdered = endedAt.map {
            $0 >= shadowStartedAt && $0 == lastCheckpointAt
        } ?? true

        return version == Self.schemaVersion &&
            !algorithmVersion.isEmpty && algorithmVersion.utf8.count <= 128 &&
            datesAreFinite && optionalEndIsFinite &&
            tripStartedAt <= shadowStartedAt &&
            lastCheckpointAt >= shadowStartedAt &&
            endStateIsConsistent && endIsOrdered &&
            vehicleType != .velo &&
            frameCount >= 0 && qualifiedGPSFrameCount >= 0 &&
            frameCount <= Self.maximumFrameCount &&
            qualifiedGPSFrameCount <= frameCount &&
            gapCount >= 0 && gapCount <= frameCount &&
            candidateCount >= 0 && candidateCount <= frameCount &&
            motionErrorCount >= 0 && motionErrorCount <= Self.maximumFrameCount &&
            elapsedShadowDuration <= Self.maximumSessionDuration &&
            missingMotionDuration.isFinite && missingMotionDuration >= 0 &&
            missingMotionDuration <= elapsedShadowDuration &&
            maximumMotionGap.isFinite && maximumMotionGap >= 0 &&
            maximumMotionGap <= elapsedShadowDuration
    }

    func isMonotonicUpdate(of previous: Self) -> Bool {
        id == previous.id && tripID == previous.tripID &&
            tripStartedAt == previous.tripStartedAt &&
            vehicleType == previous.vehicleType &&
            algorithmVersion == previous.algorithmVersion &&
            shadowStartedAt == previous.shadowStartedAt &&
            version == previous.version &&
            lastCheckpointAt >= previous.lastCheckpointAt &&
            frameCount >= previous.frameCount &&
            qualifiedGPSFrameCount >= previous.qualifiedGPSFrameCount &&
            gapCount >= previous.gapCount &&
            missingMotionDuration >= previous.missingMotionDuration &&
            maximumMotionGap >= previous.maximumMotionGap &&
            candidateCount >= previous.candidateCount &&
            motionErrorCount >= previous.motionErrorCount &&
            (previous.endedAt == nil || self == previous)
    }
}

struct CollisionShadowCoverageSummary: Equatable {
    let sessionCount: Int
    let completedSessionCount: Int
    let unfinishedSessionCount: Int
    let frameCount: Int
    let qualifiedGPSFrameCount: Int
    let gapCount: Int
    let candidateCount: Int
    let motionErrorCount: Int

    var qualifiedGPSRatio: Double? {
        guard frameCount > 0 else { return nil }
        return Double(qualifiedGPSFrameCount) / Double(frameCount)
    }

    static func summarize(_ records: [CollisionShadowCoverageRecord]) -> Self {
        Self(
            sessionCount: records.count,
            completedSessionCount: records.lazy.filter { $0.endedAt != nil }.count,
            unfinishedSessionCount: records.lazy.filter { $0.endedAt == nil }.count,
            frameCount: records.reduce(0) { $0 + $1.frameCount },
            qualifiedGPSFrameCount: records.reduce(0) { $0 + $1.qualifiedGPSFrameCount },
            gapCount: records.reduce(0) { $0 + $1.gapCount },
            candidateCount: records.reduce(0) { $0 + $1.candidateCount },
            motionErrorCount: records.reduce(0) { $0 + $1.motionErrorCount }
        )
    }
}

struct CollisionShadowCoverageAccumulator {
    static let gapThreshold: TimeInterval = 1
    static let expectedFrameInterval: TimeInterval = 1.0 / 50.0

    private(set) var record: CollisionShadowCoverageRecord
    private var lastFrameAt: Date?

    init(
        context: CollisionShadowTripContext,
        vehicleType: VehicleType,
        startedAt: Date = Date(),
        sessionID: UUID = UUID()
    ) {
        record = CollisionShadowCoverageRecord(
            id: sessionID,
            tripID: context.id,
            tripStartedAt: context.startedAt,
            vehicleType: vehicleType,
            algorithmVersion: CollisionDetectionEngine.algorithmVersion,
            shadowStartedAt: startedAt,
            lastCheckpointAt: startedAt,
            endedAt: nil,
            endReason: nil,
            frameCount: 0,
            qualifiedGPSFrameCount: 0,
            gapCount: 0,
            missingMotionDuration: 0,
            maximumMotionGap: 0,
            candidateCount: 0,
            motionErrorCount: 0,
            version: CollisionShadowCoverageRecord.schemaVersion
        )
    }

    @discardableResult
    mutating func ingest(frame: CollisionSensorFrame, hasQualifiedGPS: Bool) -> Bool {
        guard record.endedAt == nil,
              frame.timestamp >= record.shadowStartedAt,
              lastFrameAt.map({ frame.timestamp >= $0 }) ?? true else {
            return false
        }

        var didObserveGap = false
        if let lastFrameAt {
            let gap = frame.timestamp.timeIntervalSince(lastFrameAt)
            if gap > Self.gapThreshold {
                record.gapCount += 1
                record.missingMotionDuration += max(0, gap - Self.expectedFrameInterval)
                record.maximumMotionGap = max(record.maximumMotionGap, gap)
                didObserveGap = true
            }
        }

        record.frameCount += 1
        if hasQualifiedGPS {
            record.qualifiedGPSFrameCount += 1
        }
        record.lastCheckpointAt = frame.timestamp
        self.lastFrameAt = frame.timestamp
        return didObserveGap
    }

    mutating func noteCandidate(at timestamp: Date) {
        guard record.endedAt == nil else { return }
        record.candidateCount += 1
        checkpoint(at: timestamp)
    }

    mutating func noteMotionError(at timestamp: Date) {
        guard record.endedAt == nil else { return }
        record.motionErrorCount += 1
        checkpoint(at: timestamp)
    }

    mutating func checkpoint(at timestamp: Date) {
        guard record.endedAt == nil else { return }
        record.lastCheckpointAt = max(record.lastCheckpointAt, timestamp)
    }

    mutating func finish(at timestamp: Date, reason: CollisionShadowSessionEndReason) {
        guard record.endedAt == nil else { return }
        let endedAt = max(record.lastCheckpointAt, timestamp)
        record.lastCheckpointAt = endedAt
        record.endedAt = endedAt
        record.endReason = reason
    }
}

final class CollisionShadowCoverageJournal {
    static let defaultRetentionLimit = 100
    static let defaultMaximumFileBytes = 256_000

    enum IntegrityError: Error, Equatable {
        case oversized
        case malformed
        case invalidRecord
        case duplicateIdentifier
        case conflictingSession

        var diagnosticReason: String {
            switch self {
            case .oversized: "oversized"
            case .malformed: "malformed"
            case .invalidRecord: "invalidRecord"
            case .duplicateIdentifier: "duplicateIdentifier"
            case .conflictingSession: "conflictingSession"
            }
        }
    }

    private let fileURL: URL
    private let retentionLimit: Int
    private let maximumFileBytes: Int
    private static let processLock = NSLock()

    init(
        fileURL: URL = CollisionShadowCoverageJournal.defaultFileURL(),
        retentionLimit: Int = CollisionShadowCoverageJournal.defaultRetentionLimit,
        maximumFileBytes: Int = CollisionShadowCoverageJournal.defaultMaximumFileBytes
    ) {
        self.fileURL = fileURL
        self.retentionLimit = max(1, retentionLimit)
        self.maximumFileBytes = max(1, maximumFileBytes)
    }

    func load() throws -> [CollisionShadowCoverageRecord] {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        return try loadUnlocked()
    }

    func upsert(_ record: CollisionShadowCoverageRecord) throws {
        guard record.isStructurallyValid else { throw IntegrityError.invalidRecord }
        Self.processLock.lock()
        defer { Self.processLock.unlock() }

        var records: [CollisionShadowCoverageRecord]
        do {
            records = try loadUnlocked()
        } catch let error as IntegrityError {
            try quarantineCorruptFileUnlocked()
            records = []
            ViimDiagnostics.log(
                "collision.shadow.coverageJournal.recovered reason=\(error.diagnosticReason) quarantine=true"
            )
        }

        if let index = records.firstIndex(where: { $0.id == record.id }) {
            guard record.isMonotonicUpdate(of: records[index]) else {
                throw IntegrityError.conflictingSession
            }
            guard records[index] != record else { return }
            records[index] = record
        } else {
            records.append(record)
        }
        records.sort { $0.shadowStartedAt < $1.shadowStartedAt }
        if records.count > retentionLimit {
            records = Array(records.suffix(retentionLimit))
        }
        try writeUnlocked(records)
    }

    private func loadUnlocked() throws -> [CollisionShadowCoverageRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else { throw IntegrityError.oversized }

        let records: [CollisionShadowCoverageRecord]
        do {
            records = try JSONDecoder().decode([CollisionShadowCoverageRecord].self, from: data)
        } catch {
            throw IntegrityError.malformed
        }
        guard records.allSatisfy(\.isStructurallyValid) else {
            throw IntegrityError.invalidRecord
        }
        guard Set(records.map(\.id)).count == records.count else {
            throw IntegrityError.duplicateIdentifier
        }
        return records
    }

    private func writeUnlocked(_ records: [CollisionShadowCoverageRecord]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(records)
        guard data.count <= maximumFileBytes else { throw IntegrityError.oversized }
        try data.write(to: fileURL, options: CollisionShadowJournal.protectedWriteOptions)
    }

    private func quarantineCorruptFileUnlocked() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let quarantineURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName).corrupt-\(UUID().uuidString).json")
        try fileManager.moveItem(at: fileURL, to: quarantineURL)
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("ViimCollisionShadowCoverage.json")
    }
}

/// Collecte locale de calibration uniquement pendant un trajet motorise actif.
/// Ce service ne declenche aucune alerte et ne transmet aucune donnee. Il sert a
/// observer des candidats. Sans couverture de session ni etiquette utilisateur,
/// il ne permet pas encore de mesurer un taux de faux positifs ou de faux negatifs.
final class CollisionShadowMonitor {
    private let motionManager: CMMotionManager
    private let queue: OperationQueue
    private let journal: CollisionShadowJournal
    private let coverageJournal: CollisionShadowCoverageJournal
    private var engine = CollisionDetectionEngine()
    private var vehicleType: VehicleType?
    private var activeTripContext: CollisionShadowTripContext?
    private var isLocationCollectionActive = false
    private var isMonitoring = false
    private var latestLocation: CLLocation?
    private var motionClockOffset: TimeInterval?
    private var lastMotionTimestamp: TimeInterval?
    private var didLogMotionError = false
    private var candidatesAwaitingPersistence: [CollisionShadowCandidate] = []
    private var lastPersistenceRetryAt: Date?
    private var coverageAccumulator: CollisionShadowCoverageAccumulator?
    private var coverageRecordsAwaitingPersistence: [CollisionShadowCoverageRecord] = []
    private var lastCoverageCheckpointAt: Date?
    private var lastCoveragePersistenceRetryAt: Date?

    private static let persistenceRetryInterval: TimeInterval = 5
    private static let coverageCheckpointInterval: TimeInterval = 30
    private static let maximumPendingPersistenceCandidates = 10
    private static let maximumPendingCoverageRecords = 10

    init(
        motionManager: CMMotionManager = CMMotionManager(),
        journal: CollisionShadowJournal = CollisionShadowJournal(),
        coverageJournal: CollisionShadowCoverageJournal = CollisionShadowCoverageJournal()
    ) {
        self.motionManager = motionManager
        self.journal = journal
        self.coverageJournal = coverageJournal
        let queue = OperationQueue()
        queue.name = "com.yamstack.viim.collision-shadow"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        self.queue = queue
    }

    func configure(vehicleType: VehicleType) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            if Self.shouldResetMonitoringContext(
                currentTripID: self.activeTripContext?.id,
                nextTripID: self.activeTripContext?.id,
                currentVehicleType: self.vehicleType,
                nextVehicleType: vehicleType
            ), self.isMonitoring {
                self.stopMonitoring(reason: .vehicleChanged)
            }
            self.vehicleType = vehicleType
            self.reconcileMonitoring()
        }
    }

    func setActiveTrip(context: CollisionShadowTripContext?) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            if Self.shouldResetMonitoringContext(
                currentTripID: self.activeTripContext?.id,
                nextTripID: context?.id,
                currentVehicleType: self.vehicleType,
                nextVehicleType: self.vehicleType
            ), self.isMonitoring {
                // Un impact en attente ne doit jamais traverser deux trajets.
                self.stopMonitoring(reason: context == nil ? .tripEnded : .tripChanged)
            }
            self.activeTripContext = context
            self.reconcileMonitoring()
        }
    }

    func setLocationCollectionActive(_ isActive: Bool) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.isLocationCollectionActive = isActive
            self.reconcileMonitoring()
        }
    }

    func updateLocation(_ location: CLLocation?) {
        queue.addOperation { [weak self] in
            self?.latestLocation = location
        }
    }

    func stop() {
        queue.addOperation { [weak self] in
            guard let self else { return }
            if self.isMonitoring {
                self.stopMonitoring(reason: .coordinatorStopped)
            }
            self.activeTripContext = nil
            self.reconcileMonitoring()
        }
    }

    static func shouldMonitor(
        tripActive: Bool,
        vehicleType: VehicleType?,
        locationCollectionActive: Bool,
        deviceMotionAvailable: Bool
    ) -> Bool {
        tripActive &&
            locationCollectionActive &&
            vehicleType.map { $0 != .velo } == true &&
            deviceMotionAvailable
    }

    static func shouldResetMonitoringContext(
        currentTripID: UUID?,
        nextTripID: UUID?,
        currentVehicleType: VehicleType?,
        nextVehicleType: VehicleType?
    ) -> Bool {
        currentTripID != nextTripID || currentVehicleType != nextVehicleType
    }

    private func reconcileMonitoring() {
        let shouldMonitor = Self.shouldMonitor(
            tripActive: activeTripContext != nil,
            vehicleType: vehicleType,
            locationCollectionActive: isLocationCollectionActive,
            deviceMotionAvailable: motionManager.isDeviceMotionAvailable
        )

        if shouldMonitor, !isMonitoring {
            startMonitoring()
        } else if !shouldMonitor, isMonitoring {
            stopMonitoring(reason: stopReasonForCurrentPrerequisites())
        } else if activeTripContext != nil, !motionManager.isDeviceMotionAvailable {
            ViimDiagnostics.log("collision.shadow.unavailable reason=deviceMotion")
        } else if activeTripContext != nil, vehicleType == nil {
            ViimDiagnostics.log("collision.shadow.unavailable reason=vehicleProfile")
        } else if activeTripContext != nil, !isLocationCollectionActive {
            ViimDiagnostics.log("collision.shadow.unavailable reason=locationCollection")
        }
    }

    private func stopReasonForCurrentPrerequisites() -> CollisionShadowSessionEndReason {
        guard activeTripContext != nil else { return .tripEnded }
        guard let vehicleType, vehicleType != .velo else { return .unsupportedVehicle }
        guard isLocationCollectionActive else { return .locationCollectionStopped }
        guard motionManager.isDeviceMotionAvailable else { return .deviceMotionUnavailable }
        return .coordinatorStopped
    }

    private func startMonitoring() {
        guard let activeTripContext, let vehicleType else { return }
        engine.reset()
        motionClockOffset = nil
        lastMotionTimestamp = nil
        didLogMotionError = false
        let startedAt = max(Date(), activeTripContext.startedAt)
        coverageAccumulator = CollisionShadowCoverageAccumulator(
            context: activeTripContext,
            vehicleType: vehicleType,
            startedAt: startedAt
        )
        checkpointCoverage(at: startedAt, force: true)
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        isMonitoring = true
        ViimDiagnostics.log(
            "collision.shadow.start algorithm=\(CollisionDetectionEngine.algorithmVersion) alerts=false network=false"
        )

        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                if !self.didLogMotionError {
                    self.didLogMotionError = true
                    let errorAt = Date()
                    self.coverageAccumulator?.noteMotionError(at: errorAt)
                    self.checkpointCoverage(at: errorAt, force: true)
                    ViimDiagnostics.log("collision.shadow.motionError code=\((error as NSError).code)")
                }
                return
            }
            guard let motion else { return }
            self.process(motion)
        }
    }

    private func stopMonitoring(reason: CollisionShadowSessionEndReason) {
        flushPendingPersistence(at: Date(), force: true)
        let endedAt = Date()
        coverageAccumulator?.finish(at: endedAt, reason: reason)
        checkpointCoverage(at: endedAt, force: true)
        motionManager.stopDeviceMotionUpdates()
        isMonitoring = false
        engine.reset()
        latestLocation = nil
        motionClockOffset = nil
        lastMotionTimestamp = nil
        didLogMotionError = false
        coverageAccumulator = nil
        lastCoverageCheckpointAt = nil
        ViimDiagnostics.log("collision.shadow.stop reason=\(reason.rawValue)")
    }

    private func process(_ motion: CMDeviceMotion) {
        let motionTimestamp = motion.timestamp
        if let lastMotionTimestamp,
           motionTimestamp - lastMotionTimestamp > 1 {
            // Une suspension ou un trou de livraison casse la continuite du
            // signal. Ne jamais confirmer un impact a travers ce trou.
            engine.reset()
            ViimDiagnostics.log("collision.shadow.gap reset=true")
        }
        lastMotionTimestamp = motionTimestamp

        if motionClockOffset == nil {
            motionClockOffset = Date().timeIntervalSinceReferenceDate - motionTimestamp
        }
        guard let motionClockOffset else { return }
        let timestamp = Date(
            timeIntervalSinceReferenceDate: motionClockOffset + motionTimestamp
        )
        flushPendingPersistence(at: timestamp)

        let acceleration = motion.userAcceleration
        let rotation = motion.rotationRate
        let accelerationMagnitude = sqrt(
            acceleration.x * acceleration.x +
                acceleration.y * acceleration.y +
                acceleration.z * acceleration.z
        )
        let rotationMagnitude = sqrt(
            rotation.x * rotation.x +
                rotation.y * rotation.y +
                rotation.z * rotation.z
        )

        let location = latestLocation
        let hasReportedSpeed = location.map { $0.speed >= 0 && $0.speedAccuracy >= 0 } == true
        let frame = CollisionSensorFrame(
            timestamp: timestamp,
            userAccelerationMagnitudeG: accelerationMagnitude,
            rotationRateMagnitude: rotationMagnitude,
            gpsSpeedKmh: hasReportedSpeed ? location.map { $0.speed * 3.6 } : nil,
            gpsSpeedAccuracyKmh: hasReportedSpeed ? location.map { $0.speedAccuracy * 3.6 } : nil,
            gpsTimestamp: hasReportedSpeed ? location?.timestamp : nil
        )
        let hasQualifiedGPS = CollisionDetectionPolicy.shadowV2
            .qualifiedSpeed(from: frame) != nil
        let coverageObservedGap = coverageAccumulator?.ingest(
            frame: frame,
            hasQualifiedGPS: hasQualifiedGPS
        ) ?? false
        checkpointCoverage(at: timestamp, force: coverageObservedGap)

        guard let rawCandidate = engine.ingest(frame),
              let activeTripID = activeTripContext?.id,
              let vehicleType else { return }
        let candidate = rawCandidate.contextualized(
            tripID: activeTripID,
            vehicleType: vehicleType
        )
        coverageAccumulator?.noteCandidate(at: timestamp)
        checkpointCoverage(at: timestamp, force: true)
        guard candidatesAwaitingPersistence.count < Self.maximumPendingPersistenceCandidates else {
            ViimDiagnostics.log("collision.shadow.persistenceQueue.full candidateDropped=true alerts=false")
            return
        }
        candidatesAwaitingPersistence.append(candidate)
        flushPendingPersistence(at: timestamp, force: true)
    }

    private func flushPendingPersistence(at timestamp: Date, force: Bool = false) {
        guard !candidatesAwaitingPersistence.isEmpty else {
            lastPersistenceRetryAt = nil
            return
        }
        if !force,
           let lastPersistenceRetryAt,
           timestamp.timeIntervalSince(lastPersistenceRetryAt) < Self.persistenceRetryInterval {
            return
        }
        lastPersistenceRetryAt = timestamp

        while let candidate = candidatesAwaitingPersistence.first {
            do {
                try journal.append(candidate)
                candidatesAwaitingPersistence.removeFirst()
                ViimDiagnostics.log(
                    String(
                        format: "collision.shadow.candidate algorithm=%@ peakG=%.2f speedLossKmh=%.1f persisted=true alerts=false",
                        candidate.algorithmVersion,
                        candidate.peakUserAccelerationG,
                        candidate.speedLossKmh
                    )
                )
            } catch {
                let nsError = error as NSError
                ViimDiagnostics.log(
                    "collision.shadow.candidate persisted=false queued=true errorDomain=\(nsError.domain) errorCode=\(nsError.code) alerts=false"
                )
                return
            }
        }
        lastPersistenceRetryAt = nil
    }

    private func checkpointCoverage(at timestamp: Date, force: Bool = false) {
        guard var accumulator = coverageAccumulator else {
            flushPendingCoveragePersistence(at: timestamp, force: force)
            return
        }

        let checkpointIsDue = lastCoverageCheckpointAt.map {
            timestamp.timeIntervalSince($0) >= Self.coverageCheckpointInterval
        } ?? true
        guard force || checkpointIsDue else {
            flushPendingCoveragePersistence(at: timestamp)
            return
        }

        accumulator.checkpoint(at: timestamp)
        coverageAccumulator = accumulator
        enqueueCoverageRecord(accumulator.record)
        lastCoverageCheckpointAt = timestamp
        flushPendingCoveragePersistence(at: timestamp, force: force)
    }

    private func enqueueCoverageRecord(_ record: CollisionShadowCoverageRecord) {
        if let index = coverageRecordsAwaitingPersistence.firstIndex(where: { $0.id == record.id }) {
            coverageRecordsAwaitingPersistence[index] = record
            return
        }
        guard coverageRecordsAwaitingPersistence.count < Self.maximumPendingCoverageRecords else {
            ViimDiagnostics.log(
                "collision.shadow.coverageQueue.full sessionDropped=true alerts=false"
            )
            return
        }
        coverageRecordsAwaitingPersistence.append(record)
    }

    private func flushPendingCoveragePersistence(at timestamp: Date, force: Bool = false) {
        guard !coverageRecordsAwaitingPersistence.isEmpty else {
            lastCoveragePersistenceRetryAt = nil
            return
        }
        if !force,
           let lastCoveragePersistenceRetryAt,
           timestamp.timeIntervalSince(lastCoveragePersistenceRetryAt) < Self.persistenceRetryInterval {
            return
        }
        lastCoveragePersistenceRetryAt = timestamp

        while let record = coverageRecordsAwaitingPersistence.first {
            do {
                try coverageJournal.upsert(record)
                coverageRecordsAwaitingPersistence.removeFirst()
                ViimDiagnostics.log(
                    "collision.shadow.coverage checkpoint=true frames=\(record.frameCount) gpsFrames=\(record.qualifiedGPSFrameCount) gaps=\(record.gapCount) ended=\(record.endedAt != nil) alerts=false"
                )
            } catch {
                let nsError = error as NSError
                ViimDiagnostics.log(
                    "collision.shadow.coverage persisted=false queued=true errorDomain=\(nsError.domain) errorCode=\(nsError.code) alerts=false"
                )
                return
            }
        }
        lastCoveragePersistenceRetryAt = nil
    }
}
