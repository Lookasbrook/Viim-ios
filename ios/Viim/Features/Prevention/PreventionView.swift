import CoreLocation
import SwiftUI
import UIKit

/// Region de prevention deduite de la derniere position GPS connue, sans
/// aucun appel reseau (boites englobantes embarquees) : les zones a risque
/// s'adaptent au pays reel meme hors connexion. La liste ONASER ne concerne
/// que Ouagadougou ; le Canada a ses propres reperes embarques ; ailleurs,
/// l'app l'explique au lieu d'afficher des rues d'une autre ville.
enum PreventionRegion: Equatable {
    case burkina
    case canada
    case outsideKnownRegions
    case unknown

    // Boites englobantes volontairement larges : mieux vaut montrer les
    // reperes regionaux a un utilisateur frontalier que les masquer.
    private static let burkinaLatitudeRange = 9.0...15.5
    private static let burkinaLongitudeRange = (-6.0)...2.5
    private static let canadaLatitudeRange = 41.5...84.0
    private static let canadaLongitudeRange = (-141.0)...(-52.0)
    private static let maximumRegionAccuracyMeters: CLLocationAccuracy = 10_000
    private static let maximumLocationAge: TimeInterval = 15 * 60

    static func classify(location: CLLocation?, now: Date = Date()) -> PreventionRegion {
        guard let location,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumRegionAccuracyMeters,
              abs(now.timeIntervalSince(location.timestamp)) <= maximumLocationAge else {
            return .unknown
        }
        let coordinate = location.coordinate
        if burkinaLatitudeRange.contains(coordinate.latitude), burkinaLongitudeRange.contains(coordinate.longitude) {
            return .burkina
        }
        if canadaLatitudeRange.contains(coordinate.latitude), canadaLongitudeRange.contains(coordinate.longitude) {
            return .canada
        }
        return .outsideKnownRegions
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
                    case .canada:
                        ViimCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("prevention.dangerZones.canada.title", systemImage: "exclamationmark.triangle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(ViimColors.text)
                                    Spacer()
                                    ViimChip(titleKey: "prevention.dangerZones.referenceChip", style: .neutral)
                                }
                                Text("prevention.dangerZones.canada.source")
                                    .font(.caption)
                                    .foregroundStyle(ViimColors.muted)
                                DangerZoneRow(titleKey: "prevention.zone.canada.blackIce", detailKey: "prevention.zone.canada.blackIce.season", tint: ViimColors.red)
                                DangerZoneRow(titleKey: "prevention.zone.canada.wildlife", detailKey: "prevention.zone.canada.wildlife.season", tint: ViimColors.red)
                                DangerZoneRow(titleKey: "prevention.zone.canada.construction", detailKey: "prevention.zone.canada.construction.season", tint: ViimColors.warning)
                                DangerZoneRow(titleKey: "prevention.zone.canada.school", detailKey: "prevention.zone.canada.school.season", tint: ViimColors.warning)
                                Text("prevention.dangerZones.canada.upcoming")
                                    .font(.caption2)
                                    .foregroundStyle(ViimColors.muted)
                                    .padding(.top, 2)
                            }
                        }
                    case .outsideKnownRegions:
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
                        maintenanceStore: maintenanceStore,
                        onDeclareOdometer: { value in
                            (try? onboardingStore.updateOdometer(baselineKm: value)) != nil
                        }
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
                if region == .canada {
                    PreventionListRow(icon: "snowflake", titleKey: "prevention.weather.winter", detailKey: "prevention.weather.winter.advice", tint: ViimColors.blue)
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
            .filter { $0.isTrustedForDisplay && ($0.scoreVitesse ?? 0) >= 90 }
            .count
    }
}

