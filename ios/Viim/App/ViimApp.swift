import Combine
import SwiftUI
import UIKit

@main
struct ViimApp: App {
    private let persistenceController: PersistenceController
    private let persistenceRecoveryState: PersistenceRecoveryState?

    @StateObject private var onboardingStore: OnboardingStore
    @StateObject private var locationService: LocationService
    @StateObject private var motionActivityService: MotionActivityService
    @StateObject private var networkStatusService: NetworkStatusService
    @StateObject private var protectionReadinessService: ProtectionReadinessService
    @StateObject private var tripManager: TripManager
    @StateObject private var tripRecorder: TripRecorder
    @StateObject private var tripDetectionCoordinator: TripDetectionCoordinator
    @StateObject private var collisionCalibrationReviewStore: CollisionCalibrationReviewStore

    init() {
        ViimDiagnostics.logBuildIdentity()
        let persistenceBootstrap = PersistenceController.bootstrap()
        let persistenceController: PersistenceController
        let persistenceRecoveryState: PersistenceRecoveryState?
        switch persistenceBootstrap {
        case .ready(let controller):
            persistenceController = controller
            persistenceRecoveryState = nil
        case .recoveryRequired(let state):
            // Store volatile reserve exclusivement a la construction de
            // l'ecran de recuperation. Le store original n'est ni remplace ni
            // supprime, et aucun service de collecte n'est demarre ci-dessous.
            persistenceController = PersistenceController(inMemory: true)
            persistenceRecoveryState = state
        }
        let context = persistenceController.container.viewContext
        let activeTripJournal = ActiveTripJournal(context: context)
        let collectionHealthJournal = CollectionHealthJournal()
        let tripManager = TripManager(
            store: TripStore(context: context)
        )
        let onboardingStore = OnboardingStore()
        let tripRecorder = TripRecorder(
            journal: activeTripJournal,
            tripManager: tripManager,
            collectionHealthJournal: collectionHealthJournal
        )

        // Recuperer les brouillons avant d'instancier CLLocationManager. La
        // pose de son delegate peut livrer immediatement un reveil passif et
        // creer un nouveau candidat pendant le lancement.
        if persistenceRecoveryState == nil, let profile = onboardingStore.profile {
            tripRecorder.configure(
                profile: profile,
                fuelSettings: onboardingStore.fuelSettings
            )
        }
        if persistenceRecoveryState == nil {
            tripRecorder.recoverActiveTrips()
        }

        CarburantFeatureFlags.clearPersistedDebugOverrides()
        let carburantFeatureFlags = CarburantFeatureFlags.resolved()
        ViimDiagnostics.log("carburant.featureFlags \(carburantFeatureFlags.diagnosticSummary)")
        let locationService = LocationService(
            activeTripJournal: activeTripJournal,
            collectionHealthJournal: collectionHealthJournal,
            carburantFeatureFlags: carburantFeatureFlags
        )
        let motionActivityService = MotionActivityService(
            collectionHealthJournal: collectionHealthJournal
        )
        let networkStatusService = NetworkStatusService()
        let protectionReadinessService = ProtectionReadinessService(
            locationService: locationService,
            networkStatusService: networkStatusService,
            collectionHealthJournal: collectionHealthJournal,
            staleActiveDraftProvider: {
                guard let drafts = try? activeTripJournal.activeDrafts() else {
                    return true
                }
                return drafts.contains {
                    $0.phase == .active &&
                        TripRecorder.isActiveDraftStale(
                            lastUpdatedAt: $0.lastUpdatedAt,
                            now: Date()
                        )
                }
            }
        )
        let collisionShadowJournal = CollisionShadowJournal()
        let collisionShadowCoverageJournal = CollisionShadowCoverageJournal()
        let collisionShadowMonitor = CollisionShadowMonitor(
            journal: collisionShadowJournal,
            coverageJournal: collisionShadowCoverageJournal
        )
        let collisionCalibrationReviewStore = CollisionCalibrationReviewStore(
            candidateJournal: collisionShadowJournal,
            coverageJournal: collisionShadowCoverageJournal
        )
        if persistenceRecoveryState == nil, let profile = onboardingStore.profile {
            // Un lancement de fond peut ne jamais creer de vue. Le type de
            // vehicule doit donc etre connu avant toute activation capteur.
            collisionShadowMonitor.configure(vehicleType: profile.vehicleType)
        }
        let tripDetectionCoordinator = TripDetectionCoordinator(
            locationService: locationService,
            motionActivityService: motionActivityService,
            tripRecorder: tripRecorder,
            collisionShadowMonitor: collisionShadowMonitor
        )

        // Cablage headless : quand iOS relance l'app en arriere-plan (reveil
        // localisation), aucune vue n'existe encore. La recuperation des
        // trajets journalises et l'observation des trajets termines doivent
        // donc etre branchees ici, pas dans une vue.
        if persistenceRecoveryState == nil, let profile = onboardingStore.profile {
            locationService.configure(vehicleType: profile.vehicleType)
        }
        if persistenceRecoveryState == nil {
            tripRecorder.observe(locationService: locationService)
            locationService.restoreAutomaticTrackingSession()
        }

        self.persistenceController = persistenceController
        self.persistenceRecoveryState = persistenceRecoveryState
        _onboardingStore = StateObject(wrappedValue: onboardingStore)
        _locationService = StateObject(wrappedValue: locationService)
        _motionActivityService = StateObject(wrappedValue: motionActivityService)
        _networkStatusService = StateObject(wrappedValue: networkStatusService)
        _protectionReadinessService = StateObject(wrappedValue: protectionReadinessService)
        _tripManager = StateObject(
            wrappedValue: tripManager
        )
        _tripRecorder = StateObject(wrappedValue: tripRecorder)
        _tripDetectionCoordinator = StateObject(wrappedValue: tripDetectionCoordinator)
        _collisionCalibrationReviewStore = StateObject(
            wrappedValue: collisionCalibrationReviewStore
        )
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView(persistenceRecoveryState: persistenceRecoveryState)
                .environmentObject(onboardingStore)
                .environmentObject(locationService)
                .environmentObject(motionActivityService)
                .environmentObject(protectionReadinessService)
                .environmentObject(tripManager)
                .environmentObject(tripRecorder)
                .environmentObject(tripDetectionCoordinator)
                .environmentObject(collisionCalibrationReviewStore)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                // La charte Viim est une palette claire fixe (cartes blanches,
                // fonds clairs). Sans ce verrou, iOS applique des barres et
                // champs sombres par-dessus, source des textes illisibles.
                .preferredColorScheme(.light)
        }
    }
}

