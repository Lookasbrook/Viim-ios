import SwiftUI

struct AccueilView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var motionActivityService: MotionActivityService
    @EnvironmentObject private var tripManager: TripManager

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HomeHero(firstName: onboardingStore.profile?.firstName)

                VehicleTrackingCard(
                    profile: onboardingStore.profile,
                    statusKey: tripDetectionDetailKey,
                    statusStyle: tripDetectionStyle
                )

                AutoDetectionStatusCard(
                    authorizationState: locationService.authorizationState,
                    movementPhase: motionActivityService.phase,
                    isMonitoring: locationService.isMonitoring,
                    isPassiveWakeupMonitoring: locationService.isPassiveWakeupMonitoring,
                    tripPhase: locationService.tripPhase,
                    speedKmh: locationService.currentSpeedKmh
                )

                if locationService.activeTrip != nil || locationService.tripPhase == .starting || locationService.tripPhase == .stopping {
                    ActiveTripStatusCard(
                        activeTrip: locationService.activeTrip,
                        tripPhase: locationService.tripPhase,
                        speedKmh: locationService.currentSpeedKmh
                    )
                }

                DailySummaryCard(
                    summary: tripManager.todaySummary,
                    calibrationTripCount: tripManager.calibrationTripCount,
                    hasPersistenceError: tripManager.hasPersistenceError
                )

                ViimCard {
                    VStack(spacing: 0) {
                        HomeStatusRow(
                            icon: "location.fill",
                            titleKey: "home.status.tripDetection",
                            detailKey: tripDetectionDetailKey,
                            tint: locationService.tripPhase.tint
                        )
                        HomeStatusRow(
                            icon: "exclamationmark.triangle.fill",
                            titleKey: "home.status.collisionDetection",
                            detailKey: "status.enabled",
                            tint: ViimColors.success
                        )
                        HomeStatusRow(
                            icon: "person.2.fill",
                            titleKey: "home.status.familyAlert",
                            detailKey: "home.status.familyAlert.empty",
                            tint: ViimColors.blue
                        )
                        HomeStatusRow(
                            icon: "wifi",
                            titleKey: "home.status.network",
                            detailKey: "status.offlineReady",
                            tint: ViimColors.warning,
                            showsDivider: false
                        )
                    }
                }

                Text("home.todayTrips.title")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ViimColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                    .padding(.top, 2)

                if tripManager.todayTrips.isEmpty {
                    RecentTripPlaceholderCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(tripManager.todayTrips) { trip in
                            RecentTripCard(trip: trip)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .background(ViimColors.background.ignoresSafeArea())
    }

    private var tripDetectionDetailKey: LocalizedStringKey {
        guard locationService.authorizationState.canTrackLocation else {
            return locationService.authorizationState.statusKey
        }
        if !locationService.isMonitoring, locationService.isPassiveWakeupMonitoring {
            return "home.monitoring.status.passiveWakeup"
        }
        return locationService.isMonitoring ? locationService.tripPhase.statusKey : motionActivityService.phase.statusKey
    }

    private var tripDetectionStyle: ViimChip.Style {
        guard locationService.authorizationState.canTrackLocation else {
            return locationService.authorizationState == .denied ? .danger : .warning
        }
        if locationService.isPassiveWakeupMonitoring {
            return .success
        }
        return locationService.isMonitoring ? .success : .warning
    }
}

private struct HomeHero: View {
    let firstName: String?

    var body: some View {
        VStack(spacing: 4) {
            ViimBrandMark()
                .padding(.top, 12)
            Text("home.greeting")
                .font(.subheadline)
                .foregroundStyle(ViimColors.muted)
                .padding(.top, 2)
            Text(displayName)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(ViimColors.navy)
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.caption)
                .foregroundStyle(ViimColors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xD7E5F0), ViimColors.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var displayName: String {
        let trimmed = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(localized: "home.greeting.defaultName") : trimmed
    }
}

private struct VehicleTrackingCard: View {
    let profile: UserProfile?
    let statusKey: LocalizedStringKey
    let statusStyle: ViimChip.Style

