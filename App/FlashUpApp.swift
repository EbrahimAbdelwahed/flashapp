import SwiftUI

/// Application entry point.
///
/// Scene setup only. Deep-link and share-acceptance handling arrive with the group
/// beads (`fu-11-group-connect`); this scaffold owns the four-tab shell and nothing else.
@main
struct FlashUpApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
        }
    }
}
