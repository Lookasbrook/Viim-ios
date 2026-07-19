import MapKit
import SwiftUI

struct AccueilView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var motionActivityService: MotionActivityService
    @EnvironmentObject private var networkStatusService: NetworkStatusService
    @EnvironmentObject private var tripManager: TripManager
    @State private var emergencyContact: EmergencyContact?
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HomeHero(firstName: onboardingStore.profile?.firstName)
                        .staggeredAppear(hasAppeared, index: 0)

                    VehicleTrackingCard(
                        profile: onboardingStore.profile,
                        statusKey: tripDetectionDetailKey,
                        statusStyle: tripDetectionStyle
                    )
                    .staggeredAppear(hasAppeared, index: 1)

                    AutoDetectionStatusCard(
                        authorizationState: locationService.authorizationState,
                        movementPhase: motionActivityService.phase,
                        isMonitoring: locationService.isMonitoring,
                        isPassiveWakeupMonitoring: locationService.isPassiveWakeupMonitoring,
                        tripPhase: locationService.tripPhase,
                        speedKmh: locationService.currentSpeedKmh,
                        onEnableBackgroundDetection: {
                            locationService.requestBackgroundAuthorization()
                        }
                    )
                    .staggeredAppear(hasAppeared, index: 2)

                    if let outcome = tripManager.lastPersistenceOutcome {
                        CaptureOutcomeCard(outcome: outcome)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if locationService.activeTrip != nil || locationService.tripPhase == .starting || locationService.tripPhase == .stopping {
                        ActiveTripStatusCard(
                            activeTrip: locationService.activeTrip,
                            tripPhase: locationService.tripPhase,
                            speedKmh: locationService.currentSpeedKmh
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    DailySummaryCard(
                        summary: tripManager.todaySummary,
                        hasPersistenceError: tripManager.hasPersistenceError,
                        fuelSettings: onboardingStore.fuelSettings
                    )
                    .staggeredAppear(hasAppeared, index: 3)

                    statusCard
                        .staggeredAppear(hasAppeared, index: 4)

                    HStack {
                        Text("home.recentTrips.title")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(ViimColors.text)
                        Spacer()
                        if !tripManager.recentTrips.isEmpty {
                            NavigationLink {
                                RecentTripsListView(
                                    trips: tripManager.recentTrips,
                                    fuelSettings: onboardingStore.fuelSettings
                                )
                            } label: {
                                Label("home.todayTrips.viewAll", systemImage: "list.bullet")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(ViimColors.blue)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 2)

                    Group {
                        if tripManager.recentTrips.isEmpty {
                            RecentTripPlaceholderCard()
                        } else {
                            VStack(spacing: 10) {
                                ForEach(tripManager.recentTrips.prefix(3)) { trip in
                                    NavigationLink {
                                        TripDetailView(trip: trip, fuelSettings: onboardingStore.fuelSettings)
                                    } label: {
                                        RecentTripCard(trip: trip, fuelSettings: onboardingStore.fuelSettings)
                                    }
                                    .buttonStyle(PressableButtonStyle())
                                }
                            }
                        }
                    }
                    .staggeredAppear(hasAppeared, index: 5)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: locationService.tripPhase)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: tripManager.lastPersistenceOutcome)
            }
            .background(ViimColors.background.ignoresSafeArea())
            .navigationTitle("home.title")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        ProfilView()
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel(Text("profile.open"))
                }
            }
        }
        .task {
            emergencyContact = (try? SecureEmergencyContactStore.shared.load()).flatMap(BurkinaPhoneNumber.normalizedContact)
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
        }
    }

    private var statusCard: some View {
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
                    detailKey: collisionDetectionStatus.localizedDetailKey,
                    tint: collisionDetectionStatus.tint
                )
                HomeStatusRow(
                    icon: "person.2.fill",
                    titleKey: "home.status.familyAlert",
                    detailKey: emergencyContact == nil ? "home.status.familyAlert.empty" : "status.enabled",
                    tint: emergencyContact == nil ? ViimColors.blue : ViimColors.success
                )
                HomeStatusRow(
                    icon: "wifi",
                    titleKey: "home.status.network",
                    detailKey: networkStatus.localizedDetailKey,
                    tint: networkStatus.tint,
                    showsDivider: false
                )
            }
        }
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

    private var collisionDetectionStatus: HomeStatusPresentation {
        HomeStatusPresenter.collisionDetection(isEnabled: tripManager.collisionDetectionEnabled)
    }

    private var networkStatus: HomeStatusPresentation {
        HomeStatusPresenter.network(isOnline: networkStatusService.isOnline)
    }
}

