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
}
