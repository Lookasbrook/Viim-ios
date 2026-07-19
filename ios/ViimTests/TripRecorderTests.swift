import XCTest
@testable import Viim

@MainActor
final class TripRecorderTests: XCTestCase {
    func testRecoverReliableCandidatePersistsAndCleansDraft() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let manager = TripManager(store: store)
        let journal = ActiveTripJournal(context: context)
        let recorder = TripRecorder(journal: journal, tripManager: manager)
        let start = Date().addingTimeInterval(-600)
        let samples = routeSamples(start: start)
        let tripId = UUID()
        try journal.saveCandidate(
            id: tripId,
            vehicleType: .moto,
            samples: samples,
            distanceMeters: 1_200
        )

        recorder.recoverActiveTrips()

        XCTAssertEqual(try store.fetchRecentTrips(limit: 1).first?.id, tripId)
        XCTAssertTrue(try journal.activeDrafts().isEmpty)
    }

    func testRecoverStaleInsufficientCandidateRejectsAndCleansDraft() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let manager = TripManager(store: store)
        let journal = ActiveTripJournal(context: context)
        let recorder = TripRecorder(journal: journal, tripManager: manager)
        let now = Date()
        let sample = routeSamples(start: now.addingTimeInterval(-16 * 60)).first!
        try journal.saveCandidate(id: UUID(), vehicleType: .moto, samples: [sample], distanceMeters: 0)

        recorder.recoverActiveTrips(now: now)

        XCTAssertTrue(try store.fetchRecentTrips(limit: 1).isEmpty)
        XCTAssertTrue(try journal.activeDrafts().isEmpty)
    }

    func testRecoverFreshInsufficientCandidateKeepsDraftForLiveCapture() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let manager = TripManager(store: store)
        let journal = ActiveTripJournal(context: context)
        let recorder = TripRecorder(journal: journal, tripManager: manager)
        let now = Date()
        let tripId = UUID()
        let sample = routeSamples(start: now.addingTimeInterval(-60)).first!
        try journal.saveCandidate(id: tripId, vehicleType: .moto, samples: [sample], distanceMeters: 0)

        recorder.recoverActiveTrips(now: now)

        XCTAssertTrue(try store.fetchRecentTrips(limit: 1).isEmpty)
        XCTAssertEqual(try journal.activeDrafts().map(\.id), [tripId])
        let retainedSamples = try journal.samples(for: tripId)
        XCTAssertEqual(retainedSamples.count, 1)
        XCTAssertEqual(retainedSamples.first?.timestamp, sample.timestamp)
    }

    func testRecoverActiveTripPersistsFromJournalAndCleansDraft() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let manager = TripManager(store: store)
        let journal = ActiveTripJournal(context: context)
        let recorder = TripRecorder(journal: journal, tripManager: manager)
        let start = Date().addingTimeInterval(-600)
        let samples = routeSamples(start: start)
        let tripId = UUID()
        let activeTrip = ActiveDetectedTrip(
            id: tripId,
            startedAt: start,
            lastUpdatedAt: start.addingTimeInterval(600),
            lastMovingAt: start.addingTimeInterval(600),
            distanceMeters: 1_200,
            sampleCount: samples.count
        )
        recorder.configure(
            profile: UserProfile(
                firstName: "Awa",
                phoneNumber: "+22670000000",
                vehicleType: .moto,
                vehicleBrand: "",
                vehicleModel: "",
                vehicleYear: "",
                synced: false
            )
        )
        try journal.startTrip(activeTrip, vehicleType: .moto, samples: samples)

        recorder.recoverActiveTrips()

        let savedTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        XCTAssertEqual(savedTrip.id, tripId)
        XCTAssertEqual(savedTrip.routePoints.count, samples.count)
        XCTAssertEqual(savedTrip.routePoints.map(\.speedAccuracy), Array(repeating: 1, count: samples.count))
        XCTAssertTrue(try journal.activeDrafts().isEmpty)
        XCTAssertTrue(try journal.samples(for: tripId).isEmpty)
        XCTAssertEqual(manager.todayTrips.map(\.id), [tripId])
    }

    func testRecoverBuild8CompressedGpsBurstUsesReceiptTimelineAndPersists() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let manager = TripManager(store: store)
        let journal = ActiveTripJournal(context: context)
        let recorder = TripRecorder(journal: journal, tripManager: manager)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let receivedStart = start.addingTimeInterval(10_000)
        let tripId = UUID()
        let samples = [
            sample(
                latitude: 46.8915,
                longitude: -71.2137,
                speedKmh: 18,
                timestamp: start,
                receivedAt: receivedStart
            ),
            sample(
                latitude: 46.8971,
                longitude: -71.2137,
                speedKmh: 20,
                timestamp: start.addingTimeInterval(2.5),
                receivedAt: receivedStart.addingTimeInterval(180)
            ),
            sample(
                latitude: 46.9027,
                longitude: -71.2137,
                speedKmh: 22,
                timestamp: start.addingTimeInterval(5),
                receivedAt: receivedStart.addingTimeInterval(360)
            ),
            sample(
                latitude: 46.9083,
                longitude: -71.2137,
                speedKmh: 21,
                timestamp: start.addingTimeInterval(7.5),
                receivedAt: receivedStart.addingTimeInterval(540)
            ),
            sample(
                latitude: 46.9140,
                longitude: -71.2137,
                speedKmh: 18,
                timestamp: start.addingTimeInterval(10),
                receivedAt: receivedStart.addingTimeInterval(720)
            )
        ]
        let activeTrip = ActiveDetectedTrip(
            id: tripId,
            startedAt: start,
            lastUpdatedAt: start.addingTimeInterval(10),
            lastMovingAt: start.addingTimeInterval(10),
            distanceMeters: 2_500,
            sampleCount: samples.count
        )
        try journal.startTrip(activeTrip, vehicleType: .voiture, samples: samples)

        recorder.recoverActiveTrips(now: receivedStart.addingTimeInterval(900))

        let savedTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        XCTAssertEqual(savedTrip.id, tripId)
        XCTAssertEqual(savedTrip.durationSec, 720)
        XCTAssertGreaterThan(savedTrip.distanceKm, 2)
        XCTAssertTrue(try journal.activeDrafts().isEmpty)
    }

    private func routeSamples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 0, timestamp: start),
            sample(latitude: 12.3734, longitude: -1.5177, speedKmh: 18, timestamp: start.addingTimeInterval(150)),
            sample(latitude: 12.3754, longitude: -1.5157, speedKmh: 20, timestamp: start.addingTimeInterval(300)),
            sample(latitude: 12.3774, longitude: -1.5137, speedKmh: 22, timestamp: start.addingTimeInterval(450)),
            sample(latitude: 12.3794, longitude: -1.5117, speedKmh: 24, timestamp: start.addingTimeInterval(600))
        ]
    }

    private func sample(
        latitude: Double,
        longitude: Double,
        speedKmh: Double,
        timestamp: Date,
        receivedAt: Date? = nil
    ) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            speedKmh: speedKmh,
            horizontalAccuracy: 5,
            speedAccuracy: 1,
            receivedAt: receivedAt
        )
    }
}
