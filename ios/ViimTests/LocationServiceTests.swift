import CoreLocation
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

    func testSustainedVehicleSpeedBeginsActiveTrip() {
        let service = LocationService()
        let start = Date().addingTimeInterval(-30)

        service.ingestSimulatedLocation(location(latitude: 45.5017, longitude: -73.5673, speed: 9, timestamp: start))
        service.ingestSimulatedLocation(location(latitude: 45.5032, longitude: -73.5657, speed: 9, timestamp: start.addingTimeInterval(8)))
        service.ingestSimulatedLocation(location(latitude: 45.5050, longitude: -73.5639, speed: 9, timestamp: start.addingTimeInterval(16)))

        XCTAssertEqual(service.tripPhase, .active)
        XCTAssertNotNil(service.activeTrip)
        XCTAssertGreaterThan(service.activeTrip?.distanceMeters ?? 0, 0)
    }

    private func location(
        latitude: Double,
        longitude: Double,
        speed: CLLocationSpeed,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 20,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            course: 0,
            speed: speed,
            timestamp: timestamp
        )
    }
}
