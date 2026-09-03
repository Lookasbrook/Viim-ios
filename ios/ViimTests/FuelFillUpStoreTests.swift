import XCTest
@testable import Viim

@MainActor
final class FuelFillUpStoreTests: XCTestCase {
    func testFullTankConfirmationIsMandatoryAndFailureWritesNothing() throws {
        let store = makeStore()
        let profile = makeProfile()

        XCTAssertThrowsError(
            try store.recordFullTank(
                profile: profile,
                odometerKm: 10_000,
                liters: 35,
                fullTankConfirmed: false
            )
        ) { error in
            XCTAssertEqual(error as? FuelFillUpValidationError, .fullTankConfirmationRequired)
        }
        XCTAssertTrue(try store.records(for: profile).isEmpty)
    }

    func testThreeFullTanksCreateTwoIntervalsAndWeightedCalibration() throws {
        let store = makeStore()
        let profile = makeProfile()
        let base = try XCTUnwrap(VehicleFuelCatalog.profile(for: profile))
        let start = Date(timeIntervalSince1970: 1_788_000_000)

        try record(store, profile, 10_000, 35, start)
        XCTAssertNil(try store.calibration(for: profile, baseProfile: base))
        try record(store, profile, 10_300, 21, start.addingTimeInterval(86_400))
        XCTAssertNil(try store.calibration(for: profile, baseProfile: base))
        try record(store, profile, 10_600, 24, start.addingTimeInterval(172_800))

        let calibration = try XCTUnwrap(store.calibration(for: profile, baseProfile: base))
        XCTAssertEqual(calibration.intervalCount, 2)
        XCTAssertEqual(calibration.totalDistanceKm, 600, accuracy: 0.001)
        XCTAssertEqual(calibration.litersPer100Km, 7.5, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(calibration.uncertaintyRatio, 0.18)
        XCTAssertTrue(calibration.sourceIdentifier.hasPrefix("ViimFullTank.v1#"))
    }

    func testAberrantIntervalIsExcludedWithoutPoisoningCalibration() throws {
        let store = makeStore()
        let profile = makeProfile()
        let base = try XCTUnwrap(VehicleFuelCatalog.profile(for: profile))
        let start = Date(timeIntervalSince1970: 1_788_000_000)

        try record(store, profile, 20_000, 30, start)
        try record(store, profile, 20_300, 21, start.addingTimeInterval(86_400))
        try record(store, profile, 20_600, 60, start.addingTimeInterval(172_800))
        try record(store, profile, 20_900, 21, start.addingTimeInterval(259_200))

        let calibration = try XCTUnwrap(store.calibration(for: profile, baseProfile: base))
        XCTAssertEqual(calibration.intervalCount, 2)
        XCTAssertEqual(calibration.litersPer100Km, 7, accuracy: 0.001)
    }

    func testCalibrationNeverCrossesVehicleIdentity() throws {
        let store = makeStore()
        let profile = makeProfile()
        var other = makeProfile()
        other = UserProfile(
            firstName: other.firstName,
            phoneNumber: other.phoneNumber,
            vehicleType: other.vehicleType,
            vehicleBrand: "Honda",
            vehicleModel: "Civic",
            vehicleYear: other.vehicleYear,
            synced: other.synced,
            fuelType: other.fuelType
        )
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        try record(store, profile, 30_000, 30, start)
        try record(store, profile, 30_300, 21, start.addingTimeInterval(86_400))
        try record(store, profile, 30_600, 21, start.addingTimeInterval(172_800))

        XCTAssertNotNil(
            try store.calibration(
                for: profile,
                baseProfile: VehicleFuelCatalog.profile(for: profile)
            )
        )
        XCTAssertNil(
            try store.calibration(
                for: other,
                baseProfile: VehicleFuelCatalog.profile(for: other)
            )
        )
    }

    func testManagerReturnsCalibratedProfileForFutureTripsOnly() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let fillUpStore = FuelFillUpStore(context: context)
        let manager = TripManager(
            store: TripStore(context: context),
            fuelFillUpStore: fillUpStore
        )
        let profile = makeProfile()
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        try record(fillUpStore, profile, 40_000, 30, start)
        try record(fillUpStore, profile, 40_300, 21, start.addingTimeInterval(86_400))
        try record(fillUpStore, profile, 40_600, 24, start.addingTimeInterval(172_800))

        let calibrated = try XCTUnwrap(manager.calibratedFuelProfile(for: profile))
        XCTAssertEqual(calibrated.referenceResolution, .calibratedFullTank)
        XCTAssertEqual(calibrated.litersPer100Km, 7.5, accuracy: 0.001)
        XCTAssertEqual(calibrated.calibrationEvidence?.intervalCount, 2)
        let estimate = try XCTUnwrap(
            VehicleFuelCatalog.estimateConsumption(distanceKm: 100, fuelProfile: calibrated)
        )
        XCTAssertEqual(estimate.baselineLiters, 7.5, accuracy: 0.001)
    }

    func testOdometerMustIncreaseAndInvalidRecordIsNotSaved() throws {
        let store = makeStore()
        let profile = makeProfile()
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        try record(store, profile, 50_000, 30, start)

        XCTAssertThrowsError(
            try store.recordFullTank(
                profile: profile,
                odometerKm: 49_999,
                liters: 20,
                fullTankConfirmed: true,
                occurredAt: start.addingTimeInterval(86_400),
                now: start.addingTimeInterval(86_400)
            )
        ) { error in
            XCTAssertEqual(error as? FuelFillUpValidationError, .nonMonotonicOdometer)
        }
        XCTAssertEqual(try store.records(for: profile).count, 1)
    }

    func testDeletingLatestFillUpRecalculatesWithoutTouchingOlderEvidence() throws {
        let store = makeStore()
        let profile = makeProfile()
        let base = try XCTUnwrap(VehicleFuelCatalog.profile(for: profile))
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        try record(store, profile, 60_000, 30, start)
        try record(store, profile, 60_300, 21, start.addingTimeInterval(86_400))
        try record(store, profile, 60_600, 24, start.addingTimeInterval(172_800))
        XCTAssertNotNil(try store.calibration(for: profile, baseProfile: base))

        let deleted = try XCTUnwrap(store.deleteLatestRecord(for: profile))

        XCTAssertEqual(deleted.odometerKm, 60_600)
        XCTAssertEqual(try store.records(for: profile).map(\.odometerKm), [60_300, 60_000])
        XCTAssertNil(try store.calibration(for: profile, baseProfile: base))
    }

    private func makeStore() -> FuelFillUpStore {
        FuelFillUpStore(context: PersistenceController(inMemory: true).container.viewContext)
    }

    private func makeProfile() -> UserProfile {
        UserProfile(
            firstName: "Test",
            phoneNumber: "+22670000000",
            vehicleType: .voiture,
            vehicleBrand: "Toyota",
            vehicleModel: "Corolla",
            vehicleYear: "2020",
            synced: false,
            fuelType: .gasoline
        )
    }

    private func record(
        _ store: FuelFillUpStore,
        _ profile: UserProfile,
        _ odometerKm: Double,
        _ liters: Double,
        _ date: Date
    ) throws {
        try store.recordFullTank(
            profile: profile,
            odometerKm: odometerKm,
            liters: liters,
            fullTankConfirmed: true,
            occurredAt: date,
            now: date
        )
    }
}
