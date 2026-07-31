import FlashUpData
import SwiftUI

/// Persisted flags for one-off guidance (spec §A11.4).
@Observable
@MainActor
final class TutorialState {
    private enum Key {
        static let onboarding = "didFinishOnboarding"
    }

    private let defaults: UserDefaults

    var didFinishOnboarding: Bool {
        didSet { defaults.set(didFinishOnboarding, forKey: Key.onboarding) }
    }

    init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        // A recording opens on the product, never on a tutorial: spec §1.7 rules out a
        // splash screen or a static introductory frame as the first thing a viewer sees.
        // The pipeline reinstalls the app before every take, so onboarding would otherwise
        // be waiting at the top of every single clip.
        self.didFinishOnboarding = environment[DemoMode.modeKey] == "1"
            || defaults.bool(forKey: Key.onboarding)
    }
}

/// Three screens, then the app is usable. Mandatory once, replayable from Help.
///
/// It teaches the only three things the app needs the user to know: where cards come from,
/// how a review works, and what the four grades mean.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let systemImage: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(id: 0, systemImage: "square.and.arrow.down",
             title: "onboarding.import.title", body: "onboarding.import.body"),
        Page(id: 1, systemImage: "rectangle.on.rectangle",
             title: "onboarding.review.title", body: "onboarding.review.body"),
        Page(id: 2, systemImage: "hand.thumbsup",
             title: "onboarding.grades.title", body: "onboarding.grades.body")
    ]

    var body: some View {
        VStack(spacing: Spacing.loose) {
            TabView(selection: $page) {
                ForEach(pages) { item in
                    VStack(spacing: Spacing.loose) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 64))
                            .foregroundStyle(.blue)
                        Text(item.title)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(item.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Spacing.loose)
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page)

            PrimaryActionButton(
                title: page == pages.count - 1 ? "onboarding.start" : "onboarding.next",
                subtitle: nil,
                systemImage: page == pages.count - 1 ? "play.fill" : "arrow.right"
            ) {
                if page == pages.count - 1 {
                    onFinish()
                } else {
                    page += 1
                }
            }
            .padding(.horizontal, Spacing.loose)
            .accessibilityIdentifier("onboarding.primary")

            Button("onboarding.skip") { onFinish() }
                .font(.footnote)
                .accessibilityIdentifier("onboarding.skip")
        }
        .padding(.bottom, Spacing.loose)
    }
}
