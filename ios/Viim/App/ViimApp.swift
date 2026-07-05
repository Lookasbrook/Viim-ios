import SwiftUI

@main
struct ViimApp: App {
    private let persistenceController: PersistenceController

    @StateObject private var onboardingStore = OnboardingStore()
    @StateObject private var locationService = LocationService()
    @StateObject private var motionActivityService = MotionActivityService()
    @StateObject private var tripManager: TripManager

    init() {
        let persistenceController = PersistenceController.shared
        self.persistenceController = persistenceController
        _tripManager = StateObject(
            wrappedValue: TripManager(
                store: TripStore(context: persistenceController.container.viewContext)
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .environmentObject(onboardingStore)
                .environmentObject(locationService)
                .environmentObject(motionActivityService)
                .environmentObject(tripManager)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(\.locale, Locale(identifier: "fr_BF"))
        }
    }
}

private struct AppLaunchView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var motionActivityService: MotionActivityService
    @EnvironmentObject private var tripManager: TripManager
    @State private var stationaryFinalizationTask: Task<Void, Never>?

    var body: some View {
        if onboardingStore.isCompleted {
            RootTabView()
                .task(id: onboardingStore.profile?.vehicleType.rawValue) {
                    guard let profile = onboardingStore.profile else {
                        locationService.stopMonitoring(keepPassiveWakeups: false)
                        return
                    }
                    locationService.configure(vehicleType: profile.vehicleType)
                    locationService.prepareForForegroundUse()
                    motionActivityService.startAutoDetection(vehicleType: profile.vehicleType)
                }
                .onChange(of: motionActivityService.phase) { _ in
                    reconcileAutomaticTracking()
                }
                .onChange(of: locationService.activeTrip?.sampleCount) { _ in
                    persistActiveTripSnapshotIfNeeded()
                }
                .onChange(of: locationService.lastCompletedTrip?.id) { _ in
                    persistLastCompletedTripIfNeeded()
                }
        } else {
            OnboardingView()
        }
    }

    private func persistLastCompletedTripIfNeeded() {
        guard let profile = onboardingStore.profile,
              let completedTrip = locationService.lastCompletedTrip else {
            return
        }

        tripManager.persistCompletedTrip(
            completedTrip,
            samples: locationService.routeSamples,
            vehicleType: profile.vehicleType
        )
    }

    private func persistActiveTripSnapshotIfNeeded() {
        guard let profile = onboardingStore.profile,
              let activeTrip = locationService.activeTrip else {
            return
        }

        tripManager.persistActiveTripSnapshot(
            activeTrip,
            samples: locationService.routeSamples,
            vehicleType: profile.vehicleType
        )
    }

    private func reconcileAutomaticTracking() {
        ViimDiagnostics.log("motion.phase \(motionActivityService.phase)")

        if motionActivityService.phase.shouldTriggerLocationMonitoring {
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
