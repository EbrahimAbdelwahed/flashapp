import FlashUpDomain
import SwiftUI

/// Application entry point.
///
/// Scene setup only. Deep-link and share-acceptance handling arrive with the group beads
/// (`fu-11-group-connect`).
@main
struct FlashUpApp: App {
    @State private var environment = AppEnvironment()
    @State private var tutorial = TutorialState()

    var body: some Scene {
        WindowGroup {
            Group {
                if tutorial.didFinishOnboarding {
                    RootTabView()
                } else {
                    OnboardingView { tutorial.didFinishOnboarding = true }
                }
            }
            .environment(environment)
            // Card rendering needs the blobs, and it is several views deep: passing the
            // store down by hand would thread it through every screen in between.
            .environment(\.mediaStore, environment.mediaStore)
            .preferredColorScheme(environment.colorScheme)
            .task { await environment.loadAppearance() }
        }
    }
}