private struct AppLaunchView: View {
    let persistenceRecoveryState: PersistenceRecoveryState?
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var motionActivityService: MotionActivityService
    @EnvironmentObject private var tripManager: TripManager
    @EnvironmentObject private var tripRecorder: TripRecorder
    @EnvironmentObject private var tripDetectionCoordinator: TripDetectionCoordinator
    @EnvironmentObject private var protectionReadinessService: ProtectionReadinessService

    var body: some View {
        Group {
            if let persistenceRecoveryState {
                PersistenceRecoveryView(state: persistenceRecoveryState)
            } else if onboardingStore.isCompleted {
                RootTabView()
                    .task(id: recordingConfigurationID) {
                        guard let profile = onboardingStore.profile else {
                            tripDetectionCoordinator.stop()
                            return
                        }
                        tripDetectionCoordinator.configure(
                            profile: profile,
                            fuelSettings: onboardingStore.fuelSettings
                        )
                    }
            } else {
                OnboardingView()
            }
        }
        .onChange(of: scenePhase) { phase in
            guard persistenceRecoveryState == nil,
                  phase == .active,
                  onboardingStore.isCompleted else {
                return
            }
            locationService.prepareForForegroundUse()
            protectionReadinessService.refreshEmergencyContacts()
            protectionReadinessService.refreshCollectionHealth()
        }
        .onChange(of: onboardingStore.isCompleted) { isCompleted in
            guard persistenceRecoveryState == nil, isCompleted else { return }
            protectionReadinessService.refreshEmergencyContacts()
            protectionReadinessService.refreshCollectionHealth()
            locationService.prepareForForegroundUse()
        }
    }

