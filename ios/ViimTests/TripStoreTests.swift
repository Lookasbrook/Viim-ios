import CoreLocation
import XCTest
@testable import Viim

final class TripStoreTests: XCTestCase {
    func testCompletedTripIsStoredOfflineAndIncludedInSummary() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .moto,
            isCalibration: true
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(summary.tripsCount, 1)
        XCTAssertEqual(summary.pendingSyncCount, 1)
        XCTAssertEqual(summary.totalKm, 1.2, accuracy: 0.001)
        XCTAssertEqual(summary.totalDurationSec, 600)
        XCTAssertNil(summary.avgScore)
        XCTAssertTrue(recentTrip.isCalibration)
        XCTAssertFalse(recentTrip.synced)
        XCTAssertEqual(recentTrip.vehicleType, .moto)
    }

    func testFirstFiveTripsAreCalibrationThenNextTripIsRegular() throws {
        let store = makeStore()

        for index in 0..<6 {
            let trip = completedTrip(index: index)
            try store.insertCompletedTrip(
                trip,
                samples: samples(start: trip.startedAt),
                vehicleType: .voiture,
                isCalibration: try store.completedTripsCount() < 5
            )
        }

        let recentTrips = try store.fetchRecentTrips(limit: 10)

        XCTAssertEqual(try store.completedTripsCount(), 6)
        XCTAssertEqual(try store.calibrationTripCount(), 5)
        XCTAssertEqual(recentTrips.filter(\.isCalibration).count, 5)
        XCTAssertEqual(recentTrips.filter { !$0.isCalibration }.count, 1)
    }

    func testDuplicateCompletedTripIsIgnored() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .moto,
            isCalibration: true
        )
        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .moto,
            isCalibration: true
        )

        XCTAssertEqual(try store.completedTripsCount(), 1)
    }

    func testRecentTripsCanBeFilteredFromStartOfDay() throws {
        let store = makeStore()
        let todayTrip = completedTrip(index: 1)
        let oldTrip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: todayTrip.startedAt.addingTimeInterval(-86_400),
            endedAt: todayTrip.endedAt.addingTimeInterval(-86_400),
            distanceMeters: 900,
            sampleCount: 2
        )

        try store.insertCompletedTrip(
            oldTrip,
            samples: samples(start: oldTrip.startedAt),
            vehicleType: .moto,
            isCalibration: true
        )
        try store.insertCompletedTrip(
            todayTrip,
            samples: samples(start: todayTrip.startedAt),
            vehicleType: .moto,
            isCalibration: true
        )

        let todaysTrips = try store.fetchRecentTrips(limit: 3, since: todayTrip.startedAt)

        XCTAssertEqual(todaysTrips.map(\.id), [todayTrip.id])
    }

    private func makeStore() -> TripStore {
        let persistenceController = PersistenceController(inMemory: true)
        return TripStore(context: persistenceController.container.viewContext)
    }

    private func completedTrip(index: Int) -> CompletedDetectedTrip {
        let start = Date(timeIntervalSince1970: 1_783_000_000 + Double(index * 1_000))
        return CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 1_200,
            sampleCount: 3
        )
    }

    private func samples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 0, timestamp: start),
            sample(latitude: 12.3754, longitude: -1.5157, speed: 6, timestamp: start.addingTimeInterval(300)),
            sample(latitude: 12.3794, longitude: -1.5117, speed: 4, timestamp: start.addingTimeInterval(600))
        ]
    }

    private func sample(latitude: Double, longitude: Double, speed: CLLocationSpeed, timestamp: Date) -> LocationSample {
        LocationSample(
            location: CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                altitude: 300,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: 0,
                speed: speed,
                timestamp: timestamp
            ),
            speedKmh: speed * 3.6
        )
    }
}
