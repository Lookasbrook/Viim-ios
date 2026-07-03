import SwiftUI

@main
struct ViimApp: App {
    @StateObject private var onboardingStore = OnboardingStore()

    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .environmentObject(onboardingStore)
                .environment(\.locale, Locale(identifier: "fr_BF"))
        }
    }
}

private struct AppLaunchView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore

    var body: some View {
        if onboardingStore.isCompleted {
            RootTabView()
        } else {
            OnboardingView()
        }
    }
}
