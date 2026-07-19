import Foundation
import Network

protocol NetworkPathMonitoring: AnyObject {
    var isOnline: Bool { get }
    var statusUpdate: ((Bool) -> Void)? { get set }

    func start(queue: DispatchQueue)
    func cancel()
}

final class NWPathStatusMonitor: NetworkPathMonitoring {
    private let monitor = NWPathMonitor()

    var statusUpdate: ((Bool) -> Void)?

    var isOnline: Bool {
        monitor.currentPath.status == .satisfied
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.statusUpdate?(path.status == .satisfied)
        }
    }

    func start(queue: DispatchQueue) {
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}

final class NetworkStatusService: ObservableObject {
    @Published private(set) var isOnline: Bool

    private let monitor: NetworkPathMonitoring
    private let delivery: (@escaping () -> Void) -> Void
    private let monitorQueue = DispatchQueue(label: "com.yamstack.viim.network-status")

    init(
        monitor: NetworkPathMonitoring = NWPathStatusMonitor(),
        startsImmediately: Bool = true,
        delivery: @escaping (@escaping () -> Void) -> Void = { block in
            DispatchQueue.main.async(execute: block)
        }
    ) {
        self.monitor = monitor
        self.delivery = delivery
        self.isOnline = monitor.isOnline

        monitor.statusUpdate = { [weak self] isOnline in
            self?.delivery {
                self?.isOnline = isOnline
            }
        }

        if startsImmediately {
            monitor.start(queue: monitorQueue)
        }
    }

    deinit {
        monitor.cancel()
    }
}
