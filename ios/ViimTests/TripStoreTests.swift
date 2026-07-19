import CoreLocation
import CoreData
import XCTest
@testable import Viim

final class TripStoreTests: XCTestCase {
    func testCompletedTripIsStoredOfflineAndIncludedInSummary() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let routeSamples = samples(start: trip.startedAt)
        let expectedDistanceMeters = try XCTUnwrap(
            TripMetricsCalculator.distanceMetric(
                samples: routeSamples,
                vehicleType: .moto
            ).value
        )

        try store.insertCompletedTrip(
            trip,
            samples: routeSamples,
            vehicleType: .moto,
            isCalibration: false
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(summary.tripsCount, 1)
        XCTAssertEqual(summary.pendingSyncCount, 1)
        XCTAssertEqual(summary.totalKm, expectedDistanceMeters / 1_000, accuracy: 0.001)
        XCTAssertEqual(summary.totalDurationSec, 600)
        XCTAssertNil(summary.avgScore)
        XCTAssertNil(summary.fuelLiters)
        XCTAssertNil(summary.fuelFCFA)
        XCTAssertFalse(recentTrip.isCalibration)
        XCTAssertFalse(recentTrip.synced)
        XCTAssertEqual(recentTrip.vehicleType, .moto)
        XCTAssertEqual(recentTrip.routePoints.count, 5)
        XCTAssertEqual(recentTrip.qualityConfidence, .reliable)
        XCTAssertEqual(recentTrip.qualityReasonCodes, [.complete])
        XCTAssertEqual(recentTrip.qualityFormulaVersion, TripQualityEngine.formulaVersion)
        XCTAssertEqual(recentTrip.validSegmentCount, 4)
        XCTAssertEqual(recentTrip.rejectedSegmentCount, 0)
        XCTAssertNil(recentTrip.fuelFCFA)

        let qualityEvent = try XCTUnwrap(store.fetchQualityTelemetryEvents(limit: 1).first)
        XCTAssertEqual(qualityEvent.tripId, trip.id)
        XCTAssertEqual(qualityEvent.decisionSource, .liveAccepted)
        XCTAssertEqual(qualityEvent.vehicleType, .moto)
        XCTAssertEqual(qualityEvent.qualityConfidence, .reliable)
        XCTAssertEqual(qualityEvent.qualityReasonCodes, [.complete])
        XCTAssertTrue(qualityEvent.acceptedForStorage)
        XCTAssertTrue(qualityEvent.includedInSummaryAtDecision)
        XCTAssertEqual(qualityEvent.sampleCount, 5)
    }

