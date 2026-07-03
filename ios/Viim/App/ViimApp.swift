import SwiftUI

@main
struct ViimApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.locale, Locale(identifier: "fr_BF"))
        }
    }
}
