import Foundation
import SwiftUI

/// Types d'entretien suivis par Viim. Les intervalles par defaut refletent
/// les preconisations usuelles ajustees aux conditions locales (poussiere,
/// pistes) : l'utilisateur peut les modifier par tache.
enum MaintenanceTaskKind: String, Codable, CaseIterable, Identifiable {
    case oilChange = "oil"
    case brakes = "brakes"
    case tires = "tires"
    case chain = "chain"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .oilChange: "prevention.maintenance.oil"
        case .brakes: "prevention.maintenance.brakes"
        case .tires: "prevention.maintenance.tires"
        case .chain: "prevention.maintenance.chain"
        }
    }

    var symbolName: String {
        switch self {
        case .oilChange: "drop.fill"
        case .brakes: "exclamationmark.brakesignal"
        case .tires: "circle.circle"
        case .chain: "link"
        }
    }

    static func defaults(for vehicleType: VehicleType) -> [MaintenanceTaskKind] {
        switch vehicleType {
        case .moto:
            return [.oilChange, .chain, .brakes, .tires]
        case .voiture:
            return [.oilChange, .brakes, .tires]
        case .velo:
            return [.chain, .brakes, .tires]
        }
    }

    func defaultIntervalKm(for vehicleType: VehicleType) -> Double {
        switch (self, vehicleType) {
        case (.oilChange, .moto): return 3_000
        case (.oilChange, _): return 5_000
        case (.chain, .velo): return 1_500
        case (.chain, _): return 5_000
        case (.brakes, .moto): return 10_000
        case (.brakes, .velo): return 3_000
        case (.brakes, _): return 20_000
        case (.tires, .moto): return 15_000
        case (.tires, .velo): return 4_000
        case (.tires, _): return 40_000
        }
    }
}

struct MaintenanceTaskState: Codable, Equatable, Identifiable {
    let kind: MaintenanceTaskKind
    var intervalKm: Double
    var lastServiceOdometerKm: Double?
    var lastServiceDate: Date?

    var id: String { kind.rawValue }
}

/// Statut calcule d'une tache d'entretien par rapport a l'odometre courant.
enum MaintenanceStatus: Equatable {
    /// Odometre inconnu : le suivi ne peut pas demarrer.
    case needsOdometer
    /// Jamais marquee comme faite : on attend le premier pointage.
    case notTracked
    case ok(remainingKm: Double)
    case dueSoon(remainingKm: Double)
    case overdue(kmOverdue: Double)

    static func compute(
        task: MaintenanceTaskState,
        currentOdometerKm: Double?
    ) -> MaintenanceStatus {
        guard let currentOdometerKm else {
            return .needsOdometer
        }
        guard let lastServiceOdometerKm = task.lastServiceOdometerKm else {
            return .notTracked
        }

        let remaining = lastServiceOdometerKm + task.intervalKm - currentOdometerKm
        if remaining < 0 {
            return .overdue(kmOverdue: -remaining)
        }
        let dueSoonThreshold = max(task.intervalKm * 0.1, 200)
        if remaining <= dueSoonThreshold {
            return .dueSoon(remainingKm: remaining)
        }
        return .ok(remainingKm: remaining)
    }
}

/// Persistance UserDefaults des taches d'entretien, semees selon le type de
/// vehicule et resemees si l'utilisateur change de vehicule.
final class MaintenanceStore: ObservableObject {
    private struct StoredState: Codable, Equatable {
        var vehicleType: VehicleType
        var tasks: [MaintenanceTaskState]
    }

    private static let storageKey = "viim.maintenance.v1"

    @Published private(set) var tasks: [MaintenanceTaskState] = []

    private let userDefaults: UserDefaults
    private var vehicleType: VehicleType?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func configure(vehicleType: VehicleType) {
        self.vehicleType = vehicleType

        if let stored = loadStoredState(), stored.vehicleType == vehicleType {
            tasks = stored.tasks
            return
        }

        let seededTasks = MaintenanceTaskKind.defaults(for: vehicleType).map { kind in
            MaintenanceTaskState(
                kind: kind,
                intervalKm: kind.defaultIntervalKm(for: vehicleType),
                lastServiceOdometerKm: nil,
                lastServiceDate: nil
            )
        }
        tasks = seededTasks
        persist()
    }

    func markServiced(kind: MaintenanceTaskKind, atOdometerKm odometerKm: Double, date: Date = Date()) {
        guard let index = tasks.firstIndex(where: { $0.kind == kind }) else {
            return
        }
        tasks[index].lastServiceOdometerKm = odometerKm
        tasks[index].lastServiceDate = date
        persist()
    }

    func updateInterval(kind: MaintenanceTaskKind, intervalKm: Double) {
        guard let index = tasks.firstIndex(where: { $0.kind == kind }),
              intervalKm.isFinite,
              intervalKm >= 100 else {
            return
        }
        tasks[index].intervalKm = intervalKm
        persist()
    }

    private func loadStoredState() -> StoredState? {
        guard let data = userDefaults.data(forKey: Self.storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredState.self, from: data)
    }

    private func persist() {
        guard let vehicleType else {
            return
        }
        let state = StoredState(vehicleType: vehicleType, tasks: tasks)
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        userDefaults.set(data, forKey: Self.storageKey)
    }
}
