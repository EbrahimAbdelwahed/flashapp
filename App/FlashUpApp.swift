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
    @State private var appearance: StudySettings.Appearance = .system

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
            .preferredColorScheme(colorScheme)
            .task { appearance = await environment.library.settings().appearance }
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
