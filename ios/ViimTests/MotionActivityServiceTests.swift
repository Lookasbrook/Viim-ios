import CoreMotion
import XCTest
@testable import Viim

final class MotionActivityServiceTests: XCTestCase {
    func testAutomotiveActivityStartsMotoAndCarTracking() {
        let snapshot = MotionActivitySnapshot(
            isAutomotive: true,
            isCycling: false,
            isWalking: false,
            isRunning: false,
            isStationary: false,
            confidence: .medium
        )

        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .moto), .movementDetected)
        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .voiture), .movementDetected)
    }

    func testCyclingActivityStartsBikeTrackingOnly() {
        let snapshot = MotionActivitySnapshot(
            isAutomotive: false,
            isCycling: true,
            isWalking: false,
            isRunning: false,
            isStationary: false,
            confidence: .high
        )

        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .velo), .movementDetected)
        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .moto), .waitingForMovement)
    }

    func testStationaryActivityDoesNotStartLocationMonitoring() {
        let snapshot = MotionActivitySnapshot(
            isAutomotive: false,
            isCycling: false,
            isWalking: false,
            isRunning: false,
            isStationary: true,
            confidence: .high
        )
        let phase = MotionActivityService.phase(for: snapshot, vehicleType: .voiture)

        XCTAssertEqual(phase, .stationary)
        XCTAssertFalse(phase.shouldTriggerLocationMonitoring)
    }

    func testLowConfidenceMovementWaitsForBetterSignal() {
        let snapshot = MotionActivitySnapshot(
            isAutomotive: true,
            isCycling: false,
            isWalking: false,
            isRunning: false,
            isStationary: false,
            confidence: .low
        )

        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .voiture), .waitingForMovement)
    }
}
