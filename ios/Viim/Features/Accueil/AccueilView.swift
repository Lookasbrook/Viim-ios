import SwiftUI

struct AccueilView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HomeHero(firstName: onboardingStore.profile?.firstName)

                VehicleTrackingCard(
                    profile: onboardingStore.profile,
                    phase: locationService.tripPhase
                )

                DailySummaryCard()

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

                Text("home.recentTrips.title")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ViimColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                    .padding(.top, 2)

                RecentTripPlaceholderCard()
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
        return locationService.isMonitoring ? locationService.tripPhase.statusKey : "location.monitoring.paused"
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
    let phase: TripDetectionPhase

    var body: some View {
        ViimCard {
            HStack(spacing: 10) {
                VehicleIllustration(type: profile?.vehicleType ?? .moto, width: 92)
                    .frame(width: 92)

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

                    ViimChip(titleKey: phase.statusKey, style: .success)
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

private struct DailySummaryCard: View {
    var body: some View {
        ViimCard {
            VStack(spacing: 9) {
                HStack {
                    Text("home.summary.title")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    Spacer()
                    ViimChip(titleKey: "home.summary.status", style: .success)
                }

                MetricGrid(
                    metrics: [
                        .init(valueKey: "home.metric.score.calibration", labelKey: "home.metric.score.label", color: ViimColors.success, isLarge: true),
                        .init(valueKey: "home.metric.distance.empty", labelKey: "home.metric.distance.label"),
                        .init(valueKey: "home.metric.trips.empty", labelKey: "home.metric.trips.label"),
                        .init(valueKey: "home.metric.duration.empty", labelKey: "home.metric.duration.label"),
                        .init(valueKey: "home.metric.fuel.empty", labelKey: "home.metric.fuel.label"),
                        .init(valueKey: "home.metric.savings.empty", labelKey: "home.metric.savings.label", color: ViimColors.green)
                    ]
                )

                Text("home.summary.calibration")
                    .font(.caption)
                    .foregroundStyle(ViimColors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
