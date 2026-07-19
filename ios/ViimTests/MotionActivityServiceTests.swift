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

    func testCyclingActivityStartsBikeAndMotoTracking() {
        let snapshot = MotionActivitySnapshot(
            isAutomotive: false,
            isCycling: true,
            isWalking: false,
            isRunning: false,
            isStationary: false,
            confidence: .high
        )

        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .velo), .movementDetected)
        // Les motos sont souvent classees cycling par CoreMotion : le GPS doit demarrer.
        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .moto), .movementDetected)
    }

    func testWalkingDoesNotStartMotoTracking() {
        let snapshot = MotionActivitySnapshot(
            isAutomotive: false,
            isCycling: false,
            isWalking: true,
            isRunning: false,
            isStationary: false,
            confidence: .high
        )

        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .moto), .waitingForMovement)
        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .voiture), .waitingForMovement)
    }

    func testUnclassifiedMovementStartsTrackingForAllVehicles() {
        // CoreMotion emet souvent un mouvement "inconnu" (tous flags a false)
        // en debut de trajet moto ou voiture : le GPS doit demarrer, la
        // detection 10 km/h soutenus et le failsafe d'inactivite tranchent.
        let snapshot = MotionActivitySnapshot(
            isAutomotive: false,
            isCycling: false,
            isWalking: false,
            isRunning: false,
            isStationary: false,
            confidence: .medium
        )

        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .moto), .movementDetected)
        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .voiture), .movementDetected)
        XCTAssertEqual(MotionActivityService.phase(for: snapshot, vehicleType: .velo), .movementDetected)
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