    private var recordingConfigurationID: String {
        guard let profile = onboardingStore.profile else {
            return "none"
        }
        let settings = onboardingStore.fuelSettings
        return [
            profile.vehicleType.rawValue,
            profile.vehicleBrand,
            profile.vehicleModel,
            profile.vehicleYear,
            profile.fuelType?.rawValue ?? "legacy",
            settings.currency.rawValue,
            String(settings.pricePerLiter),
            settings.source?.rawValue ?? "legacy",
            settings.fuelType?.rawValue ?? "legacy",
            settings.capturedAt.map { String($0.timeIntervalSince1970) } ?? "undated",
            settings.sourceIdentifier ?? "no-source",
            settings.sourceURL?.absoluteString ?? "no-url",
            settings.locality ?? "no-locality"
        ].joined(separator: "|")
    }

}

private struct PersistenceRecoveryView: View {
    let state: PersistenceRecoveryState
    @State private var recoveryExport: RawPersistenceSnapshot?
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.fill.badge.exclamationmark")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(ViimColors.danger)
            Text("persistence.recovery.title")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("persistence.recovery.detail")
                .font(.body)
                .foregroundStyle(ViimColors.muted)
                .multilineTextAlignment(.center)
            Text(state.diagnosticSummary)
                .font(.caption.monospaced())
                .foregroundStyle(ViimColors.muted)
                .textSelection(.enabled)
            Button {
                exportStoreFamily()
            } label: {
                Label("persistence.recovery.export", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ViimColors.blue)
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(ViimColors.danger)
                    .multilineTextAlignment(.center)
            }
            Text("persistence.recovery.action")
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .accessibilityElement(children: .contain)
        .sheet(item: $recoveryExport) { snapshot in
            RecoveryShareSheet(activityItems: snapshot.fileURLs)
        }
    }

    private func exportStoreFamily() {
        do {
            recoveryExport = try PersistenceController.createRecoveryExport(state: state)
            exportError = nil
            ViimDiagnostics.log("persistence.recovery.export created=true")
        } catch {
            let nsError = error as NSError
            exportError = String(localized: "persistence.recovery.exportError")
            ViimDiagnostics.log(
                "persistence.recovery.export created=false domain=\(nsError.domain) code=\(nsError.code)"
            )
        }
    }
}

