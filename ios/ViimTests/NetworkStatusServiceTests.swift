import Dispatch
import XCTest
@testable import Viim

final class NetworkStatusServiceTests: XCTestCase {
    func testTripDetectionNeverLooksReadyWhenBackgroundPrerequisitesAreMissing() {
        let degradedStates: [LocationCollectionReadiness] = [
            .permissionNotDetermined,
            .permissionDenied,
            .permissionRestricted,
            .foregroundOnly,
            .preciseLocationDisabled,
            .backgroundRefreshDisabled,
            .backgroundRefreshRestricted,
            .passiveWakeupPending
        ]

        for readiness in degradedStates {
            let tone = HomeStatusPresenter.tripDetectionTone(
                readiness: readiness,
                isMonitoring: true,
                isPassiveWakeupMonitoring: true
            )
            XCTAssertNotEqual(tone, .success, "\(readiness) ne doit jamais paraitre pret")
        }
    }

    func testTripDetectionLooksReadyOnlyWhenConfiguredAndActive() {
        XCTAssertEqual(
            HomeStatusPresenter.tripDetectionTone(
                readiness: .ready,
                isMonitoring: false,
                isPassiveWakeupMonitoring: true
            ),
            .success
        )
    }

    func testCollisionStatusIsNotEnabledWhenDetectorIsDisabled() {
        let status = HomeStatusPresenter.collisionDetection(.unavailable)

        XCTAssertEqual(status.detailKey, "home.status.collisionDetection.unavailable")
        XCTAssertEqual(status.tone, .warning)
        XCTAssertNotEqual(status.detailKey, "status.enabled")
    }

    func testNetworkPresentationReflectsOnlineState() {
        let online = HomeStatusPresenter.network(.online)
        let offline = HomeStatusPresenter.network(.offline)

        XCTAssertEqual(online.detailKey, "status.online")
        XCTAssertEqual(online.tone, .success)
        XCTAssertEqual(offline.detailKey, "status.offlineReady")
        XCTAssertEqual(offline.tone, .warning)
    }

    func testProtectionSnapshotNeverCallsForegroundOnlyCollectionReady() {
        let snapshot = ProtectionReadinessSnapshot.evaluate(
            locationReadiness: .foregroundOnly,
            isLocationMonitoring: true,
            isPassiveWakeupMonitoring: true,
            emergencyContacts: [],
            isOnline: true
        )

        XCTAssertEqual(snapshot.tripCollection, .configurationRequired(.foregroundOnly))
        XCTAssertEqual(snapshot.automaticCollision, .unavailable)
        XCTAssertEqual(snapshot.manualAlerts, .notConfigured)
        XCTAssertEqual(snapshot.network, .online)
    }

    func testProtectionSnapshotDistinguishesPassiveStandbyAndActiveCollection() {
        let standby = ProtectionReadinessSnapshot.evaluate(
            locationReadiness: .ready,
            isLocationMonitoring: false,
            isPassiveWakeupMonitoring: true,
            emergencyContacts: [],
            isOnline: false
        )
        let collecting = ProtectionReadinessSnapshot.evaluate(
            locationReadiness: .ready,
            isLocationMonitoring: true,
            isPassiveWakeupMonitoring: true,
            emergencyContacts: [],
            isOnline: false
        )

        XCTAssertEqual(standby.tripCollection, .standby)
        XCTAssertEqual(collecting.tripCollection, .collecting)
        XCTAssertEqual(standby.network, .offline)
    }

    func testConfiguredContactsRemainUnverifiedWithoutProviderReceipt() {
        let snapshot = ProtectionReadinessSnapshot.evaluate(
            locationReadiness: .ready,
            isLocationMonitoring: false,
            isPassiveWakeupMonitoring: true,
            emergencyContacts: [
                EmergencyContact(name: "Awa", phoneNumber: "+22670000000")
            ],
            isOnline: true
        )

        XCTAssertEqual(
            snapshot.manualAlerts,
            .configuredUnverified(contactCount: 1)
        )
        let presentation = HomeStatusPresenter.manualAlerts(snapshot.manualAlerts)
        XCTAssertEqual(presentation.detailKey, "home.status.familyAlert.unverified")
        XCTAssertEqual(presentation.tone, .warning)
    }

    func testOneInvalidContactMakesMixedConfigurationNeedCorrection() {
        let snapshot = ProtectionReadinessSnapshot.evaluate(
            locationReadiness: .ready,
            isLocationMonitoring: false,
            isPassiveWakeupMonitoring: true,
            emergencyContacts: [
                EmergencyContact(name: "Awa", phoneNumber: "+22670000000"),
                EmergencyContact(name: "Numero casse", phoneNumber: "1234")
            ],
            isOnline: true
        )

        XCTAssertEqual(
            snapshot.manualAlerts,
            .needsCorrection(validContactCount: 1, invalidContactCount: 1)
        )
        XCTAssertEqual(
            HomeStatusPresenter.manualAlerts(snapshot.manualAlerts).tone,
            .danger
        )
    }

    func testContactStoreFailureIsNotPresentedAsEmptyConfiguration() {
        let snapshot = ProtectionReadinessSnapshot.evaluate(
            locationReadiness: .ready,
            isLocationMonitoring: false,
            isPassiveWakeupMonitoring: true,
            emergencyContacts: nil,
            isOnline: true
        )

        XCTAssertEqual(snapshot.manualAlerts, .unavailable)
        let presentation = HomeStatusPresenter.manualAlerts(snapshot.manualAlerts)
        XCTAssertEqual(presentation.detailKey, "home.status.familyAlert.unavailable")
        XCTAssertEqual(presentation.tone, .danger)
    }

    func testInitialOfflineStatusReflectsMonitor() {
        let monitor = FakeNetworkPathMonitor(isOnline: false)
        let service = NetworkStatusService(
            monitor: monitor,
            startsImmediately: false,
            delivery: { block in block() }
        )

        XCTAssertFalse(service.isOnline)
    }

    func testStatusUpdatesWhenMonitorChanges() {
        let monitor = FakeNetworkPathMonitor(isOnline: false)
        let service = NetworkStatusService(
            monitor: monitor,
            startsImmediately: false,
            delivery: { block in block() }
        )

        monitor.emit(isOnline: true)

        XCTAssertTrue(service.isOnline)
    }

    func testMonitorStartsWhenRequested() {
        let monitor = FakeNetworkPathMonitor(isOnline: true)
        _ = NetworkStatusService(
            monitor: monitor,
            startsImmediately: true,
            delivery: { block in block() }
        )

        XCTAssertTrue(monitor.didStart)
    }
}

private final class FakeNetworkPathMonitor: NetworkPathMonitoring {
    private(set) var didStart = false
    var isOnline: Bool
    var statusUpdate: ((Bool) -> Void)?

    init(isOnline: Bool) {
        self.isOnline = isOnline
    }

    func start(queue: DispatchQueue) {
        didStart = true
    }

    func cancel() {}

    func emit(isOnline: Bool) {
        self.isOnline = isOnline
        statusUpdate?(isOnline)
    }
}
