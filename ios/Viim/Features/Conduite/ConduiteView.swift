import SwiftUI

struct ConduiteView: View {
    @EnvironmentObject private var tripManager: TripManager
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    DrivingHeroCard(summary: summary, animate: hasAppeared)
                        .staggeredAppear(hasAppeared, index: 0)

                    Text("driving.period")
                        .font(.caption)
                        .foregroundStyle(ViimColors.muted)
                        .frame(maxWidth: .infinity, alignment: .center)

                    SectionTitle(titleKey: "driving.performance.section", systemImage: "info.circle.fill", tint: ViimColors.blue)

                    ViimCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(performanceTitle)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(ViimColors.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if scoreMetric.value != nil {
                                        ViimChip(titleKey: "driving.score.partialChip", style: .neutral)
                                    }
                                }
                                Spacer(minLength: 8)
                                ScoreRing(
                                    score: scoreMetric.value,
                                    text: displayedScoreText,
                                    color: displayedScoreColor,
                                    animate: hasAppeared
                                )
                            }

                            Text(performanceDetail)
                                .font(.caption)
                                .foregroundStyle(ViimColors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    EcoSummaryRow(summary: summary, settings: onboardingStore.fuelSettings)
                        .staggeredAppear(hasAppeared, index: 2)

                    CompactInfoRow(
                        icon: "medal.fill",
                        titleKey: "driving.badges.title",
                        detailKey: "driving.badges.status",
                        tint: ViimColors.gold
                    )

                    NavigationLink {
                        DrivingStyleDetailView(
                            summary: summary,
                            speedMetric: scoreMetric,
                            animate: true
                        )
                    } label: {
                        Text("driving.action.style")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                LinearGradient(
                                    colors: [ViimColors.blue, Color(hex: 0x2361A0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: ViimColors.blue.opacity(0.28), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(PressableButtonStyle())

                    SectionTitle(titleKey: "driving.portrait.title", systemImage: "gauge.medium", tint: ViimColors.blue)

                    SpeedCriterionCard(metric: scoreMetric, animate: hasAppeared)

                    if let fluidityScore = summary.avgScoreFluidite {
                        ScoreCriterionCard(
                            icon: "waveform.path.ecg",
                            titleKey: "driving.criteria.smoothness",
                            detailKey: "driving.criteria.smoothness.detail.real",
                            score: fluidityScore,
                            animate: hasAppeared
                        )
                    } else {
                        UpcomingCriterionCard(
                            icon: "waveform.path.ecg",
                            titleKey: "driving.criteria.smoothness",
                            detailKey: "driving.criteria.smoothness.detail"
                        )
                    }
                    if let ecoScore = summary.avgScoreEco {
                        ScoreCriterionCard(
                            icon: "leaf.fill",
                            titleKey: "driving.criteria.eco",
                            detailKey: "driving.criteria.eco.detail.real",
                            score: ecoScore,
                            animate: hasAppeared
                        )
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
            .onAppear {
                guard !hasAppeared else { return }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.15)) {
                    hasAppeared = true
                }
            }
        }
    }

    private var summary: DrivingSummary {
        tripManager.last30DaysSummary
    }

    private var displayedScoreText: String {
        DrivingValueFormatter.scoreText(scoreMetric)
    }

    private var displayedScoreColor: Color {
        guard let score = scoreMetric.value else {
            return ViimColors.navy
        }
        if score >= 80 { return ViimColors.success }
        if score >= 60 { return ViimColors.warning }
        return ViimColors.danger
    }

    private var performanceTitle: String {
        guard scoreMetric.value != nil else {
            return String(localized: "driving.performance.empty")
        }
        return String.localizedStringWithFormat(
            String(localized: "driving.performance.basedOnTrips"),
            summary.tripsCount
        )
    }

    private var performanceDetail: String {
        guard scoreMetric.value != nil else {
            return String(localized: "driving.performance.empty.detail")
        }
        return String(localized: "driving.performance.detail")
    }

    private var scoreMetric: ReliableMetric<Int> {
        TripMetricsCalculator.summaryScoreMetric(summary)
    }
}

private struct DrivingStyleDetailView: View {
    let summary: DrivingSummary
    let speedMetric: ReliableMetric<Int>
    let animate: Bool
    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                DrivingHeroCard(summary: summary, animate: hasAppeared)
                ViimCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("driving.portrait.title")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(ViimColors.text)
                        Text("driving.portrait.explanation")
                            .font(.body)
                            .foregroundStyle(ViimColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                SpeedCriterionCard(metric: speedMetric, animate: hasAppeared)
                if let fluidityScore = summary.avgScoreFluidite {
                    ScoreCriterionCard(
                        icon: "waveform.path.ecg",
                        titleKey: "driving.criteria.smoothness",
                        detailKey: "driving.criteria.smoothness.detail.real",
                        score: fluidityScore,
                        animate: hasAppeared
                    )
                } else {
                    UpcomingCriterionCard(
                        icon: "waveform.path.ecg",
                        titleKey: "driving.criteria.smoothness",
                        detailKey: "driving.criteria.smoothness.detail"
                    )
                }
                if let ecoScore = summary.avgScoreEco {
                    ScoreCriterionCard(
                        icon: "leaf.fill",
                        titleKey: "driving.criteria.eco",
                        detailKey: "driving.criteria.eco.detail.real",
                        score: ecoScore,
                        animate: hasAppeared
                    )
                }
            }
            .padding(14)
        }
        .background(ViimColors.background.ignoresSafeArea())
        .navigationTitle("driving.portrait.title")
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.15)) {
                hasAppeared = true
            }
        }
    }
}

