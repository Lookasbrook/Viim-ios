import Foundation

enum VehicleType: String, CaseIterable {
    case moto
    case voiture
    case velo

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
