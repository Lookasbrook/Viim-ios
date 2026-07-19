import Dispatch
import XCTest
@testable import Viim

final class NetworkStatusServiceTests: XCTestCase {
    func testCollisionStatusIsNotEnabledWhenDetectorIsDisabled() {
        let status = HomeStatusPresenter.collisionDetection(isEnabled: false)

        XCTAssertEqual(status.detailKey, "home.status.collisionDetection.pending")
        XCTAssertEqual(status.tone, .blue)
        XCTAssertNotEqual(status.detailKey, "status.enabled")
    }

    func testNetworkPresentationReflectsOnlineState() {
        let online = HomeStatusPresenter.network(isOnline: true)
        let offline = HomeStatusPresenter.network(isOnline: false)

        XCTAssertEqual(online.detailKey, "status.online")
        XCTAssertEqual(online.tone, .success)
        XCTAssertEqual(offline.detailKey, "status.offlineReady")
        XCTAssertEqual(offline.tone, .warning)
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
