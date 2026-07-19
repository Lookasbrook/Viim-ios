import CoreLocation
import SwiftUI

/// Region de prevention deduite de la derniere position GPS connue. La liste
/// des zones a risque ONASER ne concerne que Ouagadougou : hors du Burkina,
/// l'app le dit au lieu d'afficher des rues d'une autre ville.
enum PreventionRegion: Equatable {
    case burkina
    case outsideBurkina
    case unknown

    // Boite englobante approximative du Burkina Faso, volontairement large :
    // mieux vaut montrer les reperes ONASER a un utilisateur frontalier que
    // les masquer a un utilisateur de Ouagadougou.
    private static let latitudeRange = 9.0...15.5
    private static let longitudeRange = (-6.0)...2.5

    static func classify(location: CLLocation?) -> PreventionRegion {
        guard let location, location.horizontalAccuracy >= 0 else {
            return .unknown
        }
        let coordinate = location.coordinate
        if latitudeRange.contains(coordinate.latitude), longitudeRange.contains(coordinate.longitude) {
            return .burkina
        }
        return .outsideBurkina
    }
}

struct PreventionView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var tripManager: TripManager
    @StateObject private var maintenanceStore = MaintenanceStore()
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    PreventionHero()
                        .staggeredAppear(hasAppeared, index: 0)

                    // Zones a risque selon la region reelle de l'utilisateur.
                    // La liste ONASER ne concerne que Ouagadougou : hors du
                    // Burkina (ex. Quebec), on l'explique au lieu d'afficher
                    // des rues d'une autre ville. Aucune alerte temps reel
                    // n'existe encore : le chip ne doit pas pretendre le
                    // contraire.
                    Group {
                    switch region {
                    case .burkina:
                        ViimCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("prevention.dangerZones.title", systemImage: "exclamationmark.triangle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(ViimColors.text)
                                    Spacer()
                                    ViimChip(titleKey: "prevention.dangerZones.referenceChip", style: .neutral)
                                }
                                Text("prevention.dangerZones.source")
                                    .font(.caption)
                                    .foregroundStyle(ViimColors.muted)
                                DangerZoneRow(titleKey: "prevention.zone.jeunes", detailKey: "prevention.zone.rank1", tint: ViimColors.red)
                                DangerZoneRow(titleKey: "prevention.zone.insurrection", detailKey: "prevention.zone.rank2", tint: ViimColors.red)
                                DangerZoneRow(titleKey: "prevention.zone.bassawarga", detailKey: "prevention.zone.rank3", tint: ViimColors.warning)
                                Text("prevention.dangerZones.upcoming")
                                    .font(.caption2)
                                    .foregroundStyle(ViimColors.muted)
                                    .padding(.top, 2)
                            }
                        }
                    case .outsideBurkina:
                        ViimCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("prevention.dangerZones.outside.title", systemImage: "mappin.and.ellipse")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(ViimColors.text)
                                    Spacer()
                                    ViimChip(titleKey: "prevention.dangerZones.outside.chip", style: .neutral)
                                }
                                Text("prevention.dangerZones.outside.detail")
                                    .font(.caption)
                                    .foregroundStyle(ViimColors.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    case .unknown:
                        ViimCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("prevention.dangerZones.title", systemImage: "exclamationmark.triangle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(ViimColors.text)
                                    Spacer()
                                    ViimChip(titleKey: "prevention.dangerZones.unknown.chip", style: .warning)
                                }
                                Text("prevention.dangerZones.unknown.detail")
                                    .font(.caption)
                                    .foregroundStyle(ViimColors.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    }
                    .staggeredAppear(hasAppeared, index: 1)

                    roadAdviceCard
                        .staggeredAppear(hasAppeared, index: 2)

                    MaintenanceCard(
                        vehicleName: vehicleName,
                        currentOdometerKm: currentOdometerKm,
                        maintenanceStore: maintenanceStore
                    )
                    .staggeredAppear(hasAppeared, index: 3)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("prevention.challenge.title", systemImage: "trophy.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ViimColors.green)
                            Spacer()
                            ViimChip(
                                titleKey: challengeCompletedCount >= 5 ? "prevention.challenge.done" : "prevention.challenge.active",
                                style: challengeCompletedCount >= 5 ? .success : .neutral
                            )
                        }
                        Text("prevention.challenge.detail")
                            .font(.caption)
                            .foregroundStyle(ViimColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        ChallengeDots(completed: challengeCompletedCount, total: 5, animate: hasAppeared)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xEFFAF3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: 0xCBEBD8), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .staggeredAppear(hasAppeared, index: 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(ViimColors.background.ignoresSafeArea())
            .navigationTitle("prevention.title")
            .onAppear {
                guard !hasAppeared else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                    hasAppeared = true
                }
            }
            .task(id: onboardingStore.profile?.vehicleType.rawValue) {
                if let vehicleType = onboardingStore.profile?.vehicleType {
                    maintenanceStore.configure(vehicleType: vehicleType)
                }
                // Sans position fraiche, la region resterait "inconnue" et
                // les zones a risque ne s'adapteraient pas au pays reel.
                locationService.prepareForForegroundUse()
                locationService.requestCurrentLocation()
            }
        }
    }

    private var region: PreventionRegion {
        PreventionRegion.classify(location: locationService.latestLocation)
    }

    private var roadAdviceCard: some View {
        ViimCard {
            VStack(alignment: .leading, spacing: 4) {
                Label("prevention.road.title", systemImage: "road.lanes")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ViimColors.text)
                    .padding(.bottom, 4)
                PreventionListRow(icon: "cloud.rain.fill", titleKey: "prevention.weather.rainySeason.generic", detailKey: "prevention.weather.rainySeason.advice", tint: ViimColors.blue)
                if region == .burkina {
                    PreventionListRow(icon: "wind", titleKey: "prevention.weather.harmattan", detailKey: "prevention.weather.harmattan.advice", tint: ViimColors.warning)
                }
                PreventionListRow(icon: "moon.fill", titleKey: "prevention.weather.night", detailKey: "prevention.weather.night.advice", tint: ViimColors.navy, showsDivider: false)
            }
        }
    }

    private var vehicleName: String {
        guard let profile = onboardingStore.profile else {
            return String(localized: "prevention.maintenance.vehicleFallback")
        }
        return profile.vehicleDisplayName
    }

    private var currentOdometerKm: Double? {
        tripManager.currentOdometerKm(profile: onboardingStore.profile)
    }

    /// Defi actif : parmi les 5 derniers trajets valides, ceux conduits sans
    /// exces de vitesse (score vitesse >= 90).
    private var challengeCompletedCount: Int {
        tripManager.recentTrips
            .prefix(5)
            .filter { ($0.scoreVitesse ?? 0) >= 90 }
            .count
    }
}