    var body: some View {
        ViimCard {
            HStack(spacing: 12) {
                VehiclePhotoThumbnail(profile: profile)
                    .frame(width: 112, height: 84)

                VStack(alignment: .leading, spacing: 3) {
                    Text(vehicleName)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(ViimColors.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if let vehicleYear {
                        Text(vehicleYear)
                            .font(.caption)
                            .foregroundStyle(ViimColors.muted)
                    }

                    ViimChip(titleKey: statusKey, style: statusStyle)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var vehicleName: String {
        guard let profile else {
            return String(localized: "home.vehicle.empty").uppercased()
        }
        let parts = [profile.vehicleBrand, profile.vehicleModel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (parts.isEmpty ? profile.vehicleType.fallbackDisplayName : parts.joined(separator: " ")).uppercased()
    }

    private var vehicleYear: String? {
        guard let year = profile?.vehicleYear, !year.isEmpty else {
            return nil
        }
        return year
    }
}

private struct VehiclePhotoThumbnail: View {
    let profile: UserProfile?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let resolution = VehiclePhotoCatalog.resolve(for: profile) {
                Image(resolution.assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 112, height: 84)
                    .clipped()

                LinearGradient(
                    colors: [.clear, ViimColors.text.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color(hex: 0xEDF3F8)
                VehicleIllustration(type: vehicleType, width: 102)
                    .frame(width: 102, height: 62)
            }

            Image(systemName: vehicleType.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(vehicleType.tint)
                .clipShape(Circle())
                .padding(7)
        }
        .frame(width: 112, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: ViimColors.text.opacity(0.12), radius: 6, x: 0, y: 3)
        .accessibilityHidden(true)
    }

    private var vehicleType: VehicleType {
        profile?.vehicleType ?? .moto
    }
}

private struct AutoDetectionStatusCard: View {
    let authorizationState: LocationAuthorizationState
    let movementPhase: MovementDetectionPhase
    let isMonitoring: Bool
    let isPassiveWakeupMonitoring: Bool
    let tripPhase: TripDetectionPhase
    let speedKmh: Double

    var body: some View {
        ViimCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "location.viewfinder")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("home.monitoring.title")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ViimColors.text)
                        Text(detailKey)
                            .font(.caption)
                            .foregroundStyle(ViimColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(DrivingValueFormatter.speedText(kmh: speedKmh))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }

                HStack(spacing: 7) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                    Text(statusKey)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var tint: Color {
        if !authorizationState.canTrackLocation {
            return authorizationState == .denied ? ViimColors.danger : ViimColors.warning
        }
        if isPassiveWakeupMonitoring {
            return ViimColors.success
        }
        return isMonitoring ? ViimColors.success : movementPhase.tint
    }

    private var detailKey: LocalizedStringKey {
        guard authorizationState.canTrackLocation else {
            return authorizationState == .denied ? "home.monitoring.denied.detail" : "home.monitoring.permission.detail"
        }
        if !isMonitoring, isPassiveWakeupMonitoring {
            return "home.monitoring.passive.detail"
        }
        return isMonitoring ? tripPhase.statusKey : movementPhase.detailKey
    }

    private var statusKey: LocalizedStringKey {
        guard authorizationState.canTrackLocation else {
            return "home.monitoring.status.needsPermission"
        }
        if !isMonitoring, isPassiveWakeupMonitoring {
            return "home.monitoring.status.passiveWakeup"
        }
        return isMonitoring ? "home.monitoring.status.gpsConfirming" : movementPhase.statusKey
    }
}

private struct ActiveTripStatusCard: View {
    let activeTrip: ActiveDetectedTrip?
    let tripPhase: TripDetectionPhase
    let speedKmh: Double

    var body: some View {
        ViimCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("home.activeTrip.title")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    Spacer()
                    ViimChip(titleKey: tripPhase.statusKey, style: .success)
                }

                HStack(spacing: 8) {
                    SummaryMetricTile(
                        value: DrivingValueFormatter.distanceText(kilometers: (activeTrip?.distanceMeters ?? 0) / 1_000),
                        labelKey: "home.metric.distance.label",
                        color: ViimColors.blue
                    )
                    SummaryMetricTile(
                        value: DrivingValueFormatter.durationText(seconds: activeDurationSec),
                        labelKey: "home.metric.duration.label",
                        color: ViimColors.navy
                    )
                    SummaryMetricTile(
                        value: DrivingValueFormatter.speedText(kmh: speedKmh),
                        labelKey: "home.metric.speed.label",
                        color: ViimColors.success
                    )
                }
            }
        }
    }

    private var activeDurationSec: Int {
        guard let activeTrip else {
            return 0
        }
        return max(0, Int(Date().timeIntervalSince(activeTrip.startedAt)))
    }
}

private struct DailySummaryCard: View {
    let summary: DrivingSummary
    let calibrationTripCount: Int
    let hasPersistenceError: Bool

    var body: some View {
        ViimCard {
            VStack(spacing: 9) {
                HStack {
                    Text("home.summary.title")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    Spacer()
                    ViimChip(titleKey: summaryStatusKey, style: hasPersistenceError ? .danger : .success)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    SummaryMetricTile(
                        value: DrivingValueFormatter.scoreText(summary.avgScore),
                        labelKey: "home.metric.score.label",
                        color: ViimColors.success,
                        isLarge: true
                    )
                    SummaryMetricTile(
                        value: DrivingValueFormatter.distanceText(kilometers: summary.totalKm),
                        labelKey: "home.metric.distance.label"
                    )
                    SummaryMetricTile(
                        value: String(summary.tripsCount),
                        labelKey: "home.metric.trips.label"
                    )
                    SummaryMetricTile(
                        value: DrivingValueFormatter.durationText(seconds: summary.totalDurationSec),
                        labelKey: "home.metric.duration.label"
                    )
                    SummaryMetricTile(
                        value: String(summary.pendingSyncCount),
                        labelKey: "home.metric.pendingSync.label",
                        color: summary.pendingSyncCount > 0 ? ViimColors.warning : ViimColors.success
                    )
                    SummaryMetricTile(
                        value: String(calibrationTripCount),
                        labelKey: "home.metric.calibration.label",
                        color: calibrationTripCount >= 5 ? ViimColors.success : ViimColors.blue
                    )
                }

                Text(DrivingValueFormatter.calibrationText(completedTrips: calibrationTripCount))
                    .font(.caption)
                    .foregroundStyle(ViimColors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var summaryStatusKey: LocalizedStringKey {
        hasPersistenceError ? "home.summary.persistenceError" : "home.summary.status"
    }
}

private struct SummaryMetricTile: View {
    let value: String
    let labelKey: LocalizedStringKey
    var color: Color = ViimColors.text
    var isLarge = false

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(isLarge ? .system(size: 34, weight: .heavy) : .system(size: 17, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(labelKey)
                .font(.caption2)
                .foregroundStyle(ViimColors.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HomeStatusRow: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color
    var showsDivider = true

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Color(hex: 0xF0F5FA))
                .clipShape(Circle())

            Text(titleKey)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ViimColors.text)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(detailKey)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ViimColors.muted)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color(hex: 0xEDF2F6))
                    .frame(height: 1)
                    .padding(.leading, 45)
            }
        }
    }
}

private struct RecentTripPlaceholderCard: View {
    var body: some View {
        ViimCard {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: 0xE8F0E4))
                    MiniRoute()
                        .stroke(ViimColors.success, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .padding(10)
                }
                .frame(width: 74, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("home.recentTrips.empty.title")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ViimColors.text)
                        Spacer()
                        ViimChip(titleKey: "status.pendingCalibration", style: .neutral)
                    }
                    Text("home.recentTrips.empty.detail")
                        .font(.caption)
                        .foregroundStyle(ViimColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct RecentTripCard: View {
    let trip: TripRecord

    var body: some View {
        ViimCard {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(trip.vehicleType.tint.opacity(0.12))
                    MiniRoute()
                        .stroke(trip.vehicleType.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .padding(10)
                    Image(systemName: trip.vehicleType.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(trip.vehicleType.tint)
                        .clipShape(Circle())
                        .offset(x: 24, y: 18)
                }
                .frame(width: 74, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(DrivingValueFormatter.tripDateText(trip.endDate))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ViimColors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 6)
                        ViimChip(titleKey: statusKey, style: trip.isCalibration ? .neutral : .success)
                    }

                    HStack(spacing: 10) {
                        Label(DrivingValueFormatter.distanceText(kilometers: trip.distanceKm), systemImage: "road.lanes")
                        Label(DrivingValueFormatter.durationText(seconds: trip.durationSec), systemImage: "clock.fill")
                        Label(DrivingValueFormatter.scoreText(trip.score), systemImage: "star.fill")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ViimColors.muted)

                    Text(syncStatusKey)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(trip.synced ? ViimColors.success : ViimColors.warning)
                }
            }
        }
    }

    private var statusKey: LocalizedStringKey {
        trip.isCalibration ? "home.recentTrips.calibration" : "home.recentTrips.saved"
    }

    private var syncStatusKey: LocalizedStringKey {
        trip.synced ? "home.recentTrips.synced" : "home.recentTrips.pendingSync"
    }
}

private struct MiniRoute: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY - rect.height * 0.30))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.36))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private extension TripDetectionPhase {
    var statusKey: LocalizedStringKey {
        switch self {
        case .idle: "location.trip.idle"
        case .starting: "location.trip.starting"
        case .active: "location.trip.active"
        case .stopping: "location.trip.stopping"
        }
    }

