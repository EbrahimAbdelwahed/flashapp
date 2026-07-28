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
            .preferredColorScheme(environment.colorScheme)
            .task { await environment.loadAppearance() }
        }
    }
}
