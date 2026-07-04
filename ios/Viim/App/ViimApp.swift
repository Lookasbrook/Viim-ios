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

    var body: some View {
        if onboardingStore.isCompleted {
            RootTabView()
                .task(id: onboardingStore.profile?.vehicleType.rawValue) {
                    guard let profile = onboardingStore.profile else {
                        locationService.stopMonitoring()
                        return
                    }
                    locationService.configure(vehicleType: profile.vehicleType)
                    locationService.prepareForForegroundUse()
                    motionActivityService.startAutoDetection(vehicleType: profile.vehicleType)
                }
                .onChange(of: motionActivityService.phase) { _ in
                    reconcileAutomaticTracking()
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

    private func reconcileAutomaticTracking() {
        if motionActivityService.phase.shouldTriggerLocationMonitoring {
            if !locationService.isMonitoring {
                locationService.startMonitoring()
            }
            return
        }

        guard motionActivityService.phase == .stationary,
              locationService.isMonitoring,
              locationService.activeTrip == nil,
              locationService.tripPhase == .idle else {
            return
        }

        locationService.stopMonitoring()
    }
}
