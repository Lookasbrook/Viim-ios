import SwiftUI
import UIKit

struct ViimCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(ViimColors.text)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: ViimColors.text.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

/// Apparition en cascade des cartes d'un ecran : chaque carte glisse et
/// apparait avec un leger delai selon son rang, pour une entree premium sans
/// ralentir l'acces au contenu.
private struct StaggeredAppearModifier: ViewModifier {
    let visible: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.85)
                    .delay(Double(index) * 0.05),
                value: visible
            )
    }
}

extension View {
    func staggeredAppear(_ visible: Bool, index: Int) -> some View {
        modifier(StaggeredAppearModifier(visible: visible, index: index))
    }

    /// Les claviers numeriques et telephoniques iOS n'affichent pas de touche
    /// Retour. Ce bouton commun garantit que chaque formulaire Viim reste
    /// quittable, y compris sur les petits ecrans.
    func viimKeyboardDismissal() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common.done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
    }
}

/// Pastille d'etat qui pulse doucement : reservee aux etats reellement actifs
/// (trajet en cours, detection GPS), jamais aux etats statiques.
struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 14, height: 14)
                .scaleEffect(isPulsing ? 1.6 : 0.8)
                .opacity(isPulsing ? 0 : 0.9)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct ViimBrandMark: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Viim")
                .foregroundStyle(ViimColors.navy)
            Text(".")
                .foregroundStyle(ViimColors.gold)
        }
        .font(.system(size: 20, weight: .heavy, design: .rounded))
        .accessibilityLabel("Viim")
    }
}

struct ViimChip: View {
    let titleKey: LocalizedStringKey
    let style: Style

    enum Style {
        case success
        case warning
        case danger
        case neutral

        var foreground: Color {
            switch self {
            case .success: ViimColors.success
            case .warning: ViimColors.warning
            case .danger: ViimColors.danger
            case .neutral: ViimColors.blue
            }
        }

        var background: Color {
            switch self {
            case .success: Color(hex: 0xE2F5EA)
            case .warning: Color(hex: 0xFDEBD7)
            case .danger: Color(hex: 0xFBE5E5)
            case .neutral: Color(hex: 0xEDF5FC)
            }
        }
    }

    var body: some View {
        Text(titleKey)
            .font(.caption2.weight(.bold))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(style.background)
            .clipShape(Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

struct VehicleIllustration: View {
    let type: VehicleType
    var width: CGFloat = 150

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color(hex: 0xE1EAF2))
                .frame(width: width * 0.8, height: width * 0.05)
                .offset(y: width * 0.23)

            switch type {
            case .moto:
                motorcycle
            case .voiture:
                car
            case .velo:
                bicycle
            }
        }
        .frame(width: width, height: width * 0.56)
        .accessibilityHidden(true)
    }

    private var motorcycle: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                Circle()
                    .stroke(ViimColors.navy, lineWidth: w * 0.035)
                    .frame(width: w * 0.22, height: w * 0.22)
                    .position(x: w * 0.24, y: h * 0.72)
                Circle()
                    .fill(ViimColors.navy)
                    .frame(width: w * 0.07, height: w * 0.07)
                    .position(x: w * 0.24, y: h * 0.72)
                Circle()
                    .stroke(ViimColors.navy, lineWidth: w * 0.035)
                    .frame(width: w * 0.22, height: w * 0.22)
                    .position(x: w * 0.76, y: h * 0.72)
                Circle()
                    .fill(ViimColors.navy)
                    .frame(width: w * 0.07, height: w * 0.07)
                    .position(x: w * 0.76, y: h * 0.72)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.24, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.41, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.72))
                }
                .stroke(ViimColors.blue, style: StrokeStyle(lineWidth: w * 0.04, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.64, y: h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.25))
                    path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.25))
                }
                .stroke(ViimColors.blue, style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round, lineJoin: .round))

                RoundedRectangle(cornerRadius: 5)
                    .fill(ViimColors.navy)
                    .frame(width: w * 0.18, height: h * 0.11)
                    .position(x: w * 0.53, y: h * 0.34)
                RoundedRectangle(cornerRadius: 6)
                    .fill(ViimColors.gold)
                    .frame(width: w * 0.14, height: h * 0.13)
                    .position(x: w * 0.38, y: h * 0.58)
            }
        }
    }

    private var car: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                RoundedRectangle(cornerRadius: w * 0.08)
                    .fill(ViimColors.blue)
                    .frame(width: w * 0.72, height: h * 0.30)
                    .position(x: w * 0.50, y: h * 0.60)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.30, y: h * 0.56))
                    path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.35))
                    path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.35))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.56))
                }
                .fill(ViimColors.navy)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: w * 0.15, height: h * 0.12)
                    .position(x: w * 0.45, y: h * 0.45)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: w * 0.15, height: h * 0.12)
                    .position(x: w * 0.60, y: h * 0.45)
                Circle()
                    .fill(ViimColors.navy)
                    .frame(width: w * 0.14, height: w * 0.14)
                    .position(x: w * 0.32, y: h * 0.74)
                Circle()
                    .fill(ViimColors.navy)
                    .frame(width: w * 0.14, height: w * 0.14)
                    .position(x: w * 0.70, y: h * 0.74)
            }
        }
    }

    private var bicycle: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                Circle()
                    .stroke(ViimColors.green, lineWidth: w * 0.035)
                    .frame(width: w * 0.24, height: w * 0.24)
                    .position(x: w * 0.25, y: h * 0.72)
                Circle()
                    .stroke(ViimColors.green, lineWidth: w * 0.035)
                    .frame(width: w * 0.24, height: w * 0.24)
                    .position(x: w * 0.75, y: h * 0.72)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.25, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.45, y: h * 0.48))
                    path.addLine(to: CGPoint(x: w * 0.57, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.72))
                    path.move(to: CGPoint(x: w * 0.45, y: h * 0.48))
                    path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.72))
                    path.move(to: CGPoint(x: w * 0.57, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.42))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.42))
                }
                .stroke(ViimColors.navy, style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct MetricGrid: View {
    let metrics: [Metric]

    struct Metric: Identifiable {
        let id = UUID()
        let valueKey: LocalizedStringKey
        let labelKey: LocalizedStringKey
        var color: Color = ViimColors.text
        var isLarge = false
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
            ForEach(metrics) { metric in
                VStack(spacing: 2) {
                    Text(metric.valueKey)
                        .font(metric.isLarge ? .system(size: 34, weight: .heavy) : .system(size: 17, weight: .bold))
                        .foregroundStyle(metric.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(metric.labelKey)
                        .font(.caption2)
                        .foregroundStyle(ViimColors.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct StatusRow: View {
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ViimColors.text)
                Text(detailKey)
                    .font(.caption)
                    .foregroundStyle(ViimColors.muted)
            }

            Spacer(minLength: 0)
        }
    }
}
