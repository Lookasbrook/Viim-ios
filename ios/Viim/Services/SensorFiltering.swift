import Foundation

enum SensorFiltering {
    static func lowPass(raw: Double, previousFiltered: Double, alpha: Double) -> Double {
        alpha * raw + (1 - alpha) * previousFiltered
    }

    static func isGpsConfirmedSpeedChange(from previousKmh: Double, to currentKmh: Double) -> Bool {
        abs(currentKmh - previousKmh) > 5
    }
}