private struct CaptureOutcomeCard: View {
    let outcome: TripPersistenceOutcome

    var body: some View {
        ViimCard {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(titleKey)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    Text(detailKey)
                        .font(.caption)
                        .foregroundStyle(ViimColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var titleKey: LocalizedStringKey {
        switch outcome {
        case .persisted, .duplicate: "home.capture.persisted.title"
        case .rejected: "home.capture.rejected.title"
        case .failedRetryable: "home.capture.retry.title"
        }
    }

    private var detailKey: LocalizedStringKey {
        switch outcome {
        case .persisted: "home.capture.persisted.detail"
        case .duplicate: "home.capture.duplicate.detail"
        case .rejected: "home.capture.rejected.detail"
        case .failedRetryable: "home.capture.retry.detail"
        }
    }

    private var iconName: String {
        switch outcome {
        case .persisted, .duplicate: "checkmark.circle.fill"
        case .rejected: "location.slash.fill"
        case .failedRetryable: "arrow.clockwise.circle.fill"
        }
    }

    private var tint: Color {
        switch outcome {
        case .persisted, .duplicate: ViimColors.success
        case .rejected: ViimColors.warning
        case .failedRetryable: ViimColors.red
        }
    }
}

struct HomeStatusPresentation: Equatable {
    let detailKey: String
    let tone: HomeStatusTone

    var localizedDetailKey: LocalizedStringKey {
        LocalizedStringKey(detailKey)
    }

    var tint: Color {
        tone.tint
    }
}

enum HomeStatusTone: Equatable {
    case success
    case warning
    case blue

    var tint: Color {
        switch self {
        case .success:
            return ViimColors.success
        case .warning:
            return ViimColors.warning
        case .blue:
            return ViimColors.blue
        }
    }
}

enum HomeStatusPresenter {
    static func collisionDetection(isEnabled: Bool) -> HomeStatusPresentation {
        HomeStatusPresentation(
            detailKey: isEnabled ? "status.enabled" : "home.status.collisionDetection.pending",
            tone: isEnabled ? .success : .blue
        )
    }

    static func network(isOnline: Bool) -> HomeStatusPresentation {
        HomeStatusPresentation(
            detailKey: isOnline ? "status.online" : "status.offlineReady",
            tone: isOnline ? .success : .warning
        )
    }
}

private struct HomeHero: View {
    let firstName: String?
    @State private var routeDrawn = false

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [ViimColors.navy, Color(hex: 0x0E1E30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Halos discrets pour donner de la profondeur au fond navy.
            Circle()
                .fill(ViimColors.blue.opacity(0.18))
                .frame(width: 190, height: 190)
                .blur(radius: 40)
                .offset(x: 220, y: -60)
            Circle()
                .fill(ViimColors.gold.opacity(0.10))
                .frame(width: 150, height: 150)
                .blur(radius: 36)
                .offset(x: -60, y: 80)

            // Trace de route qui se dessine a l'ouverture : le motif metier de
            // Viim (le trajet) devient la signature visuelle de l'Accueil.
            HeroRoute(drawn: routeDrawn)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 0) {
                    Text(verbatim: "Viim")
                        .foregroundStyle(.white)
                    Text(verbatim: ".")
                        .foregroundStyle(ViimColors.gold)
                }
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .padding(.bottom, 6)

                Text(greetingKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(displayName)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ViimColors.gold.opacity(0.9))
                    .padding(.top, 1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(height: 158)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: ViimColors.navy.opacity(0.30), radius: 10, x: 0, y: 5)
        .onAppear {
            guard !routeDrawn else { return }
            withAnimation(.easeOut(duration: 1.4).delay(0.3)) {
                routeDrawn = true
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var greetingKey: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: Date())
        return (5..<18).contains(hour) ? "home.greeting.morning" : "home.greeting.evening"
    }

    private var displayName: String {
        let trimmed = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(localized: "home.greeting.defaultName") : trimmed
    }
}

/// Trace de trajet stylisee du hero : une route en pointilles qui se dessine,
/// un depart navy et une arrivee doree qui pulse doucement.
private struct HeroRoute: View {
    let drawn: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                routePath(width: w, height: h)
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.16), ViimColors.gold.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 7])
                    )

                Circle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .position(x: w * 0.42, y: h * 0.88)

