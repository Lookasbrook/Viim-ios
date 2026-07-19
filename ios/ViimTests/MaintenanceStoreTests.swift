import XCTest
@testable import Viim

final class MaintenanceStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private let suiteName = "MaintenanceStoreTests"

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    func testConfigureSeedsTasksForVehicleType() {
        let store = MaintenanceStore(userDefaults: userDefaults)
        store.configure(vehicleType: .voiture)

        XCTAssertEqual(store.tasks.map(\.kind), [.oilChange, .brakes, .tires])
        XCTAssertEqual(
            store.tasks.first { $0.kind == .oilChange }?.intervalKm,
            5_000
        )

        let motoStore = MaintenanceStore(userDefaults: userDefaults)
        motoStore.configure(vehicleType: .moto)
        XCTAssertEqual(motoStore.tasks.map(\.kind), [.oilChange, .chain, .brakes, .tires])
        XCTAssertEqual(
            motoStore.tasks.first { $0.kind == .oilChange }?.intervalKm,
            3_000
        )
    }

    func testMarkServicedPersistsAcrossInstances() {
        let store = MaintenanceStore(userDefaults: userDefaults)
        store.configure(vehicleType: .voiture)
        store.markServiced(kind: .oilChange, atOdometerKm: 45_000)

        let reloaded = MaintenanceStore(userDefaults: userDefaults)
        reloaded.configure(vehicleType: .voiture)

        XCTAssertEqual(
            reloaded.tasks.first { $0.kind == .oilChange }?.lastServiceOdometerKm,
            45_000
        )
    }

    func testStatusProgressesFromOkToOverdueWithOdometer() {
        let task = MaintenanceTaskState(
            kind: .oilChange,
            intervalKm: 5_000,
            lastServiceOdometerKm: 45_000,
            lastServiceDate: Date()
        )

        XCTAssertEqual(
            MaintenanceStatus.compute(task: task, currentOdometerKm: 46_000),
            .ok(remainingKm: 4_000)
        )
        XCTAssertEqual(
            MaintenanceStatus.compute(task: task, currentOdometerKm: 49_700),
            .dueSoon(remainingKm: 300)
        )
        XCTAssertEqual(
            MaintenanceStatus.compute(task: task, currentOdometerKm: 51_000),
            .overdue(kmOverdue: 1_000)
        )
    }

    func testStatusRequiresOdometerAndInitialService() {
        let untracked = MaintenanceTaskState(
            kind: .tires,
            intervalKm: 40_000,
            lastServiceOdometerKm: nil,
            lastServiceDate: nil
        )

        XCTAssertEqual(
            MaintenanceStatus.compute(task: untracked, currentOdometerKm: nil),
            .needsOdometer
        )
        XCTAssertEqual(
            MaintenanceStatus.compute(task: untracked, currentOdometerKm: 45_000),
            .notTracked
        )
    }

    func testChangingVehicleTypeReseedsTasks() {
        let store = MaintenanceStore(userDefaults: userDefaults)
        store.configure(vehicleType: .voiture)
        store.markServiced(kind: .oilChange, atOdometerKm: 45_000)

        let switched = MaintenanceStore(userDefaults: userDefaults)
        switched.configure(vehicleType: .moto)

        XCTAssertEqual(switched.tasks.map(\.kind), [.oilChange, .chain, .brakes, .tires])
        XCTAssertNil(switched.tasks.first { $0.kind == .oilChange }?.lastServiceOdometerKm)
    }

    func testUpdateIntervalRejectsAbsurdValues() {
        let store = MaintenanceStore(userDefaults: userDefaults)
        store.configure(vehicleType: .voiture)

        store.updateInterval(kind: .oilChange, intervalKm: 50)
        XCTAssertEqual(store.tasks.first { $0.kind == .oilChange }?.intervalKm, 5_000)

        store.updateInterval(kind: .oilChange, intervalKm: 7_500)
        XCTAssertEqual(store.tasks.first { $0.kind == .oilChange }?.intervalKm, 7_500)
    }
}
