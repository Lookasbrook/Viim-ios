import SwiftUI

enum VehicleType: String, CaseIterable, Codable, Identifiable {
    case moto
    case voiture
    case velo

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .moto: "vehicle.type.moto"
        case .voiture: "vehicle.type.voiture"
        case .velo: "vehicle.type.velo"
        }
    }

    var fallbackDisplayName: String {
        switch self {
        case .moto: String(localized: "vehicle.type.moto")
        case .voiture: String(localized: "vehicle.type.voiture")
        case .velo: String(localized: "vehicle.type.velo")
        }
    }

    var statusKey: LocalizedStringKey {
        "vehicle.status.trackingActive"
    }

    var symbolName: String {
        switch self {
        case .moto: "motorcycle.fill"
        case .voiture: "car.fill"
        case .velo: "bicycle"
        }
    }

    var tint: Color {
        switch self {
        case .moto: ViimColors.blue
        case .voiture: ViimColors.navy
        case .velo: ViimColors.green
        }
    }

    var lowPassAlpha: Double {
        switch self {
        case .moto: 0.15
        case .voiture: 0.25
        case .velo: 0.20
        }
    }

    var speedLimitKmh: Double? {
        switch self {
        case .moto: 80
        case .voiture: 100
        case .velo: nil
        }
    }
}
