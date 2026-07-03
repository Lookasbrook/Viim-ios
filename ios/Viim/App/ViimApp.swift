import SwiftUI

@main
struct ViimApp: App {
    @StateObject private var onboardingStore = OnboardingStore()
    @StateObject private var locationService = LocationService()

    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .environmentObject(onboardingStore)
                .environmentObject(locationService)
                .environment(\.locale, Locale(identifier: "fr_BF"))
        }
    }
}

private struct AppLaunchView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var locationService: LocationService

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
                }
        } else {
            OnboardingView()
        }
    }
}
