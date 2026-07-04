import SwiftUI

struct ConduiteView: View {
    @EnvironmentObject private var tripManager: TripManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    DrivingHeroCard(summary: tripManager.last30DaysSummary)

                    Text("driving.period")
                        .font(.caption)
                        .foregroundStyle(ViimColors.muted)
                        .frame(maxWidth: .infinity, alignment: .center)

                    SectionTitle(titleKey: "driving.performance.section", systemImage: "info.circle.fill", tint: ViimColors.blue)

                    ViimCard {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("driving.performance.badges")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(ViimColors.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("driving.performance.cityAverage")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ViimColors.blue)
                            }
                            Spacer(minLength: 8)
                            ScoreRing(valueKey: "driving.performance.percent", color: ViimColors.navy)
                        }
                    }

                    CompactInfoRow(
                        icon: "fuelpump.fill",
                        titleKey: "driving.eco.title",
                        detailKey: "driving.eco.savings",
                        tint: ViimColors.green
                    )

                    CompactInfoRow(
                        icon: "medal.fill",
                        titleKey: "driving.badges.title",
                        detailKey: "driving.badges.status",
                        tint: ViimColors.gold
                    )

                    Button(action: {}) {
                        Text("driving.action.style")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(ViimColors.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    SectionTitle(titleKey: "driving.portrait.title", systemImage: "gauge.medium", tint: ViimColors.blue)

                    DrivingCriterionCard(
                        icon: "speedometer",
                        titleKey: "driving.criteria.speed",
                        valueKey: "driving.criteria.speed.value",
                        detailKey: "driving.criteria.speed.detail",
                        progress: 0,
                        color: ViimColors.success
                    )
                    DrivingCriterionCard(
                        icon: "waveform.path.ecg",
                        titleKey: "driving.criteria.smoothness",
                        valueKey: "driving.criteria.smoothness.value",
                        detailKey: "driving.criteria.smoothness.detail",
                        progress: 0,
                        color: ViimColors.warning
                    )
                    DrivingCriterionCard(
                        icon: "iphone.slash",
                        titleKey: "driving.criteria.vigilance",
                        valueKey: "driving.criteria.vigilance.value",
                        detailKey: "driving.criteria.vigilance.detail",
                        progress: 0,
                        color: ViimColors.success
                    )

                    ViimCard {
                        HStack(spacing: 10) {
                            StatusPill(icon: "shield.fill", titleKey: "driving.security.title", valueKey: "driving.security.status", tint: ViimColors.warning)
                            StatusPill(icon: "leaf.fill", titleKey: "driving.eco.shortTitle", valueKey: "driving.eco.improvement", tint: ViimColors.green)
                        }
                    }

                    AdviceCard(
                        titleKey: "driving.advice.title",
                        detailKey: "driving.advice.detail",
                        tint: ViimColors.warning
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(ViimColors.background.ignoresSafeArea())
            .navigationTitle("driving.title")
        }
    }
}

private struct DrivingHeroCard: View {
    let summary: DrivingSummary

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [ViimColors.navy, Color(hex: 0x1E4B6F)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            MountainScene()
                .padding(.top, 18)

            HStack(spacing: 0) {
                HeroMetric(value: String(summary.tripsCount), labelKey: "driving.hero.trips.label")
                Divider().background(Color.white.opacity(0.25))
                HeroMetric(value: DrivingValueFormatter.distanceText(kilometers: summary.totalKm), labelKey: "driving.hero.distance.label")
                Divider().background(Color.white.opacity(0.25))
                HeroMetric(value: DrivingValueFormatter.durationText(seconds: summary.totalDurationSec), labelKey: "driving.hero.duration.label")
            }
            .frame(height: 58)
            .background(.white.opacity(0.96))
        }
        .frame(height: 206)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: ViimColors.text.opacity(0.10), radius: 8, x: 0, y: 4)
    }
}

private struct MountainScene: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.10, y: height * 0.72))
                    path.addLine(to: CGPoint(x: width * 0.38, y: height * 0.24))
                    path.addLine(to: CGPoint(x: width * 0.78, y: height * 0.72))
                    path.closeSubpath()
                }
                .fill(Color(hex: 0x16324D))

                Path { path in
                    path.move(to: CGPoint(x: width * 0.48, y: height * 0.72))
                    path.addLine(to: CGPoint(x: width * 0.72, y: height * 0.36))
                    path.addLine(to: CGPoint(x: width * 0.98, y: height * 0.72))
                    path.closeSubpath()
                }
                .fill(Color(hex: 0x244E73))

                Circle()
                    .fill(ViimColors.gold)
                    .frame(width: 18, height: 18)
                    .position(x: width * 0.40, y: height * 0.35)

                Image(systemName: "flag.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ViimColors.red)
                    .position(x: width * 0.55, y: height * 0.21)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HeroMetric: View {
    let value: String
    let labelKey: LocalizedStringKey

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(ViimColors.navy)
            Text(labelKey)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ViimColors.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SectionTitle: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(titleKey)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ViimColors.text)
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

private struct ScoreRing: View {
    let valueKey: LocalizedStringKey
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
            Text(valueKey)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 58, height: 58)
    }
}

private struct CompactInfoRow: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color

    var body: some View {
        ViimCard {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                Text(titleKey)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ViimColors.text)
                Spacer(minLength: 8)
                Text(detailKey)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct DrivingCriterionCard: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let valueKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let progress: CGFloat
    let color: Color

    var body: some View {
        ViimCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(titleKey, systemImage: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    Spacer()
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(ViimColors.blue)
                }

                Text(valueKey)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)

                Text(detailKey)
                    .font(.caption)
                    .foregroundStyle(ViimColors.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressBar(progress: progress, color: color)
            }
        }
    }
}

private struct ProgressBar: View {
    let progress: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0xE3EAF1))
                Capsule()
                    .fill(color)
                    .frame(width: max(8, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

private struct StatusPill: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let valueKey: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ViimColors.text)
                Text(valueKey)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AdviceCard: View {
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(titleKey, systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(detailKey)
                .font(.caption)
                .foregroundStyle(ViimColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFF9EC))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xF3E2B3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
