import XCTest
@testable import Viim

final class ActiveTripJournalTests: XCTestCase {
    func testCandidateIsPersistedFromFirstSampleAndPromotedWithoutChangingID() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let journal = ActiveTripJournal(context: persistenceController.container.viewContext)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let tripId = UUID()
        let samples = [
            sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start),
            sample(latitude: 12.3754, longitude: -1.5157, speedKmh: 20, timestamp: start.addingTimeInterval(300))
        ]

        try journal.saveCandidate(id: tripId, vehicleType: .voiture, samples: [samples[0]], distanceMeters: 0)
        XCTAssertEqual(try journal.activeDrafts().first?.phase, .candidate)
        XCTAssertEqual(try journal.samples(for: tripId).count, 1)

        let activeTrip = ActiveDetectedTrip(
            id: tripId,
            startedAt: start,
            lastUpdatedAt: samples[1].timestamp,
            lastMovingAt: samples[1].timestamp,
            distanceMeters: 500,
            sampleCount: samples.count
        )
        try journal.startTrip(activeTrip, vehicleType: .voiture, samples: samples)

        let promoted = try XCTUnwrap(journal.activeDrafts().first)
        XCTAssertEqual(promoted.id, tripId)
        XCTAssertEqual(promoted.phase, .active)
        XCTAssertEqual(try journal.samples(for: tripId).count, 2)
    }

    func testJournalStoresDraftAndSamplesWithSpeedAccuracy() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let journal = ActiveTripJournal(context: persistenceController.container.viewContext)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let tripId = UUID()
        var activeTrip = ActiveDetectedTrip(
            id: tripId,
            startedAt: start,
            lastUpdatedAt: start.addingTimeInterval(60),
            lastMovingAt: start.addingTimeInterval(60),
            distanceMeters: 120,
            sampleCount: 2
        )
        let initialSamples = [
            sample(latitude: 12.3714, longitude: -1.5197, speedKmh: 18, timestamp: start),
            sample(latitude: 12.3724, longitude: -1.5187, speedKmh: 20, timestamp: start.addingTimeInterval(60))
        ]

        try journal.startTrip(activeTrip, vehicleType: .moto, samples: initialSamples)
        activeTrip.lastUpdatedAt = start.addingTimeInterval(120)
        activeTrip.lastMovingAt = start.addingTimeInterval(120)
        activeTrip.distanceMeters = 240
        activeTrip.sampleCount = 3
        try journal.appendSample(
            sample(latitude: 12.3734, longitude: -1.5177, speedKmh: 22, timestamp: start.addingTimeInterval(120)),
            to: activeTrip,
            vehicleType: .moto
        )

        let drafts = try journal.activeDrafts()
        let savedSamples = try journal.samples(for: tripId)

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.id, tripId)
        XCTAssertEqual(drafts.first?.sampleCount, 3)
        XCTAssertEqual(drafts.first?.distanceMeters, 240)
        XCTAssertEqual(savedSamples.count, 3)
        XCTAssertEqual(savedSamples.map(\.speedAccuracy), [1, 1, 1])

        try journal.deleteTrip(id: tripId)

        XCTAssertTrue(try journal.activeDrafts().isEmpty)
        XCTAssertTrue(try journal.samples(for: tripId).isEmpty)
    }

    func testRejectedTerminalOutcomeKeepsSamplesForAuditAndRemovesDraft() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let journal = ActiveTripJournal(context: persistenceController.container.viewContext)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let tripId = UUID()
        let samples = [
            sample(latitude: 46.8915, longitude: -71.2137, speedKmh: 30, timestamp: start),
            sample(latitude: 46.8920, longitude: -71.2137, speedKmh: 31, timestamp: start.addingTimeInterval(9))
        ]
        try journal.saveCandidate(id: tripId, vehicleType: .voiture, samples: samples, distanceMeters: 55)

        try journal.finalizeTrip(
            id: tripId,
            status: "rejected",
            reason: "staleCandidate",
            source: "recovery",
            sampleCount: samples.count
        )

        XCTAssertTrue(try journal.activeDrafts().isEmpty)
        let retainedSamples = try journal.samples(for: tripId)
        XCTAssertEqual(retainedSamples.count, samples.count)
        XCTAssertEqual(retainedSamples.map(\.timestamp), samples.map(\.timestamp))
        let outcome = try XCTUnwrap(journal.captureOutcomes().first)
        XCTAssertEqual(outcome.tripId, tripId)
        XCTAssertEqual(outcome.status, "rejected")
        XCTAssertEqual(outcome.reason, "staleCandidate")
        XCTAssertEqual(outcome.sampleCount, 2)
    }

    private func sample(
        latitude: Double,
        longitude: Double,
        speedKmh: Double,
        timestamp: Date
    ) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            speedKmh: speedKmh,
            horizontalAccuracy: 5,
            speedAccuracy: 1
        )
    }
}