private struct MaintenanceCard: View {
    let vehicleName: String
    let currentOdometerKm: Double?
    @ObservedObject var maintenanceStore: MaintenanceStore
    let onDeclareOdometer: (Double) -> Bool
    @State private var odometerText = ""
    @State private var odometerEntryFailed = false
    @State private var editedTask: MaintenanceTaskState?

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
                    // Saisie directe : sans odometre, aucun rappel ne peut
                    // demarrer, autant le demander ici plutot que renvoyer
                    // l'utilisateur chercher la section dans Profil.
                    Text("prevention.maintenance.needsOdometer")
                        .font(.caption)
                        .foregroundStyle(ViimColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField("prevention.maintenance.odometer.placeholder", text: $odometerText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        Button {
                            declareOdometer()
                        } label: {
                            Text("prevention.maintenance.odometer.save")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(ViimColors.green)
                        .disabled(parsedOdometer == nil)
                    }
                    if odometerEntryFailed {
                        Text("profile.odometer.invalid")
                            .font(.caption2)
                            .foregroundStyle(ViimColors.danger)
                    }
                }

                ForEach(maintenanceStore.tasks) { task in
                    MaintenanceTaskRow(
                        task: task,
                        status: MaintenanceStatus.compute(task: task, currentOdometerKm: currentOdometerKm),
                        canMarkDone: currentOdometerKm != nil,
                        onMarkDone: {
                            if let currentOdometerKm {
                                maintenanceStore.markServiced(kind: task.kind, atOdometerKm: currentOdometerKm)
                            }
                        },
                        onEdit: {
                            editedTask = task
                        }
                    )
                }

                Text("prevention.maintenance.editHint")
                    .font(.caption2)
                    .foregroundStyle(ViimColors.muted)
                    .padding(.top, 2)
            }
        }
        .viimKeyboardDismissal()
        .sheet(item: $editedTask) { task in
            MaintenanceTaskEditorSheet(
                task: task,
                currentOdometerKm: currentOdometerKm,
                maintenanceStore: maintenanceStore
            )
            .presentationDetents([.medium])
        }
    }

    private var parsedOdometer: Double? {
        Self.parseKilometers(odometerText)
    }

    private func declareOdometer() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        guard let value = parsedOdometer, onDeclareOdometer(value) else {
            odometerEntryFailed = true
            return
        }
        odometerEntryFailed = false
        odometerText = ""
    }

    static func parseKilometers(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value >= 0, value < 3_000_000 else {
            return nil
        }
        return value
    }

    private func odometerText(_ kilometers: Double) -> String {
        String.localizedStringWithFormat(
            String(localized: "prevention.maintenance.odometerFormat"),
            kilometers
        )
    }
}

/// Fiche d'une tache d'entretien : l'utilisateur renseigne le kilometrage du
/// dernier entretien et ajuste l'intervalle. Tout est stocke localement,
/// aucun reseau requis.
private struct MaintenanceTaskEditorSheet: View {
    let task: MaintenanceTaskState
    let currentOdometerKm: Double?
    @ObservedObject var maintenanceStore: MaintenanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var intervalText = ""
    @State private var lastServiceText = ""
    @State private var entryFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("prevention.maintenance.editor.interval.placeholder", text: $intervalText)
                            .keyboardType(.numberPad)
                        Text(verbatim: "km")
                            .foregroundStyle(ViimColors.muted)
                    }
                } header: {
                    Text("prevention.maintenance.editor.interval")
                } footer: {
                    Text("prevention.maintenance.editor.interval.help")
                }

                Section {
                    HStack {
                        TextField("prevention.maintenance.editor.lastService.placeholder", text: $lastServiceText)
                            .keyboardType(.numberPad)
                        Text(verbatim: "km")
                            .foregroundStyle(ViimColors.muted)
                    }

                    if let currentOdometerKm {
                        Button("prevention.maintenance.editor.doneNow") {
                            lastServiceText = String(Int(currentOdometerKm.rounded()))
                        }
                    }
                } header: {
                    Text("prevention.maintenance.editor.lastService")
                } footer: {
                    Text("prevention.maintenance.editor.lastService.help")
                }

                if entryFailed {
                    Text("profile.odometer.invalid")
                        .foregroundStyle(ViimColors.danger)
                        .font(.footnote)
                }

                Section {
                    Button("prevention.maintenance.editor.save") {
                        save()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .viimKeyboardDismissal()
            .navigationTitle(task.kind.titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                intervalText = String(Int(task.intervalKm.rounded()))
                if let lastServiceOdometerKm = task.lastServiceOdometerKm {
                    lastServiceText = String(Int(lastServiceOdometerKm.rounded()))
                }
            }
        }
    }

    private func save() {
        guard let interval = MaintenanceCard.parseKilometers(intervalText), interval >= 100 else {
            entryFailed = true
            return
        }

        let lastService = lastServiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : MaintenanceCard.parseKilometers(lastServiceText)
        if !lastServiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, lastService == nil {
            entryFailed = true
            return
        }

        maintenanceStore.updateInterval(kind: task.kind, intervalKm: interval)
        if let lastService {
            maintenanceStore.markServiced(kind: task.kind, atOdometerKm: lastService)
        }
        dismiss()
    }
}

private struct MaintenanceTaskRow: View {
    let task: MaintenanceTaskState
    let status: MaintenanceStatus
    let canMarkDone: Bool
    let onMarkDone: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onEdit()
            } label: {
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

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ViimColors.muted.opacity(0.7))
                }
            }
            .buttonStyle(.plain)

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
