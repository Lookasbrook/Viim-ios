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

                if let postSpeed = reliableSpeed(from: frame),
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
              let preImpactSpeed = reliableSpeed(from: frame),
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

    private func reliableSpeed(
        from frame: CollisionSensorFrame
    ) -> (value: Double, accuracy: Double)? {
        guard let speed = frame.gpsSpeedKmh,
              let accuracy = frame.gpsSpeedAccuracyKmh,
              let gpsTimestamp = frame.gpsTimestamp,
              speed.isFinite,
              speed >= 0,
              accuracy.isFinite,
              accuracy >= 0,
              accuracy <= policy.maximumGPSSpeedAccuracyKmh else {
            return nil
        }

        let age = frame.timestamp.timeIntervalSince(gpsTimestamp)
        guard age >= -0.5, age <= policy.maximumGPSAge else {
            return nil
        }
        return (speed, accuracy)
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

/// Collecte locale de calibration uniquement pendant un trajet motorise actif.
/// Ce service ne declenche aucune alerte et ne transmet aucune donnee. Il sert a
/// observer des candidats. Sans couverture de session ni etiquette utilisateur,
/// il ne permet pas encore de mesurer un taux de faux positifs ou de faux negatifs.
final class CollisionShadowMonitor {
    private let motionManager: CMMotionManager
    private let queue: OperationQueue
    private let journal: CollisionShadowJournal
    private var engine = CollisionDetectionEngine()
    private var vehicleType: VehicleType?
    private var activeTripID: UUID?
    private var isLocationCollectionActive = false
    private var isMonitoring = false
    private var latestLocation: CLLocation?
    private var motionClockOffset: TimeInterval?
    private var lastMotionTimestamp: TimeInterval?
    private var didLogMotionError = false
    private var candidatesAwaitingPersistence: [CollisionShadowCandidate] = []
    private var lastPersistenceRetryAt: Date?

    private static let persistenceRetryInterval: TimeInterval = 5
    private static let maximumPendingPersistenceCandidates = 10

    init(
        motionManager: CMMotionManager = CMMotionManager(),
        journal: CollisionShadowJournal = CollisionShadowJournal()
    ) {
        self.motionManager = motionManager
        self.journal = journal
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
                currentTripID: self.activeTripID,
                nextTripID: self.activeTripID,
                currentVehicleType: self.vehicleType,
                nextVehicleType: vehicleType
            ), self.isMonitoring {
                self.stopMonitoring()
            }
            self.vehicleType = vehicleType
            self.reconcileMonitoring()
        }
    }

    func setActiveTrip(id: UUID?) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            if Self.shouldResetMonitoringContext(
                currentTripID: self.activeTripID,
                nextTripID: id,
                currentVehicleType: self.vehicleType,
                nextVehicleType: self.vehicleType
            ), self.isMonitoring {
                // Un impact en attente ne doit jamais traverser deux trajets.
                self.stopMonitoring()
            }
            self.activeTripID = id
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
            self.activeTripID = nil
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
            tripActive: activeTripID != nil,
            vehicleType: vehicleType,
            locationCollectionActive: isLocationCollectionActive,
            deviceMotionAvailable: motionManager.isDeviceMotionAvailable
        )

        if shouldMonitor, !isMonitoring {
            startMonitoring()
        } else if !shouldMonitor, isMonitoring {
            stopMonitoring()
        } else if activeTripID != nil, !motionManager.isDeviceMotionAvailable {
            ViimDiagnostics.log("collision.shadow.unavailable reason=deviceMotion")
        } else if activeTripID != nil, vehicleType == nil {
            ViimDiagnostics.log("collision.shadow.unavailable reason=vehicleProfile")
        } else if activeTripID != nil, !isLocationCollectionActive {
            ViimDiagnostics.log("collision.shadow.unavailable reason=locationCollection")
        }
    }

    private func startMonitoring() {
        engine.reset()
        motionClockOffset = nil
        lastMotionTimestamp = nil
        didLogMotionError = false
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
                    ViimDiagnostics.log("collision.shadow.motionError code=\((error as NSError).code)")
                }
                return
            }
            guard let motion else { return }
            self.process(motion)
        }
    }

    private func stopMonitoring() {
        flushPendingPersistence(at: Date(), force: true)
        motionManager.stopDeviceMotionUpdates()
        isMonitoring = false
        engine.reset()
        latestLocation = nil
        motionClockOffset = nil
        lastMotionTimestamp = nil
        didLogMotionError = false
        ViimDiagnostics.log("collision.shadow.stop")
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

        guard let rawCandidate = engine.ingest(frame),
              let activeTripID,
              let vehicleType else { return }
        let candidate = rawCandidate.contextualized(
            tripID: activeTripID,
            vehicleType: vehicleType
        )
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
}