    var tint: Color {
        switch self {
        case .idle: ViimColors.blue
        case .starting: ViimColors.green
        case .active: ViimColors.success
        case .stopping: ViimColors.red
        }
    }
}

private extension MovementDetectionPhase {
    var statusKey: LocalizedStringKey {
        switch self {
        case .unavailable: "motion.status.unavailable"
        case .waitingForMovement: "motion.status.waiting"
        case .stationary: "motion.status.stationary"
        case .movementDetected: "motion.status.moving"
        }
    }

    var detailKey: LocalizedStringKey {
        switch self {
        case .unavailable: "motion.detail.unavailable"
        case .waitingForMovement: "motion.detail.waiting"
        case .stationary: "motion.detail.stationary"
        case .movementDetected: "motion.detail.moving"
        }
    }

    var tint: Color {
        switch self {
        case .unavailable: ViimColors.warning
        case .waitingForMovement: ViimColors.blue
        case .stationary: ViimColors.muted
        case .movementDetected: ViimColors.success
        }
    }
}

private extension LocationAuthorizationState {
    var statusKey: LocalizedStringKey {
        switch self {
        case .notDetermined: "location.permission.notDetermined"
        case .restricted: "location.permission.restricted"
        case .denied: "location.permission.denied"
        case .authorizedWhenInUse: "location.permission.whenInUse"
        case .authorizedAlways: "location.permission.always"
        }
    }
}
