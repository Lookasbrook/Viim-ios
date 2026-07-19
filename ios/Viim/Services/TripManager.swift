import Foundation

enum TripPersistenceOutcome: Equatable {
    case persisted
    case duplicate
    case rejected(String)
    case failedRetryable(String)

    var status: String {
        switch self {
        case .persisted: "persisted"
        case .duplicate: "duplicate"
        case .rejected: "rejected"
        case .failedRetryable: "failedRetryable"
        }
    }

    var reason: String {
        switch self {
        case .persisted, .duplicate: "none"
        case .rejected(let reason), .failedRetryable(let reason): reason
        }
    }

    var shouldDeleteJournal: Bool {
        switch self {
        case .persisted, .duplicate, .rejected: true
        case .failedRetryable: false
        }
    }
}

@MainActor
final class TripManager: ObservableObject {
    @Published private(set) var todayTrips: [TripRecord] = []
    @Published private(set) var recentTrips: [TripRecord] = []
    @Published private(set) var todaySummary: DrivingSummary = .empty
    @Published private(set) var last30DaysSummary: DrivingSummary = .empty
    @Published private(set) var hasPersistenceError = false
    @Published private(set) var collisionDetectionEnabled = false
    @Published private(set) var lastPersistenceOutcome: TripPersistenceOutcome?

    private let store: TripStore

    init(store: TripStore) {
        self.store = store
        recalculateHistoricalQualityReports()
        repairStoredMaxSpeedValues()
        refresh()
    }

    func refresh() {
        do {
            todayTrips = try store.fetchTrips(
                since: Calendar.current.startOfDay(for: Date())
            )
            recentTrips = try store.fetchTrips()
            todaySummary = try store.fetchTodaySummary()
            last30DaysSummary = try store.fetchLast30DaysSummary()
            hasPersistenceError = false
        } catch {
            hasPersistenceError = true
        }
    }

    private func recalculateHistoricalQualityReports() {
        do {
            let updatedCount = try store.recalculateLegacyQualityReports()
            if updatedCount > 0 {
                ViimDiagnostics.log("trip.quality.recalculated count=\(updatedCount)")
            }
        } catch {
            hasPersistenceError = true
            ViimDiagnostics.log("trip.quality.recalculation.failed")
        }
    }

    private func repairStoredMaxSpeedValues() {
        do {
            let updatedCount = try store.repairStoredMaxSpeedValues()
            if updatedCount > 0 {
                ViimDiagnostics.log("trip.maxSpeed.repaired count=\(updatedCount)")
            }
        } catch {
            hasPersistenceError = true
            ViimDiagnostics.log("trip.maxSpeed.repair.failed")
        }
    }

    /// Kilometrage courant du vehicule : base declaree a l'inscription (ou
    /// re-declaree dans le profil) + km des trajets valides depuis cette date.
    func currentOdometerKm(profile: UserProfile?) -> Double? {
        guard let profile, let baselineKm = profile.odometerBaselineKm else {
            return nil
        }

        let summary = try? store.fetchSummary(since: profile.odometerBaselineDate)
        return baselineKm + (summary?.totalKm ?? 0)
    }