private struct MaintenanceCard: View {
    let vehicleName: String
    let currentOdometerKm: Double?
    @ObservedObject var maintenanceStore: MaintenanceStore

    var body: some View {
        ViimCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("prevention.maintenance.title", systemImage: "wrench.and.screwdriver.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ViimColors.text)
                    Spacer()
                    ViimChip(
                        titleKey: currentOdometerKm == nil ? "prevention.maintenance.odometerMissing" : "prevention.maintenance.trackingActive",
                        style: currentOdometerKm == nil ? .warning : .success
                    )
                }

                Text(verbatim: vehicleName)
                    .font(.caption)
                    .foregroundStyle(ViimColors.muted)
                    .lineLimit(2)

                if let currentOdometerKm {
                    Text(odometerText(currentOdometerKm))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ViimColors.text)
                } else {
                    Text("prevention.maintenance.needsOdometer")
                        .font(.caption)
                        .foregroundStyle(ViimColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(maintenanceStore.tasks) { task in
                    MaintenanceTaskRow(
                        task: task,
                        status: MaintenanceStatus.compute(task: task, currentOdometerKm: currentOdometerKm),
                        canMarkDone: currentOdometerKm != nil
                    ) {
                        if let currentOdometerKm {
                            maintenanceStore.markServiced(kind: task.kind, atOdometerKm: currentOdometerKm)
                        }
                    }
                }
            }
        }
    }

    private func odometerText(_ kilometers: Double) -> String {
        String.localizedStringWithFormat(
            String(localized: "prevention.maintenance.odometerFormat"),
            kilometers
        )
    }
}

private struct MaintenanceTaskRow: View {
    let task: MaintenanceTaskState
    let status: MaintenanceStatus
    let canMarkDone: Bool
    let onMarkDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.kind.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(statusTint)
                .frame(width: 24, height: 24)
                .background(statusTint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(task.kind.titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ViimColors.text)
                Text(statusText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusTint)
            }

            Spacer(minLength: 8)

            if canMarkDone {
                Button {
                    onMarkDone()
                } label: {
                    Text("prevention.maintenance.markDone")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(ViimColors.green)
            }
        }
        .frame(minHeight: 34)
    }

    private var statusTint: Color {
        switch status {
        case .needsOdometer, .notTracked:
            return ViimColors.muted
        case .ok:
            return ViimColors.green
        case .dueSoon:
            return ViimColors.warning
        case .overdue:
            return ViimColors.red
        }
    }

    private var statusText: String {
        switch status {
        case .needsOdometer:
            return String(localized: "prevention.maintenance.status.needsOdometer")
        case .notTracked:
            return String(localized: "prevention.maintenance.status.notTracked")
        case .ok(let remainingKm):
            return String.localizedStringWithFormat(
                String(localized: "prevention.maintenance.status.okFormat"),
                remainingKm
            )
        case .dueSoon(let remainingKm):
            return String.localizedStringWithFormat(
                String(localized: "prevention.maintenance.status.dueSoonFormat"),
                remainingKm
            )
        case .overdue(let kmOverdue):
            return String.localizedStringWithFormat(
                String(localized: "prevention.maintenance.status.overdueFormat"),
                kmOverdue
            )
        }
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
        .shadow(color: ViimColors.text.opacity(0.10), radius: 8, x: 0, y: 4)
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
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleKey)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ViimColors.text)
                    Text(detailKey)
                        .font(.caption)
                        .foregroundStyle(ViimColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)

            if showsDivider {
                Divider()
                    .padding(.leading, 45)
            }
        }
    }
}

private struct ChallengeDots: View {
    let completed: Int
    let total: Int
    var animate = true

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed ? ViimColors.green : Color(hex: 0xDDEFE4))
                    .overlay(
                        Circle()
                            .stroke(ViimColors.green.opacity(index < completed ? 0 : 0.35), lineWidth: 1)
                    )
                    .frame(width: 14, height: 14)
                    .scaleEffect(animate ? 1 : 0.4)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.06),
                        value: animate
                    )
            }
            Spacer()
            Text(progressText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(ViimColors.muted)
        }
    }

    private var progressText: String {
        String.localizedStringWithFormat(
            String(localized: "prevention.challenge.progressFormat"),
            completed,
            total
        )
    }
}