                PulsingDot(color: ViimColors.gold)
                    .position(x: w * 0.90, y: h * 0.24)
                    .opacity(drawn ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private func routePath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: width * 0.42, y: height * 0.88))
            path.addCurve(
                to: CGPoint(x: width * 0.68, y: height * 0.52),
                control1: CGPoint(x: width * 0.55, y: height * 0.92),
                control2: CGPoint(x: width * 0.63, y: height * 0.74)
            )
            path.addCurve(
                to: CGPoint(x: width * 0.90, y: height * 0.24),
                control1: CGPoint(x: width * 0.74, y: height * 0.30),
                control2: CGPoint(x: width * 0.84, y: height * 0.22)
            )
        }
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
    let onEnableBackgroundDetection: () -> Void

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

                if authorizationState == .authorizedWhenInUse {
                    Button {
                        onEnableBackgroundDetection()
                    } label: {
                        Label("home.monitoring.background.action", systemImage: "lock.open.fill")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(ViimColors.blue)
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
        if authorizationState == .authorizedWhenInUse {
            return "home.monitoring.whenInUse.detail"
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
        if authorizationState == .authorizedWhenInUse {
            return "location.permission.whenInUse"
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
                HStack(spacing: 8) {
                    PulsingDot(color: ViimColors.success)
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
    let hasPersistenceError: Bool
    let fuelSettings: FuelSettings

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
                        value: DrivingValueFormatter.scoreText(scoreMetric),
                        labelKey: "home.metric.score.label",
                        color: scoreColor,
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
                        value: DrivingValueFormatter.moneyText(
                            costMetric,
                            currency: fuelSettings.currency
                        ),
                        labelKey: "home.metric.cost.label",
                        color: ViimColors.green
                    )
                }
            }
        }
    }

    private var summaryStatusKey: LocalizedStringKey {
        hasPersistenceError ? "home.summary.persistenceError" : "home.summary.status"
    }

    private var scoreMetric: ReliableMetric<Int> {
        TripMetricsCalculator.summaryScoreMetric(summary)
    }

    private var scoreColor: Color {
        guard let score = scoreMetric.value else {
            return ViimColors.muted
        }
        if score >= 80 { return ViimColors.success }
        if score >= 60 { return ViimColors.warning }
        return ViimColors.danger
    }

    private var costMetric: ReliableMetric<Int> {
        TripMetricsCalculator.fuelCostMetric(
            liters: summary.fuelLiters,
            settings: fuelSettings
        )
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
                        ViimChip(titleKey: "home.recentTrips.empty.status", style: .neutral)
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
    let fuelSettings: FuelSettings

    var body: some View {
        ViimCard {
            HStack(spacing: 10) {
                TripRoutePreview(trip: trip)
                    .frame(width: 74, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(DrivingValueFormatter.tripDateText(trip.endDate))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ViimColors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 6)
                        ViimChip(titleKey: "home.recentTrips.saved", style: .success)
                    }

                    HStack(spacing: 10) {
                        Label(DrivingValueFormatter.distanceText(kilometers: trip.distanceKm), systemImage: "road.lanes")
                        Label(DrivingValueFormatter.durationText(seconds: trip.durationSec), systemImage: "clock.fill")
                        Label(DrivingValueFormatter.scoreText(scoreMetric), systemImage: "star.fill")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ViimColors.muted)

                    HStack(spacing: 8) {
                        Label(
                            DrivingValueFormatter.moneyText(fuelMetric, currency: fuelSettings.currency),
                            systemImage: "fuelpump.fill"
                        )
                        Spacer(minLength: 6)
                        Text("home.recentTrips.local")
                    }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ViimColors.muted)
                }
            }
        }
    }

    private var scoreMetric: ReliableMetric<Int> {
        TripMetricsCalculator.scoreMetric(for: trip)
    }

    private var fuelMetric: ReliableMetric<Int> {
        TripMetricsCalculator.fuelCostMetric(
            liters: trip.fuelLiters,
            settings: fuelSettings,
            vehicleType: trip.vehicleType
        )
    }
}

private struct TripRoutePreview: View {
    let trip: TripRecord

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(trip.vehicleType.tint.opacity(0.12))

            if validRoutePoints.count >= 2 {
                RouteShape(points: validRoutePoints)
                    .stroke(trip.vehicleType.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .padding(10)
            } else {
                RouteUnavailableThumbnail(tint: trip.vehicleType.tint)
            }

            if validRoutePoints.count >= 2 {
                Image(systemName: trip.vehicleType.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(trip.vehicleType.tint)
                    .clipShape(Circle())
                    .offset(x: 24, y: 18)
            }
        }
    }

