import Foundation

@MainActor
final class TripManager: ObservableObject {
    @Published private(set) var recentTrips: [TripRecord] = []
    @Published private(set) var todaySummary: DrivingSummary = .empty
    @Published private(set) var last30DaysSummary: DrivingSummary = .empty
    @Published private(set) var calibrationTripCount = 0
    @Published private(set) var hasPersistenceError = false

    private let store: TripStore

    init(store: TripStore) {
        self.store = store
        refresh()
    }

    func refresh() {
        do {
            recentTrips = try store.fetchRecentTrips()
            todaySummary = try store.fetchTodaySummary()
            last30DaysSummary = try store.fetchLast30DaysSummary()
            calibrationTripCount = try store.calibrationTripCount()
            hasPersistenceError = false
        } catch {
            hasPersistenceError = true
        }
    }

    func persistCompletedTrip(
        _ completedTrip: CompletedDetectedTrip,
        samples: [LocationSample],
        vehicleType: VehicleType
    ) {
        do {
            guard !store.tripExists(id: completedTrip.id) else {
                refresh()
                return
            }

            let isCalibration = try store.completedTripsCount() < 5
            try store.insertCompletedTrip(
                completedTrip,
                samples: samples,
                vehicleType: vehicleType,
                isCalibration: isCalibration
            )
            refresh()
        } catch {
            hasPersistenceError = true
        }
    }
}

enum DrivingValueFormatter {
    static func distanceText(kilometers: Double) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("format.distance.km", comment: ""),
            kilometers
        )
    }

    static func durationText(seconds: Int) -> String {
        if seconds >= 3_600 {
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            return String.localizedStringWithFormat(
                NSLocalizedString("format.duration.hoursMinutes", comment: ""),
                hours,
                minutes
            )
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("format.duration.minutes", comment: ""),
            max(0, seconds / 60)
        )
    }

    static func speedText(kmh: Double) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("format.speed.kmh", comment: ""),
            kmh
        )
    }

    static func scoreText(_ score: Int?) -> String {
        score.map(String.init) ?? NSLocalizedString("format.score.empty", comment: "")
    }

    static func calibrationText(completedTrips: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("home.summary.calibration.format", comment: ""),
            min(5, max(0, completedTrips))
        )
    }

    static func tripDateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).hour().minute().locale(Locale(identifier: "fr_BF")))
    }
}