    @discardableResult
    func persistCompletedTrip(
        _ completedTrip: CompletedDetectedTrip,
        samples: [LocationSample],
        vehicleType: VehicleType,
        fuelProfile: VehicleFuelProfile? = nil,
        fuelSettings: FuelSettings? = nil
    ) -> TripPersistenceOutcome {
        do {
            guard !store.tripExists(id: completedTrip.id) else {
                refresh()
                lastPersistenceOutcome = .duplicate
                return .duplicate
            }

            let qualityReport = TripQualityEngine.report(
                completedTrip: completedTrip,
                samples: samples,
                vehicleType: vehicleType
            )

            let persistability = TripMetricsCalculator.persistabilityMetric(
                completedTrip: completedTrip,
                samples: samples,
                vehicleType: vehicleType
            )
            guard persistability.value == true else {
                ViimDiagnostics.log("trip.persist.skipped reason=\(persistability.reasonCode.rawValue)")
                try store.recordQualityDecision(
                    tripId: completedTrip.id,
                    report: qualityReport,
                    vehicleType: vehicleType,
                    sampleCount: samples.count,
                    source: .liveRejected,
                    acceptedForStorage: false
                )
                refresh()
                let outcome = TripPersistenceOutcome.rejected(persistability.reasonCode.rawValue)
                lastPersistenceOutcome = outcome
                return outcome
            }

            guard qualityReport.shouldPersist else {
                let reasonCodes = qualityReport.reasonCodes.map(\.rawValue).joined(separator: ",")
                ViimDiagnostics.log("trip.persist.skipped quality=\(qualityReport.confidence.rawValue) reasons=\(reasonCodes)")
                try store.recordQualityDecision(
                    tripId: completedTrip.id,
                    report: qualityReport,
                    vehicleType: vehicleType,
                    sampleCount: samples.count,
                    source: .liveRejected,
                    acceptedForStorage: false
                )
                refresh()
                let outcome = TripPersistenceOutcome.rejected(reasonCodes)
                lastPersistenceOutcome = outcome
                return outcome
            }

            let scores = ScoreEngine.scores(
                for: completedTrip,
                samples: samples,
                vehicleType: vehicleType
            )
            try store.insertCompletedTrip(
                completedTrip,
                samples: samples,
                vehicleType: vehicleType,
                isCalibration: false,
                scores: scores,
                fuelProfile: fuelProfile,
                fuelSettings: fuelSettings,
                qualityReport: qualityReport
            )
            ViimDiagnostics.log("trip.persisted distanceMeters=\(Int(completedTrip.distanceMeters)) samples=\(completedTrip.sampleCount) score=\(scores.score ?? -1) quality=\(qualityReport.score)")
            refresh()
            lastPersistenceOutcome = .persisted
            return .persisted
        } catch {
            hasPersistenceError = true
            ViimDiagnostics.log("trip.persist.failed")
            let outcome = TripPersistenceOutcome.failedRetryable("coreDataSave")
            lastPersistenceOutcome = outcome
            return outcome
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

    static func speedText(_ metric: ReliableMetric<Double>) -> String {
        guard let value = metric.value else {
            return NSLocalizedString("format.score.empty", comment: "")
        }

        return speedText(kmh: value)
    }

    static func scoreText(_ score: Int?) -> String {
        score.map(String.init) ?? NSLocalizedString("format.score.empty", comment: "")
    }

    static func scoreText(_ metric: ReliableMetric<Int>) -> String {
        guard let value = metric.value else {
            return NSLocalizedString("format.score.empty", comment: "")
        }

        return String(value)
    }

    static func fcfaText(_ amount: Int?) -> String {
        guard let amount else {
            return NSLocalizedString("format.money.unavailable", comment: "")
        }

        let formattedAmount = amount.formatted(.number.grouping(.automatic).locale(Locale(identifier: "fr_BF")))
        return String.localizedStringWithFormat(
            NSLocalizedString("format.money.fcfa", comment: ""),
            formattedAmount
        )
    }

    static func fcfaText(_ metric: ReliableMetric<Int>) -> String {
        guard let amount = metric.value else {
            return NSLocalizedString("format.money.unavailable", comment: "")
        }

        return fcfaText(amount)
    }

    static func moneyText(
        _ metric: ReliableMetric<Int>,
        currency: SupportedCurrency,
        locale: Locale = .current
    ) -> String {
        guard let minorUnits = metric.value else {
            return NSLocalizedString("format.money.unavailable", comment: "")
        }

        let majorUnits = Double(minorUnits) / currency.minorUnitScale
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currencyISOCode
        formatter.currencyCode = currency.rawValue
        formatter.minimumFractionDigits = currency.fractionDigits
        formatter.maximumFractionDigits = currency.fractionDigits
        return formatter.string(from: NSNumber(value: majorUnits)) ?? "\(currency.rawValue) \(majorUnits)"
    }

    static func routePointsText(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("format.route.points", comment: ""),
            count
        )
    }

    static func coordinatesText(latitude: Double, longitude: Double) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("format.coordinates", comment: ""),
            latitude,
            longitude
        )
    }

    static func tripDateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).hour().minute().locale(.current))
    }
}