private struct RecoveryShareSheet: UIViewControllerRepresentable {
    let activityItems: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

@MainActor
final class TripDetectionCoordinator: ObservableObject {
    private let locationService: LocationService
    private let motionActivityService: MotionActivityService
    private let tripRecorder: TripRecorder
    private let collisionShadowMonitor: CollisionShadowMonitor
    private var stationaryFinalizationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        locationService: LocationService,
        motionActivityService: MotionActivityService,
        tripRecorder: TripRecorder,
        collisionShadowMonitor: CollisionShadowMonitor = CollisionShadowMonitor()
    ) {
        self.locationService = locationService
        self.motionActivityService = motionActivityService
        self.tripRecorder = tripRecorder
        self.collisionShadowMonitor = collisionShadowMonitor

        motionActivityService.$phase
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.reconcileAutomaticTracking()
                }
            }
            .store(in: &cancellables)

        locationService.$latestLocation
            .sink { [weak collisionShadowMonitor] location in
                collisionShadowMonitor?.updateLocation(location)
            }
            .store(in: &cancellables)

        locationService.$activeTrip
            .map { trip in
                trip.map {
                    CollisionShadowTripContext(id: $0.id, startedAt: $0.startedAt)
                }
            }
            .removeDuplicates()
            .sink { [weak collisionShadowMonitor] context in
                collisionShadowMonitor?.setActiveTrip(context: context)
            }
            .store(in: &cancellables)

        locationService.$isMonitoring
            .removeDuplicates()
            .sink { [weak collisionShadowMonitor] isActive in
                collisionShadowMonitor?.setLocationCollectionActive(isActive)
            }
            .store(in: &cancellables)
    }

    func configure(profile: UserProfile, fuelSettings: FuelSettings) {
        tripRecorder.configure(profile: profile, fuelSettings: fuelSettings)
        tripRecorder.observe(locationService: locationService)
        locationService.configure(vehicleType: profile.vehicleType)
        collisionShadowMonitor.configure(vehicleType: profile.vehicleType)
        collisionShadowMonitor.updateLocation(locationService.latestLocation)
        collisionShadowMonitor.setLocationCollectionActive(locationService.isMonitoring)
        collisionShadowMonitor.setActiveTrip(
            context: locationService.activeTrip.map {
                CollisionShadowTripContext(id: $0.id, startedAt: $0.startedAt)
            }
        )
        locationService.prepareForForegroundUse()
        motionActivityService.startAutoDetection(vehicleType: profile.vehicleType)
        reconcileAutomaticTracking()
    }

    func stop() {
        stationaryFinalizationTask?.cancel()
        stationaryFinalizationTask = nil
        motionActivityService.stopAutoDetection()
        collisionShadowMonitor.stop()
        locationService.stopMonitoring(keepPassiveWakeups: false)
    }

    private func reconcileAutomaticTracking() {
        ViimDiagnostics.log("motion.phase \(motionActivityService.phase)")

        // CoreMotion indisponible ou refuse : bascule sur la detection GPS
        // pure. Le demarrage de trajet (10 km/h soutenus 30 s) et le failsafe
        // d'inactivite de LocationService gerent seuls le cycle marche/arret.
        if motionActivityService.phase == .unavailable {
            stationaryFinalizationTask?.cancel()
            stationaryFinalizationTask = nil

            if !locationService.isMonitoring {
                ViimDiagnostics.log("motion.unavailable.gpsFallback")
                locationService.startMonitoring()
            }
            return
        }

        if motionActivityService.phase.shouldTriggerLocationMonitoring {
            if locationService.shouldFinalizeDespiteMotionMovement {
                stationaryFinalizationTask?.cancel()
                stationaryFinalizationTask = nil
                ViimDiagnostics.log("trip.stationaryFinalize.gpsOverrideMotion")
                locationService.finishActiveTripAfterStationaryMotion()
                return
            }

            stationaryFinalizationTask?.cancel()
            stationaryFinalizationTask = nil

            if !locationService.isMonitoring {
                ViimDiagnostics.log("motion.triggerLocationMonitoring")
                locationService.startMonitoring()
            }
            return
        }

        guard motionActivityService.phase == .stationary else {
            stationaryFinalizationTask?.cancel()
            stationaryFinalizationTask = nil
            return
        }

        if locationService.activeTrip != nil {
            scheduleStationaryTripFinalization()
            return
        }

        guard locationService.isMonitoring,
              locationService.tripPhase == .idle else {
            return
        }

        // CoreMotion peut annoncer stationnaire a un feu rouge ou pendant que
        // iOS livre les points GPS au compte-gouttes. Si un deplacement recent
        // est prouve par les points recus, ne pas couper la session : le
        // failsafe d'inactivite de LocationService fera l'arret si le calme
        // se confirme.
        if locationService.shouldDeferStationaryStop {
            ViimDiagnostics.log("motion.stationaryStop.deferred reason=armingOrMovement")
            return
        }

        ViimDiagnostics.log("motion.stationaryStopLocationMonitoring")
        locationService.stopMonitoring()
    }

    private func scheduleStationaryTripFinalization() {
        guard stationaryFinalizationTask == nil else {
            return
        }

        stationaryFinalizationTask = Task { @MainActor in
            ViimDiagnostics.log("trip.stationaryFinalize.scheduled")
            try? await Task.sleep(nanoseconds: 90_000_000_000)

            guard !Task.isCancelled,
                  motionActivityService.phase == .stationary else {
                ViimDiagnostics.log("trip.stationaryFinalize.cancelled")
                return
            }

            locationService.finishActiveTripAfterStationaryMotion()
            stationaryFinalizationTask = nil
        }
    }
}
