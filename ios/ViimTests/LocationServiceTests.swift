import XCTest
@testable import Viim

final class LocationServiceTests: XCTestCase {
    func testStationaryFinalizationKeepsShortNoiseOut() {
        let shouldPersist = LocationService.shouldPersistTripAfterStationaryMotion(
            distanceMeters: 40,
            duration: 30
        )

        XCTAssertFalse(shouldPersist)
    }

    func testStationaryFinalizationPersistsMeaningfulDistance() {
        let shouldPersist = LocationService.shouldPersistTripAfterStationaryMotion(
            distanceMeters: 90,
            duration: 30
        )

        XCTAssertTrue(shouldPersist)
    }

    func testStationaryFinalizationPersistsMeaningfulDuration() {
        let shouldPersist = LocationService.shouldPersistTripAfterStationaryMotion(
            distanceMeters: 40,
            duration: 70
        )

        XCTAssertTrue(shouldPersist)
    }

    func testForegroundLocationRequestDoesNotPromotePassiveWakeup() {
        XCTAssertFalse(
            LocationService.shouldEvaluatePassiveWakeupPromotion(
                wasRequestingCurrentLocation: true,
                isMonitoring: false,
                authorizationState: .authorizedAlways
            )
        )
        XCTAssertTrue(
            LocationService.shouldEvaluatePassiveWakeupPromotion(
                wasRequestingCurrentLocation: false,
                isMonitoring: false,
                authorizationState: .authorizedAlways
            )
        )
        XCTAssertFalse(
            LocationService.shouldEvaluatePassiveWakeupPromotion(
                wasRequestingCurrentLocation: false,
                isMonitoring: true,
                authorizationState: .authorizedAlways
            )
        )
    }
}