    private var validRoutePoints: [TripRoutePoint] {
        TripMetricsCalculator.validRoutePoints(from: trip.routePoints)
    }
}

private struct RouteUnavailableThumbnail: View {
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "location.slash.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text("trip.route.unavailable.short")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ViimColors.muted)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
        .padding(6)
    }
}

private struct RouteUnavailableMap: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "map.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(ViimColors.blue)
            Text("trip.route.unavailable.title")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ViimColors.text)
            Text("trip.route.unavailable.detail")
                .font(.caption)
                .foregroundStyle(ViimColors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xE8F0E4))
    }
}

private struct TripDetailView: View {
    let trip: TripRecord
    let fuelSettings: FuelSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                TripRouteMapSection(trip: trip)

                ViimCard {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 12) {
                        SummaryMetricTile(
                            value: DrivingValueFormatter.distanceText(kilometers: trip.distanceKm),
                            labelKey: "home.metric.distance.label",
                            color: ViimColors.blue
                        )
                        SummaryMetricTile(
                            value: DrivingValueFormatter.durationText(seconds: trip.durationSec),
                            labelKey: "home.metric.duration.label",
                            color: ViimColors.navy
                        )
                        SummaryMetricTile(
                            value: DrivingValueFormatter.speedText(kmh: trip.avgSpeedKmh),
                            labelKey: "trip.detail.avgSpeed",
                            color: ViimColors.success
                        )
                        SummaryMetricTile(
                            value: DrivingValueFormatter.speedText(maxSpeedMetric),
                            labelKey: "trip.detail.maxSpeed",
                            color: maxSpeedMetric.confidence == .needsReview ? ViimColors.red : ViimColors.warning
                        )
                        SummaryMetricTile(
                            value: DrivingValueFormatter.scoreText(scoreMetric),
                            labelKey: "home.metric.score.label",
                            color: ViimColors.success
                        )
                        SummaryMetricTile(
                            value: DrivingValueFormatter.moneyText(
                                fuelMetric,
                                currency: fuelSettings.currency
                            ),
                            labelKey: "home.metric.cost.label",
                            color: ViimColors.green
                        )
                    }
                }

                TripNavigationDataCard(trip: trip)
            }
            .padding(14)
        }
        .background(ViimColors.background.ignoresSafeArea())
        .navigationTitle("trip.detail.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var maxSpeedMetric: ReliableMetric<Double> {
        TripMetricsCalculator.maxSpeedMetric(for: trip)
    }

    private var scoreMetric: ReliableMetric<Int> {
        TripMetricsCalculator.scoreMetric(for: trip)
    }

    private var fuelMetric: ReliableMetric<Int> {
        TripMetricsCalculator.fuelCostMetric(
            liters: trip.fuelLiters,
            settings: fuelSettings,
            vehicleType: trip.vehicleType
        )
    }
}

private struct TripRouteMapSection: View {
    let trip: TripRecord

    var body: some View {
        ViimCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("trip.detail.navigation")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    Spacer()
                    ViimChip(titleKey: "home.recentTrips.local", style: .neutral)
                }

                if validRoutePoints.count >= 2 {
                    TripRouteMapView(routePoints: validRoutePoints, tint: trip.vehicleType.tint)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RouteUnavailableMap()
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var validRoutePoints: [TripRoutePoint] {
        TripMetricsCalculator.validRoutePoints(from: trip.routePoints)
    }
}

private struct TripRouteMapView: View {
    let routePoints: [TripRoutePoint]
    let tint: Color

    var body: some View {
        if routePoints.count >= 2 {
            if #available(iOS 17.0, *) {
                TripRouteMapModern(routePoints: routePoints, tint: tint)
            } else {
                TripRouteMapFallback(routePoints: routePoints, tint: tint)
            }
        } else {
            RouteUnavailableMap()
        }
    }
}

@available(iOS 17.0, *)
private struct TripRouteMapModern: View {
    let routePoints: [TripRoutePoint]
    let tint: Color
    @State private var position: MapCameraPosition

    init(routePoints: [TripRoutePoint], tint: Color) {
        self.routePoints = routePoints
        self.tint = tint
        _position = State(initialValue: .region(Self.region(for: routePoints)))
    }

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            MapPolyline(coordinates: coordinates)
                .stroke(tint, lineWidth: 5)

