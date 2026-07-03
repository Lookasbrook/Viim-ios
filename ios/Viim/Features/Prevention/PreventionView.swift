import SwiftUI

struct PreventionView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    PreventionHero()

                    ViimCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("prevention.dangerZones.title", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(ViimColors.text)
                                Spacer()
                                ViimChip(titleKey: "prevention.alerts.enabled", style: .success)
                            }
                            Text("prevention.dangerZones.source")
                                .font(.caption)
                                .foregroundStyle(ViimColors.muted)
                            DangerZoneRow(titleKey: "prevention.zone.jeunes", detailKey: "prevention.zone.rank1", tint: ViimColors.red)
                            DangerZoneRow(titleKey: "prevention.zone.insurrection", detailKey: "prevention.zone.rank2", tint: ViimColors.red)
                            DangerZoneRow(titleKey: "prevention.zone.bassawarga", detailKey: "prevention.zone.rank3", tint: ViimColors.warning)
                        }
                    }

                    ViimCard {
                        VStack(spacing: 0) {
                            PreventionListRow(icon: "cloud.rain.fill", titleKey: "prevention.weather.rainySeason", detailKey: "prevention.weather.active", tint: ViimColors.warning)
                            PreventionListRow(icon: "wind", titleKey: "prevention.weather.harmattan", detailKey: "prevention.weather.none", tint: ViimColors.muted)
                            PreventionListRow(icon: "moon.fill", titleKey: "prevention.weather.night", detailKey: "status.enabled", tint: ViimColors.green)
                            PreventionListRow(icon: "fuelpump.fill", titleKey: "prevention.fuel.shortage", detailKey: "prevention.fuel.detail", tint: ViimColors.blue, showsDivider: false)
                        }
                    }

                    ViimCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("prevention.maintenance.title", systemImage: "wrench.and.screwdriver.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(ViimColors.text)
                                Spacer()
                                ViimChip(titleKey: "prevention.maintenance.taskCount", style: .warning)
                            }
                            Text(verbatim: vehicleName)
                                .font(.caption)
                                .foregroundStyle(ViimColors.muted)
                                .lineLimit(2)
                            MaintenanceRow(titleKey: "prevention.maintenance.oil", detailKey: "prevention.maintenance.oil.detail", tint: ViimColors.muted)
                            MaintenanceRow(titleKey: "prevention.maintenance.chain", detailKey: "prevention.maintenance.chain.detail", tint: ViimColors.danger)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("prevention.challenge.title", systemImage: "trophy.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ViimColors.green)
                        Text("prevention.challenge.detail")
                            .font(.caption)
                            .foregroundStyle(ViimColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        ChallengeProgress()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xEFFAF3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: 0xCBEBD8), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(ViimColors.background.ignoresSafeArea())
            .navigationTitle("prevention.title")
        }
    }

    private var vehicleName: String {
        guard let profile = onboardingStore.profile else {
            return String(localized: "prevention.maintenance.vehicleFallback")
        }
        return profile.vehicleDisplayName
    }
}

private struct PreventionHero: View {
    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [Color(hex: 0x123A28), ViimColors.green],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 82, weight: .bold))
                .foregroundStyle(.white.opacity(0.13))
                .offset(x: 216, y: 12)
            VStack(alignment: .leading, spacing: 6) {
                Text("prevention.title")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("prevention.hero.detail")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(18)
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DangerZoneRow: View {
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(titleKey)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ViimColors.text)
            Spacer(minLength: 8)
            Text(detailKey)
                .font(.caption.weight(.bold))
                .foregroundStyle(ViimColors.muted)
        }
        .frame(minHeight: 30)
    }
}

private struct PreventionListRow: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                Text(titleKey)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ViimColors.text)
                Spacer(minLength: 8)
                Text(detailKey)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ViimColors.muted)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(minHeight: 48)

            if showsDivider {
                Divider()
                    .padding(.leading, 45)
            }
        }
    }
}

private struct MaintenanceRow: View {
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack {
            Text(titleKey)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ViimColors.text)
            Spacer()
            Text(detailKey)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
        }
        .frame(minHeight: 30)
    }
}

private struct ChallengeProgress: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0xDDEFE4))
                Capsule()
                    .fill(ViimColors.green)
                    .frame(width: proxy.size.width * 0.60)
            }
        }
        .frame(height: 8)
    }
}
