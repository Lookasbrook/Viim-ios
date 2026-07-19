import CoreLocation
import XCTest
@testable import Viim

@MainActor
final class TripManagerTests: XCTestCase {
    func testPersistedTripIsScoredImmediatelyAndNotLearningBlocked() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let store = TripStore(context: persistenceController.container.viewContext)
        let manager = TripManager(store: store)
        let start = Date().addingTimeInterval(-600)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: Date(),
            distanceMeters: 1_200,
            sampleCount: 5
        )

        let outcome = manager.persistCompletedTrip(
            trip,
            samples: samples(start: start),
            vehicleType: .moto
        )

        let savedTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(manager.todayTrips.map(\.id), [trip.id])
        XCTAssertFalse(savedTrip.isCalibration)
        XCTAssertNotNil(savedTrip.score)
        XCTAssertEqual(manager.todaySummary.avgScore, savedTrip.score)
        XCTAssertEqual(outcome, .persisted)
    }

    func testImpossibleGpsJumpIsNotPersistedAndDoesNotIncrementTripCount() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let store = TripStore(context: persistenceController.container.viewContext)
        let manager = TripManager(store: store)
        let start = Date().addingTimeInterval(-600)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: Date(),
            distanceMeters: 12_000,
            sampleCount: 2
        )

        let outcome = manager.persistCompletedTrip(
            trip,
            samples: impossibleJumpSamples(start: start),
            vehicleType: .moto
        )

        XCTAssertTrue(try store.fetchRecentTrips(limit: 1).isEmpty)
        XCTAssertEqual(manager.todaySummary.tripsCount, 0)
        XCTAssertEqual(manager.todaySummary.totalKm, 0)
        XCTAssertNil(manager.todaySummary.avgScore)
        guard case .rejected = outcome else {
            return XCTFail("Expected an explicit rejection outcome")
        }
    }

    func testHistoricalTripIsAvailableInRecentTripsButNotTodayTrips() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let store = TripStore(context: persistenceController.container.viewContext)
        let manager = TripManager(store: store)
        let start = Calendar.current.date(byAdding: .day, value: -2, to: Date())!.addingTimeInterval(-600)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 1_200,
            sampleCount: 5
        )

        XCTAssertEqual(
            manager.persistCompletedTrip(
                trip,
                samples: samples(start: start),
                vehicleType: .moto
            ),
            .persisted
        )

        XCTAssertTrue(manager.todayTrips.isEmpty)
        XCTAssertEqual(manager.recentTrips.map(\.id), [trip.id])
    }

    func testRetryableOutcomeNeverDeletesJournal() {
        XCTAssertFalse(TripPersistenceOutcome.failedRetryable("test").shouldDeleteJournal)
        XCTAssertTrue(TripPersistenceOutcome.persisted.shouldDeleteJournal)
    }

    private func samples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 0, timestamp: start),
            sample(latitude: 12.3734, longitude: -1.5177, speed: 6, timestamp: start.addingTimeInterval(150)),
            sample(latitude: 12.3754, longitude: -1.5157, speed: 8, timestamp: start.addingTimeInterval(300)),
            sample(latitude: 12.3774, longitude: -1.5137, speed: 10, timestamp: start.addingTimeInterval(450)),
            sample(latitude: 12.3794, longitude: -1.5117, speed: 12, timestamp: start.addingTimeInterval(600))
        ]
    }

    private func impossibleJumpSamples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 12, timestamp: start),
            sample(latitude: 12.4714, longitude: -1.5197, speed: 12, timestamp: start.addingTimeInterval(10))
        ]
    }

    private func sample(latitude: Double, longitude: Double, speed: CLLocationSpeed, timestamp: Date) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            speedKmh: speed * 3.6,
            horizontalAccuracy: 5,
            speedAccuracy: 1
        )
    }
}