            if let start = coordinates.first {
                Marker("trip.detail.start", systemImage: "play.fill", coordinate: start)
                    .tint(ViimColors.success)
            }

            if let end = coordinates.last {
                Marker("trip.detail.end", systemImage: "flag.fill", coordinate: end)
                    .tint(ViimColors.red)
            }
        }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        routePoints.map(\.coordinate)
    }

    private static func region(for points: [TripRoutePoint]) -> MKCoordinateRegion {
        TripMapRegionBuilder.region(for: points)
    }
}

private struct TripRouteMapFallback: View {
    let routePoints: [TripRoutePoint]
    let tint: Color

    var body: some View {
        ZStack {
            Color(hex: 0xE8F0E4)
            if routePoints.count >= 2 {
                RouteShape(points: routePoints)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .padding(18)
            } else {
                RouteUnavailableMap()
            }
        }
    }
}

private struct TripNavigationDataCard: View {
    let trip: TripRecord

    var body: some View {
        ViimCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("trip.detail.gpsData")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ViimColors.text)

                TripDetailInfoRow(
                    titleKey: "trip.detail.points",
                    value: DrivingValueFormatter.routePointsText(validRoutePoints.count)
                )

                if let start = validRoutePoints.first {
                    TripDetailInfoRow(
                        titleKey: "trip.detail.start",
                        value: DrivingValueFormatter.coordinatesText(latitude: start.latitude, longitude: start.longitude)
                    )
                }

                if let end = validRoutePoints.last {
                    TripDetailInfoRow(
                        titleKey: "trip.detail.end",
                        value: DrivingValueFormatter.coordinatesText(latitude: end.latitude, longitude: end.longitude)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var validRoutePoints: [TripRoutePoint] {
        TripMetricsCalculator.validRoutePoints(from: trip.routePoints)
    }

    private var routeMetric: ReliableMetric<Int> {
        TripMetricsCalculator.routeMetric(points: trip.routePoints)
    }
}

private struct TripDetailInfoRow: View {
    let titleKey: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titleKey)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ViimColors.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(ViimColors.text)
                .multilineTextAlignment(.trailing)
        }
    }
}

private enum TripMapRegionBuilder {
    static func region(for points: [TripRoutePoint]) -> MKCoordinateRegion {
        guard let first = points.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 12.3714, longitude: -1.5197),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }

        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let minLatitude = latitudes.min() ?? first.latitude
        let maxLatitude = latitudes.max() ?? first.latitude
        let minLongitude = longitudes.min() ?? first.longitude
        let maxLongitude = longitudes.max() ?? first.longitude
        let latitudeSpan = max((maxLatitude - minLatitude) * 1.6, 0.01)
        let longitudeSpan = max((maxLongitude - minLongitude) * 1.6, 0.01)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
        )
    }
}

private struct RecentTripsListView: View {
    let trips: [TripRecord]
    let fuelSettings: FuelSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if trips.isEmpty {
                    RecentTripPlaceholderCard()
                } else {
                    ForEach(trips) { trip in
                        NavigationLink {
                            TripDetailView(trip: trip, fuelSettings: fuelSettings)
                        } label: {
                            RecentTripCard(trip: trip, fuelSettings: fuelSettings)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
        .background(ViimColors.background.ignoresSafeArea())
        .navigationTitle("home.recentTrips.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RouteShape: Shape {
    let points: [TripRoutePoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first else {
            return Path()
        }

        let minLatitude = points.map(\.latitude).min() ?? first.latitude
        let maxLatitude = points.map(\.latitude).max() ?? first.latitude
        let minLongitude = points.map(\.longitude).min() ?? first.longitude
        let maxLongitude = points.map(\.longitude).max() ?? first.longitude
        let latitudeSpan = max(maxLatitude - minLatitude, 0.00001)
        let longitudeSpan = max(maxLongitude - minLongitude, 0.00001)

        var path = Path()
        for (index, point) in points.enumerated() {
            let x = rect.minX + CGFloat((point.longitude - minLongitude) / longitudeSpan) * rect.width
            let y = rect.maxY - CGFloat((point.latitude - minLatitude) / latitudeSpan) * rect.height
            let cgPoint = CGPoint(x: x, y: y)

            if index == 0 {
                path.move(to: cgPoint)
            } else {
                path.addLine(to: cgPoint)
            }
        }
        return path
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