private struct DrivingHeroCard: View {
    let summary: DrivingSummary
    var animate = true

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [ViimColors.navy, Color(hex: 0x1E4B6F)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            MountainScene(animate: animate)
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
    var animate = true

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
                    .scaleEffect(animate ? 1 : 0.2)
                    .opacity(animate ? 1 : 0)
                    .position(x: width * 0.40, y: height * 0.35)

                Image(systemName: "flag.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ViimColors.red)
                    .opacity(animate ? 1 : 0)
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
                .contentTransition(.numericText())
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
    let score: Int?
    let text: String
    let color: Color
    var animate = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 7)

            if let score {
                Circle()
                    .trim(from: 0, to: animate ? CGFloat(min(max(score, 0), 100)) / 100 : 0.02)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.6), color],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.2), value: animate)
            }

            Text(text)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(score == nil ? ViimColors.muted : color)
                .contentTransition(.numericText())
        }
        .frame(width: 64, height: 64)
        .scaleEffect(animate ? 1 : 0.7)
        .opacity(animate ? 1 : 0)
    }
}

private struct EcoSummaryRow: View {
    let summary: DrivingSummary
    let settings: FuelSettings?

    var body: some View {
        ViimCard {
            HStack(spacing: 12) {
                Image(systemName: "fuelpump.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ViimColors.green)
                    .frame(width: 34, height: 34)
                    .background(ViimColors.green.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("driving.eco.title")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    if hasRealEstimate {
                        Text("driving.eco.estimatedTag")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ViimColors.muted)
                    }
                }
                Spacer(minLength: 8)
                Text(detailText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ViimColors.green)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var hasRealEstimate: Bool {
        summary.fuelLiters != nil && summary.tripsCount > 0
    }

    private var detailText: String {
        guard let liters = summary.fuelLiters, summary.tripsCount > 0 else {
            return String(localized: "driving.eco.savings")
        }

        let litersText = String.localizedStringWithFormat(
            String(localized: "driving.eco.litersFormat"),
            liters
        )

        if let settings {
            let costMetric = TripMetricsCalculator.fuelCostMetric(
                liters: liters,
                settings: settings
            )
            if costMetric.value != nil {
                let costText = DrivingValueFormatter.moneyText(costMetric, currency: settings.currency)
                return "\(litersText) · \(costText)"
            }
        }

        return litersText
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

private struct SpeedCriterionCard: View {
    let metric: ReliableMetric<Int>
    var animate = true

    var body: some View {
        ViimCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("driving.criteria.speed", systemImage: "speedometer")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    Spacer()
                    if metric.value != nil {
                        ViimChip(titleKey: "driving.score.partialChip", style: .neutral)
                    }
                }

                if let score = metric.value {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(score))
                            .font(.system(size: 27, weight: .heavy, design: .rounded))
                            .foregroundStyle(color(for: score))
                            .contentTransition(.numericText())
                        Text("driving.criteria.speed.unit")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ViimColors.muted)
                    }

                    Text("driving.criteria.speed.detail.real")
                        .font(.caption)
                        .foregroundStyle(ViimColors.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    AnimatedProgressBar(
                        progress: CGFloat(score) / 100,
                        color: color(for: score),
                        animate: animate
                    )
                } else {
                    Text("format.score.empty")
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .foregroundStyle(ViimColors.muted)

                    Text("driving.criteria.speed.detail")
                        .font(.caption)
                        .foregroundStyle(ViimColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func color(for score: Int) -> Color {
        if score >= 80 { return ViimColors.success }
        if score >= 60 { return ViimColors.warning }
        return ViimColors.danger
    }
}

private struct ScoreCriterionCard: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let score: Int
    var animate = true

    var body: some View {
        ViimCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(titleKey, systemImage: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    Spacer()
                    ViimChip(titleKey: "driving.score.partialChip", style: .neutral)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(score))
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .foregroundStyle(color(for: score))
                        .contentTransition(.numericText())
                    Text("driving.criteria.speed.unit")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ViimColors.muted)
                }

                Text(detailKey)
                    .font(.caption)
                    .foregroundStyle(ViimColors.muted)
                    .fixedSize(horizontal: false, vertical: true)

                AnimatedProgressBar(
                    progress: CGFloat(score) / 100,
                    color: color(for: score),
                    animate: animate
                )
            }
        }
    }

    private func color(for score: Int) -> Color {
        if score >= 80 { return ViimColors.success }
        if score >= 60 { return ViimColors.warning }
        return ViimColors.danger
    }
}

private struct UpcomingCriterionCard: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey

    var body: some View {
        ViimCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(titleKey, systemImage: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    Spacer()
                    ViimChip(titleKey: "driving.criteria.comingSoon", style: .warning)
                }

                Text(detailKey)
                    .font(.caption)
                    .foregroundStyle(ViimColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AnimatedProgressBar: View {
    let progress: CGFloat
    let color: Color
    var animate = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0xE3EAF1))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.75), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: animate ? max(8, proxy.size.width * min(max(progress, 0), 1)) : 8)
            }
        }
        .frame(height: 8)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
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
