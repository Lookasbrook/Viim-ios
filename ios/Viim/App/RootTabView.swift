import SwiftUI

enum ViimTab: String, CaseIterable, Identifiable {
    case accueil
    case conduite
    case assistance
    case prevention

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .accueil: "tab.accueil"
        case .conduite: "tab.conduite"
        case .assistance: "tab.assistance"
        case .prevention: "tab.prevention"
        }
    }

    var symbolName: String {
        switch self {
        case .accueil: "house"
        case .conduite: "steeringwheel"
        case .assistance: "exclamationmark.triangle"
        case .prevention: "shield"
        }
    }

    var tint: Color {
        switch self {
        case .accueil: ViimColors.navy
        case .conduite: ViimColors.blue
        case .assistance: ViimColors.red
        case .prevention: ViimColors.green
        }
    }
}

struct RootTabView: View {
    @State private var selectedTab: ViimTab = .accueil

    var body: some View {
        TabView(selection: $selectedTab) {
            AccueilView()
                .tabItem { tabLabel(.accueil) }
                .tag(ViimTab.accueil)

            ConduiteView()
                .tabItem { tabLabel(.conduite) }
                .tag(ViimTab.conduite)

            AssistanceView()
                .tabItem { tabLabel(.assistance) }
                .tag(ViimTab.assistance)

            PreventionView()
                .tabItem { tabLabel(.prevention) }
                .tag(ViimTab.prevention)
        }
        .tint(selectedTab.tint)
    }

    @ViewBuilder
    private func tabLabel(_ tab: ViimTab) -> some View {
        Label(tab.titleKey, systemImage: tab.symbolName)
    }
}
