import CoreMotion
import Foundation

enum MovementDetectionPhase: Equatable {
    case unavailable
    case waitingForMovement
    case stationary
    case movementDetected

    var shouldTriggerLocationMonitoring: Bool {
        self == .movementDetected
    }
}

struct MotionActivitySnapshot {
    let isAutomotive: Bool
    let isCycling: Bool
    let isWalking: Bool
    let isRunning: Bool
    let isStationary: Bool
    let confidence: CMMotionActivityConfidence

    init(
        isAutomotive: Bool,
        isCycling: Bool,
        isWalking: Bool,
        isRunning: Bool,
        isStationary: Bool,
        confidence: CMMotionActivityConfidence
    ) {
        self.isAutomotive = isAutomotive
        self.isCycling = isCycling
        self.isWalking = isWalking
        self.isRunning = isRunning
        self.isStationary = isStationary
        self.confidence = confidence
    }

    init(activity: CMMotionActivity) {
        self.init(
            isAutomotive: activity.automotive,
            isCycling: activity.cycling,
            isWalking: activity.walking,
            isRunning: activity.running,
            isStationary: activity.stationary,
            confidence: activity.confidence
        )
    }
}

@MainActor
final class MotionActivityService: ObservableObject {
    private let manager = CMMotionActivityManager()
    private let queue: OperationQueue
    private var vehicleType: VehicleType = .moto

    @Published private(set) var phase: MovementDetectionPhase = .waitingForMovement
    @Published private(set) var isAutoDetectionActive = false

    init() {
        let queue = OperationQueue()
        queue.name = "com.yamstack.viim.motion-activity"
        queue.qualityOfService = .utility
        self.queue = queue
    }

    func startAutoDetection(vehicleType: VehicleType) {
        self.vehicleType = vehicleType

        guard CMMotionActivityManager.isActivityAvailable() else {
            phase = .unavailable
            isAutoDetectionActive = false
            ViimDiagnostics.log("motion.unavailable")
            return
        }

        guard !isAutoDetectionActive else {
            return
        }

        phase = .waitingForMovement
        isAutoDetectionActive = true
        ViimDiagnostics.log("motion.startAutoDetection vehicleType=\(vehicleType.rawValue)")

        manager.startActivityUpdates(to: queue) { [weak self] activity in
            guard let activity else {
                return
            }

            let snapshot = MotionActivitySnapshot(activity: activity)
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.phase = Self.phase(for: snapshot, vehicleType: self.vehicleType)
            }
        }
    }

    func stopAutoDetection() {
        manager.stopActivityUpdates()
        isAutoDetectionActive = false
        phase = .waitingForMovement
        ViimDiagnostics.log("motion.stopAutoDetection")
    }

    nonisolated static func phase(
        for snapshot: MotionActivitySnapshot,
        vehicleType: VehicleType
    ) -> MovementDetectionPhase {
        guard snapshot.confidence != .low else {
            return .waitingForMovement
        }

        if snapshot.isStationary {
            return .stationary
        }

        switch vehicleType {
        case .moto, .voiture:
            return snapshot.isAutomotive ? .movementDetected : .waitingForMovement
        case .velo:
            return snapshot.isCycling ? .movementDetected : .waitingForMovement
        }
    }
}
