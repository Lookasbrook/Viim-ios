import Combine
import SwiftUI

@main
struct ViimApp: App {
    private let persistenceController: PersistenceController

    @StateObject private var onboardingStore: OnboardingStore
    @StateObject private var locationService: LocationService
    @StateObject private var motionActivityService = MotionActivityService()
    @StateObject private var networkStatusService = NetworkStatusService()
    @StateObject private var tripManager: TripManager
    @StateObject private var tripRecorder: TripRecorder
    @StateObject private var tripDetectionCoordinator: TripDetectionCoordinator

    init() {
        ViimDiagnostics.logBuildIdentity()
        let persistenceController = PersistenceController.shared
        let context = persistenceController.container.viewContext
        let activeTripJournal = ActiveTripJournal(context: context)
        let tripManager = TripManager(
            store: TripStore(context: context)
        )
        let onboardingStore = OnboardingStore()
        let tripRecorder = TripRecorder(
            journal: activeTripJournal,
            tripManager: tripManager
        )

        // Recuperer les brouillons avant d'instancier CLLocationManager. La
        // pose de son delegate peut livrer immediatement un reveil passif et
        // creer un nouveau candidat pendant le lancement.
        if let profile = onboardingStore.profile {
            tripRecorder.configure(profile: profile)
        }
        tripRecorder.recoverActiveTrips()

        let locationService = LocationService(activeTripJournal: activeTripJournal)
        let motionActivityService = MotionActivityService()
        let tripDetectionCoordinator = TripDetectionCoordinator(
            locationService: locationService,
            motionActivityService: motionActivityService,
            tripRecorder: tripRecorder
        )

        // Cablage headless : quand iOS relance l'app en arriere-plan (reveil
        // localisation), aucune vue n'existe encore. La recuperation des
        // trajets journalises et l'observation des trajets termines doivent
        // donc etre branchees ici, pas dans une vue.
        if let profile = onboardingStore.profile {
            tripManager.recalculateFuelEstimates(profile: profile)
            locationService.configure(vehicleType: profile.vehicleType)
        }
        tripRecorder.observe(locationService: locationService)
        locationService.restoreAutomaticTrackingSession()

        self.persistenceController = persistenceController
        _onboardingStore = StateObject(wrappedValue: onboardingStore)
        _locationService = StateObject(wrappedValue: locationService)
        _motionActivityService = StateObject(wrappedValue: motionActivityService)
        _tripManager = StateObject(
            wrappedValue: tripManager
        )
        _tripRecorder = StateObject(wrappedValue: tripRecorder)
        _tripDetectionCoordinator = StateObject(wrappedValue: tripDetectionCoordinator)
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .environmentObject(onboardingStore)
                .environmentObject(locationService)
                .environmentObject(motionActivityService)
                .environmentObject(networkStatusService)
                .environmentObject(tripManager)
                .environmentObject(tripRecorder)
                .environmentObject(tripDetectionCoordinator)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                // La charte Viim est une palette claire fixe (cartes blanches,
                // fonds clairs). Sans ce verrou, iOS applique des barres et
                // champs sombres par-dessus, source des textes illisibles.
                .preferredColorScheme(.light)
        }
    }
}

private struct AppLaunchView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var motionActivityService: MotionActivityService
    @EnvironmentObject private var tripManager: TripManager
    @EnvironmentObject private var tripRecorder: TripRecorder
    @EnvironmentObject private var tripDetectionCoordinator: TripDetectionCoordinator

    var body: some View {
        if onboardingStore.isCompleted {
            RootTabView()
                .task(id: onboardingStore.profile?.vehicleType.rawValue) {
                    guard let profile = onboardingStore.profile else {
                        tripDetectionCoordinator.stop()
                        return
                    }
                    tripDetectionCoordinator.configure(profile: profile)
                }
        } else {
            OnboardingView()
        }
    }

}

@MainActor
final class TripDetectionCoordinator: ObservableObject {
    private let locationService: LocationService
    private let motionActivityService: MotionActivityService
    private let tripRecorder: TripRecorder
    private var stationaryFinalizationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        locationService: LocationService,
        motionActivityService: MotionActivityService,
        tripRecorder: TripRecorder
    ) {
        self.locationService = locationService
        self.motionActivityService = motionActivityService
        self.tripRecorder = tripRecorder

        motionActivityService.$phase
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.reconcileAutomaticTracking()
                }
            }
            .store(in: &cancellables)
    }

    func configure(profile: UserProfile) {
        tripRecorder.configure(profile: profile)
        tripRecorder.observe(locationService: locationService)
        locationService.configure(vehicleType: profile.vehicleType)
        locationService.prepareForForegroundUse()
        motionActivityService.startAutoDetection(vehicleType: profile.vehicleType)
        reconcileAutomaticTracking()
    }

    func stop() {
        stationaryFinalizationTask?.cancel()
        stationaryFinalizationTask = nil
        motionActivityService.stopAutoDetection()
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