    func testStoredScoreIsIncludedInSummary() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let scores = TripScores(
            score: 82,
            scoreVitesse: 82,
            scoreFluidite: nil,
            scoreVigilance: nil,
            scoreEco: nil
        )

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .voiture,
            isCalibration: false,
            scores: scores
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(summary.avgScore, 82)
        XCTAssertEqual(recentTrip.score, 82)
        XCTAssertEqual(recentTrip.scoreVitesse, 82)
    }

    func testStoredDistanceUsesFilteredGpsSegmentsInsteadOfReportedAccumulator() throws {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 9_999,
            sampleCount: 5
        )
        let routeSamples = samples(start: start)
        let expectedDistanceMeters = try XCTUnwrap(
            TripMetricsCalculator.distanceMetric(
                samples: routeSamples,
                vehicleType: .moto
            ).value
        )

        try store.insertCompletedTrip(
            trip,
            samples: routeSamples,
            vehicleType: .moto,
            isCalibration: false
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(recentTrip.distanceKm, expectedDistanceMeters / 1_000, accuracy: 0.001)
        XCTAssertEqual(summary.totalKm, expectedDistanceMeters / 1_000, accuracy: 0.001)
        XCTAssertNotEqual(recentTrip.distanceKm, trip.distanceMeters / 1_000)
    }

    func testLegacyFuelEstimateIsRecalculatedOnceFromValidatedDistanceAndVehicleProfile() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let trip = completedTrip(index: 0)
        let routeSamples = samples(start: trip.startedAt)
        let profile = try XCTUnwrap(
            VehicleFuelCatalog.profile(
                vehicleType: .voiture,
                brand: "Toyota",
                model: "Corolla"
            )
        )

        try store.insertCompletedTrip(
            trip,
            samples: routeSamples,
            vehicleType: .voiture,
            isCalibration: false,
            scores: TripScores(
                score: 95,
                scoreVitesse: 95,
                scoreFluidite: nil,
                scoreVigilance: nil,
                scoreEco: nil
            ),
            fuelProfile: profile
        )

        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        let object = try XCTUnwrap(context.fetch(request).first)
        object.setValue(99.0, forKey: "fuelLiters")
        object.setValue("vehicle-fuel-catalog-v3", forKey: "fuelFormulaVersion")
        try context.save()

        XCTAssertEqual(
            try store.recalculateFuelEstimates(fuelProfile: profile, vehicleType: .voiture),
            1
        )

        let repaired = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        XCTAssertEqual(repaired.fuelLiters ?? -1, repaired.distanceKm * 6.8 / 100, accuracy: 0.000_001)
        XCTAssertEqual(object.value(forKey: "fuelFormulaVersion") as? String, VehicleFuelCatalog.formulaVersion)
        XCTAssertEqual(
            try store.recalculateFuelEstimates(fuelProfile: profile, vehicleType: .voiture),
            0
        )
    }

    func testRejectedUnreliableTripDoesNotLeavePartialCoreDataObject() throws {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let trip = CompletedDetectedTrip(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 12_000,
            sampleCount: 2
        )

        XCTAssertThrowsError(
            try store.insertCompletedTrip(
                trip,
                samples: impossibleJumpSamples(start: start),
                vehicleType: .moto,
                isCalibration: false
            )
        )
        XCTAssertEqual(try store.completedTripsCount(), 0)

        let qualityEvent = try XCTUnwrap(store.fetchQualityTelemetryEvents(limit: 1).first)
        XCTAssertEqual(qualityEvent.tripId, trip.id)
        XCTAssertEqual(qualityEvent.decisionSource, .liveRejected)
        XCTAssertEqual(qualityEvent.qualityConfidence, .rejected)
        XCTAssertTrue(qualityEvent.qualityReasonCodes.contains(.gpsInsufficient))
        XCTAssertFalse(qualityEvent.acceptedForStorage)
    }

    func testRecognizedVehicleStoresNavigationBasedFuelConsumption() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)
        let fuelProfile = try XCTUnwrap(
            VehicleFuelCatalog.profile(vehicleType: .voiture, brand: "Toyota", model: "Corolla")
        )
        let routeSamples = samples(start: trip.startedAt)
        let expectedDistanceMeters = try XCTUnwrap(
            TripMetricsCalculator.distanceMetric(
                samples: routeSamples,
                vehicleType: .voiture
            ).value
        )
        let scores = TripScores(
            score: 95,
            scoreVitesse: 95,
            scoreFluidite: nil,
            scoreVigilance: nil,
            scoreEco: nil
        )

        try store.insertCompletedTrip(
            trip,
            samples: routeSamples,
            vehicleType: .voiture,
            isCalibration: false,
            scores: scores,
            fuelProfile: fuelProfile
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        let fuelSettings = FuelSettings(currency: .cad, pricePerLiter: 1.70)
        let fuelMetric = TripMetricsCalculator.fuelCostMetric(
            liters: recentTrip.fuelLiters,
            settings: fuelSettings,
            vehicleType: recentTrip.vehicleType
        )
        let expectedFuelConsumption = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(
                distanceKm: expectedDistanceMeters / 1_000,
                fuelProfile: fuelProfile,
                dynamics: DrivingDynamicsAnalyzer.dynamics(
                    samples: routeSamples,
                    vehicleType: .voiture,
                    distanceKm: expectedDistanceMeters / 1_000
                )
            )
        )

        XCTAssertEqual(recentTrip.distanceKm, expectedDistanceMeters / 1_000, accuracy: 0.000_001)
        XCTAssertEqual(recentTrip.fuelLiters ?? -1, expectedFuelConsumption.liters, accuracy: 0.000_001)
        XCTAssertEqual(summary.fuelLiters ?? -1, expectedFuelConsumption.liters, accuracy: 0.000_001)
        XCTAssertNil(recentTrip.fuelFCFA)
        XCTAssertNil(summary.fuelFCFA)
        XCTAssertEqual(fuelMetric.value, fuelSettings.costMinorUnits(for: expectedFuelConsumption.liters))
        XCTAssertEqual(fuelMetric.confidence, .partial)
        XCTAssertEqual(fuelMetric.reasonCode, .fuelEstimated)
    }

    func testFetchTripsReturnsAllTripsFromStartOfDay() throws {
        let store = makeStore()

        for index in 0..<6 {
            let trip = completedTrip(index: index)
            try store.insertCompletedTrip(
                trip,
                samples: samples(start: trip.startedAt),
                vehicleType: .voiture,
                isCalibration: false
            )
        }

        let allTrips = try store.fetchTrips(since: completedTrip(index: 0).startedAt)
        let recentTrips = try store.fetchRecentTrips(limit: 3, since: completedTrip(index: 0).startedAt)

        XCTAssertEqual(try store.completedTripsCount(), 6)
        XCTAssertEqual(allTrips.count, 6)
        XCTAssertEqual(recentTrips.count, 3)
        XCTAssertEqual(allTrips.filter(\.isCalibration).count, 0)
    }

    func testDuplicateCompletedTripIsIgnored() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .moto,
            isCalibration: false
        )
        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .moto,
            isCalibration: false
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
            sampleCount: 5
        )

        try store.insertCompletedTrip(
            oldTrip,
            samples: samples(start: oldTrip.startedAt),
            vehicleType: .moto,
            isCalibration: false
        )
        try store.insertCompletedTrip(
            todayTrip,
            samples: samples(start: todayTrip.startedAt),
            vehicleType: .moto,
            isCalibration: false
        )

        let todaysTrips = try store.fetchRecentTrips(limit: 3, since: todayTrip.startedAt)

        XCTAssertEqual(todaysTrips.map(\.id), [todayTrip.id])
    }

    func testBicycleTripsHaveExactZeroFuelConsumptionAndCurrencyCost() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .velo,
            isCalibration: false
        )

        let summary = try store.fetchSummary()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(summary.fuelLiters, 0)
        XCTAssertNil(summary.fuelFCFA)
        XCTAssertEqual(recentTrip.fuelLiters, 0)
        XCTAssertNil(recentTrip.fuelFCFA)
        let metric = TripMetricsCalculator.fuelCostMetric(
            liters: recentTrip.fuelLiters,
            settings: FuelSettings(currency: .cad, pricePerLiter: 1.70),
            vehicleType: recentTrip.vehicleType
        )
        XCTAssertEqual(metric.value, 0)
        XCTAssertEqual(metric.confidence, .reliable)
    }

    func testLegacyBicycleTripWithoutStoredFuelDoesNotInventZeroCost() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)

        let object = NSManagedObject(
            entity: try XCTUnwrap(NSEntityDescription.entity(forEntityName: "Trip", in: context)),
            insertInto: context
        )
        object.setValue(UUID(), forKey: "id")
        object.setValue(start, forKey: "startDate")
        object.setValue(start.addingTimeInterval(600), forKey: "endDate")
        object.setValue(1.2, forKey: "distanceKm")
        object.setValue(Int64(600), forKey: "durationSec")
        object.setValue(7.2, forKey: "avgSpeedKmh")
        object.setValue(18.0, forKey: "maxSpeedKmh")
        object.setValue(nil, forKey: "score")
        object.setValue(nil, forKey: "scoreVitesse")
        object.setValue(nil, forKey: "scoreFluidite")
        object.setValue(nil, forKey: "scoreVigilance")
        object.setValue(nil, forKey: "scoreEco")
        object.setValue(nil, forKey: "fuelLiters")
        object.setValue(nil, forKey: "fuelFCFA")
        object.setValue(nil, forKey: "polyline")
        object.setValue(false, forKey: "isCalibration")
        object.setValue(VehicleType.velo.rawValue, forKey: "vehicleType")
        object.setValue("conducteur", forKey: "role")
        object.setValue(false, forKey: "synced")
        object.setValue(Date(), forKey: "createdAt")
        try context.save()

        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertNil(recentTrip.fuelLiters)
        XCTAssertNil(recentTrip.fuelFCFA)
        XCTAssertEqual(recentTrip.qualityConfidence, .needsReview)
        XCTAssertEqual(recentTrip.qualityReasonCodes, [.legacyUnverified])
        XCTAssertNil(TripMetricsCalculator.fuelCostMetric(for: recentTrip).value)
        XCTAssertEqual(TripMetricsCalculator.fuelCostMetric(for: recentTrip).confidence, .needsInput)
    }

    func testRecalculatesLegacyQualityFromStoredPolylineAndCorrectsDistance() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let routeSamples = samples(start: start)
        let expectedDistanceMeters = try XCTUnwrap(
            TripMetricsCalculator.distanceMetric(
                samples: routeSamples,
                vehicleType: .moto
            ).value
        )
        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .moto,
            distanceKm: 9.9,
            routePoints: routePoints(from: routeSamples)
        )

        let updatedCount = try store.recalculateLegacyQualityReports()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        let summary = try store.fetchSummary()

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(recentTrip.qualityConfidence, .reliable)
        XCTAssertEqual(recentTrip.qualityFormulaVersion, TripQualityEngine.formulaVersion)
        XCTAssertEqual(recentTrip.distanceKm, expectedDistanceMeters / 1_000, accuracy: 0.001)
        XCTAssertNotEqual(recentTrip.distanceKm, 9.9)
        XCTAssertEqual(summary.tripsCount, 1)
        XCTAssertEqual(summary.totalKm, expectedDistanceMeters / 1_000, accuracy: 0.001)
    }

    func testRecalculatedLegacyTripWithoutSpeedAccuracyDoesNotStoreZeroMaxSpeed() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let routeSamples = samples(start: start)
        let legacyPolyline = try legacyPolylineDataWithoutSpeedAccuracy(from: routeSamples)

        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .voiture,
            distanceKm: 9.9,
            polylineData: legacyPolyline
        )

        let updatedCount = try store.recalculateLegacyQualityReports()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(
            recentTrip.maxSpeedKmh,
            routeSamples.map(\.speedKmh).max() ?? 0,
            accuracy: 0.01
        )
        XCTAssertNil(TripMetricsCalculator.maxSpeedMetric(for: recentTrip).value)
        XCTAssertNil(recentTrip.scoreVitesse)
    }

    func testRepairsStoredZeroMaxSpeedFromLegacyPolyline() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        let routeSamples = samples(start: start)
        let legacyPolyline = try legacyPolylineDataWithoutSpeedAccuracy(from: routeSamples)

        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .voiture,
            distanceKm: 9.9,
            polylineData: legacyPolyline
        )
        let request = NSFetchRequest<NSManagedObject>(entityName: "Trip")
        let object = try XCTUnwrap(context.fetch(request).first)
        object.setValue(0.0, forKey: "maxSpeedKmh")
        object.setValue(TripQualityEngine.formulaVersion, forKey: "qualityFormulaVersion")
        try context.save()

        let updatedCount = try store.repairStoredMaxSpeedValues()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(
            recentTrip.maxSpeedKmh,
            routeSamples.map(\.speedKmh).max() ?? 0,
            accuracy: 0.01
        )
        XCTAssertNil(recentTrip.scoreVitesse)
        XCTAssertFalse(recentTrip.synced)
    }

    func testSummaryExcludesLegacyTripWithoutAuditableRoute() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .moto,
            distanceKm: 1.2,
            routePoints: []
        )

        XCTAssertEqual(try store.fetchRecentTrips(limit: 1).count, 1)
        XCTAssertEqual(try store.fetchSummary().tripsCount, 0)

        let updatedCount = try store.recalculateLegacyQualityReports()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(recentTrip.qualityConfidence, .needsReview)
        XCTAssertEqual(recentTrip.qualityReasonCodes, [.legacyUnverified])
        XCTAssertEqual(try store.fetchSummary().tripsCount, 0)
    }

    func testRecalculatedRejectedLegacyTripIsExcludedFromSummary() throws {
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        let store = TripStore(context: context)
        let start = Date(timeIntervalSince1970: 1_783_000_000)
        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: .moto,
            distanceKm: 12,
            routePoints: routePoints(from: impossibleLegacyJumpSamples(start: start))
        )

        let updatedCount = try store.recalculateLegacyQualityReports()
        let recentTrip = try XCTUnwrap(store.fetchRecentTrips(limit: 1).first)
        let summary = try store.fetchSummary()

        XCTAssertEqual(updatedCount, 1)
        XCTAssertEqual(recentTrip.qualityConfidence, .rejected)
        XCTAssertTrue(recentTrip.qualityReasonCodes.contains(.impossibleSpeed))
        XCTAssertEqual(summary.tripsCount, 0)
        XCTAssertEqual(summary.totalKm, 0)
    }

    func testQualityLearningProfileEnablesProtectiveModeAfterRepeatedGpsRejections() throws {
        let store = makeStore()

        for _ in 0..<5 {
            try store.recordQualityDecision(
                tripId: nil,
                report: rejectedGpsQualityReport(),
                vehicleType: .moto,
                sampleCount: 5,
                source: .liveRejected,
                acceptedForStorage: false
            )
        }

        let profile = try store.fetchQualityLearningProfile()

        XCTAssertEqual(profile.sampleSize, 5)
        XCTAssertEqual(profile.rejectedCount, 5)
        XCTAssertEqual(profile.signal, .gpsDegraded)
        XCTAssertTrue(profile.isProtectiveModeEnabled)
        XCTAssertEqual(profile.minimumSummaryQualityScore, 85)
        XCTAssertTrue(profile.topReasonCodes.contains(.gpsAccuracyTooLow))
    }

    func testProtectiveLearningExcludesPartialTripsFromReliableSummary() throws {
        let store = makeStore()
        let trip = completedTrip(index: 0)

        try store.insertCompletedTrip(
            trip,
            samples: samples(start: trip.startedAt),
            vehicleType: .moto,
            isCalibration: false,
            qualityReport: partialQualityReport()
        )
        XCTAssertEqual(try store.fetchSummary().tripsCount, 1)

        for _ in 0..<5 {
            try store.recordQualityDecision(
                tripId: nil,
                report: rejectedGpsQualityReport(),
                vehicleType: .moto,
                sampleCount: 5,
                source: .liveRejected,
                acceptedForStorage: false
            )
        }

        let profile = try store.fetchQualityLearningProfile()
        let summary = try store.fetchSummary()

        XCTAssertTrue(profile.isProtectiveModeEnabled)
        XCTAssertEqual(summary.tripsCount, 0)
        XCTAssertEqual(summary.totalKm, 0)
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
            sampleCount: 5
        )
    }

    private func samples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 0, timestamp: start),
            sample(latitude: 12.3734, longitude: -1.5177, speed: 5, timestamp: start.addingTimeInterval(150)),
            sample(latitude: 12.3754, longitude: -1.5157, speed: 6, timestamp: start.addingTimeInterval(300)),
            sample(latitude: 12.3774, longitude: -1.5137, speed: 5, timestamp: start.addingTimeInterval(450)),
            sample(latitude: 12.3794, longitude: -1.5117, speed: 4, timestamp: start.addingTimeInterval(600))
        ]
    }

    private func impossibleJumpSamples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 12, timestamp: start),
            sample(latitude: 12.4714, longitude: -1.5197, speed: 12, timestamp: start.addingTimeInterval(10))
        ]
    }

    private func impossibleLegacyJumpSamples(start: Date) -> [LocationSample] {
        [
            sample(latitude: 12.3714, longitude: -1.5197, speed: 12, timestamp: start),
            sample(latitude: 12.4714, longitude: -1.5197, speed: 12, timestamp: start.addingTimeInterval(10)),
            sample(latitude: 12.4724, longitude: -1.5187, speed: 12, timestamp: start.addingTimeInterval(20)),
            sample(latitude: 12.4734, longitude: -1.5177, speed: 12, timestamp: start.addingTimeInterval(30)),
            sample(latitude: 12.4744, longitude: -1.5167, speed: 12, timestamp: start.addingTimeInterval(40))
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

    private func routePoints(from samples: [LocationSample]) -> [TripRoutePoint] {
        samples.map { sample in
            TripRoutePoint(
                timestamp: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude,
                speedKmh: sample.speedKmh,
                horizontalAccuracy: sample.horizontalAccuracy,
                speedAccuracy: sample.speedAccuracy
            )
        }
    }

    private func partialQualityReport() -> TripQualityReport {
        TripQualityReport(
            score: 70,
            confidence: .partial,
            reasonCodes: [.gpsAccuracyTooLow],
            activeDurationSec: 600,
            stationaryTailSec: 0,
            gpsAccuracyAvg: 45,
            gpsAccuracyP95: 95,
            rejectedSegmentCount: 0,
            validSegmentCount: 4,
            maxSampleGapSec: 150,
            p95SampleGapSec: 150,
            coverageRatio: 1,
            burstCount: 1,
            motionAgreementRate: nil,
            formulaVersion: TripQualityEngine.formulaVersion
        )
    }

    private func rejectedGpsQualityReport() -> TripQualityReport {
        TripQualityReport(
            score: 0,
            confidence: .rejected,
            reasonCodes: [.gpsAccuracyTooLow, .gpsInsufficient],
            activeDurationSec: 600,
            stationaryTailSec: 0,
            gpsAccuracyAvg: 120,
            gpsAccuracyP95: 150,
            rejectedSegmentCount: 0,
            validSegmentCount: 0,
            maxSampleGapSec: 0,
            p95SampleGapSec: 0,
            coverageRatio: 0,
            burstCount: 0,
            motionAgreementRate: nil,
            formulaVersion: TripQualityEngine.formulaVersion
        )
    }

    private func insertLegacyTrip(
        context: NSManagedObjectContext,
        start: Date,
        vehicleType: VehicleType,
        distanceKm: Double,
        routePoints: [TripRoutePoint]
    ) throws {
        let polyline = routePoints.isEmpty ? nil : try JSONEncoder().encode(routePoints)
        try insertLegacyTrip(
            context: context,
            start: start,
            vehicleType: vehicleType,
            distanceKm: distanceKm,
            polylineData: polyline
        )
    }

    private func insertLegacyTrip(
        context: NSManagedObjectContext,
        start: Date,
        vehicleType: VehicleType,
        distanceKm: Double,
        polylineData: Data?
    ) throws {
        let object = NSManagedObject(
            entity: try XCTUnwrap(NSEntityDescription.entity(forEntityName: "Trip", in: context)),
            insertInto: context
        )
        object.setValue(UUID(), forKey: "id")
        object.setValue(start, forKey: "startDate")
        object.setValue(start.addingTimeInterval(600), forKey: "endDate")
        object.setValue(distanceKm, forKey: "distanceKm")
        object.setValue(Int64(600), forKey: "durationSec")
        object.setValue(distanceKm / (600.0 / 3_600), forKey: "avgSpeedKmh")
        object.setValue(18.0, forKey: "maxSpeedKmh")
        object.setValue(nil, forKey: "score")
        object.setValue(nil, forKey: "scoreVitesse")
        object.setValue(nil, forKey: "scoreFluidite")
        object.setValue(nil, forKey: "scoreVigilance")
        object.setValue(nil, forKey: "scoreEco")
        object.setValue(nil, forKey: "fuelLiters")
        object.setValue(nil, forKey: "fuelFCFA")
        object.setValue(polylineData, forKey: "polyline")
        object.setValue(Int64(0), forKey: "qualityScore")
        object.setValue(TripQualityConfidence.needsReview.rawValue, forKey: "qualityConfidence")
        object.setValue(TripQualityReasonCode.legacyUnverified.rawValue, forKey: "qualityReasonCodes")
        object.setValue(Int64(0), forKey: "activeDurationSec")
        object.setValue(Int64(0), forKey: "stationaryTailSec")
        object.setValue(-1.0, forKey: "gpsAccuracyAvg")
        object.setValue(-1.0, forKey: "gpsAccuracyP95")
        object.setValue(Int64(0), forKey: "rejectedSegmentCount")
        object.setValue(Int64(0), forKey: "validSegmentCount")
        object.setValue(nil, forKey: "motionAgreementRate")
        object.setValue(TripQualityReport.legacyUnverified.formulaVersion, forKey: "qualityFormulaVersion")
        object.setValue(false, forKey: "isCalibration")
        object.setValue(vehicleType.rawValue, forKey: "vehicleType")
        object.setValue("conducteur", forKey: "role")
        object.setValue(false, forKey: "synced")
        object.setValue(Date(), forKey: "createdAt")
        try context.save()
    }

    private func legacyPolylineDataWithoutSpeedAccuracy(from samples: [LocationSample]) throws -> Data {
        let points = samples.map { sample in
            [
                "timestamp": sample.timestamp.timeIntervalSinceReferenceDate,
                "latitude": sample.latitude,
                "longitude": sample.longitude,
                "speedKmh": sample.speedKmh,
                "horizontalAccuracy": sample.horizontalAccuracy
            ]
        }
        return try JSONSerialization.data(withJSONObject: points)
    }
}
