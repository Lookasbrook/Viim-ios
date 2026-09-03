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

    static let shadowV1 = CollisionDetectionPolicy(
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
    static let algorithmVersion = "collision-shadow-v1-impact-gps-delta"

    private struct PendingImpact {
        let impactAt: Date
        let preImpactSpeedKmh: Double
        var peakUserAccelerationG: Double
        var peakRotationRate: Double
    }

    private let policy: CollisionDetectionPolicy
    private var pendingImpact: PendingImpact?
    private var lastCandidateAt: Date?
    private var lastFrameAt: Date?

    init(policy: CollisionDetectionPolicy = .shadowV1) {
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
                    let speedLoss = pending.preImpactSpeedKmh - postSpeed
                    if speedLoss >= policy.minimumSpeedLossKmh {
                        let candidate = CollisionShadowCandidate(
                            id: UUID(),
                            algorithmVersion: Self.algorithmVersion,
                            impactAt: pending.impactAt,
                            confirmedAt: frame.timestamp,
                            peakUserAccelerationG: pending.peakUserAccelerationG,
                            peakRotationRate: pending.peakRotationRate,
                            preImpactSpeedKmh: pending.preImpactSpeedKmh,
                            postImpactSpeedKmh: postSpeed,
                            speedLossKmh: speedLoss
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
              preImpactSpeed >= policy.minimumPreImpactSpeedKmh else {
            return nil
        }

        pendingImpact = PendingImpact(
            impactAt: frame.timestamp,
            preImpactSpeedKmh: preImpactSpeed,
            peakUserAccelerationG: frame.userAccelerationMagnitudeG,
            peakRotationRate: frame.rotationRateMagnitude
        )
        return nil
    }

    private func reliableSpeed(from frame: CollisionSensorFrame) -> Double? {
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
        return speed
    }
}

final class CollisionShadowJournal {
    static let defaultRetentionLimit = 100

    private let fileURL: URL
    private let retentionLimit: Int

    init(
        fileURL: URL = CollisionShadowJournal.defaultFileURL(),
        retentionLimit: Int = CollisionShadowJournal.defaultRetentionLimit
    ) {
        self.fileURL = fileURL
        self.retentionLimit = max(1, retentionLimit)
    }

    func load() throws -> [CollisionShadowCandidate] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([CollisionShadowCandidate].self, from: data)
    }

    func append(_ candidate: CollisionShadowCandidate) throws {
        var candidates = try load()
        candidates.append(candidate)
        if candidates.count > retentionLimit {
            candidates = Array(candidates.suffix(retentionLimit))
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(candidates)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("ViimCollisionShadow.json")
    }
}

/// Collecte locale de calibration uniquement pendant un trajet motorise actif.
/// Ce service ne declenche aucune alerte et ne transmet aucune donnee. Il sert a
/// mesurer les faux positifs avant d'autoriser une fonction de securite publique.
final class CollisionShadowMonitor {
    private let motionManager: CMMotionManager
    private let queue: OperationQueue
    private let journal: CollisionShadowJournal
    private var engine = CollisionDetectionEngine()
    private var vehicleType: VehicleType = .moto
    private var isTripActive = false
    private var isMonitoring = false
    private var latestLocation: CLLocation?
    private var motionClockOffset: TimeInterval?
    private var lastMotionTimestamp: TimeInterval?
    private var didLogMotionError = false

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
            self.vehicleType = vehicleType
            self.reconcileMonitoring()
        }
    }

    func setTripActive(_ isActive: Bool) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.isTripActive = isActive
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
            self.isTripActive = false
            self.reconcileMonitoring()
        }
    }

    static func shouldMonitor(
        tripActive: Bool,
        vehicleType: VehicleType,
        deviceMotionAvailable: Bool
    ) -> Bool {
        tripActive && vehicleType != .velo && deviceMotionAvailable
    }

    private func reconcileMonitoring() {
        let shouldMonitor = Self.shouldMonitor(
            tripActive: isTripActive,
            vehicleType: vehicleType,
            deviceMotionAvailable: motionManager.isDeviceMotionAvailable
        )

        if shouldMonitor, !isMonitoring {
            startMonitoring()
        } else if !shouldMonitor, isMonitoring {
            stopMonitoring()
        } else if isTripActive, !motionManager.isDeviceMotionAvailable {
            ViimDiagnostics.log("collision.shadow.unavailable reason=deviceMotion")
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

        guard let candidate = engine.ingest(frame) else { return }
        do {
            try journal.append(candidate)
            ViimDiagnostics.log(
                String(
                    format: "collision.shadow.candidate algorithm=%@ peakG=%.2f speedLossKmh=%.1f persisted=true alerts=false",
                    candidate.algorithmVersion,
                    candidate.peakUserAccelerationG,
                    candidate.speedLossKmh
                )
            )
        } catch {
            ViimDiagnostics.log("collision.shadow.candidate persisted=false alerts=false")
        }
    }
}
