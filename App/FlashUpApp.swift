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
    @State private var installErrorMessage: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if case .failed = environment.storageState {
                    StorageRecoveryView()
                } else if tutorial.didFinishOnboarding {
                    RootTabView()
                } else {
                    OnboardingView {
                        Task {
                            do {
                                try await environment.installDemoDeck()
                                tutorial.didFinishOnboarding = true
                            } catch {
                                installErrorMessage = String(localized: "storage.error.unavailable")
                            }
                        }
                    }
                }
            }
            .environment(environment)
            // Card rendering needs the blobs, and it is several views deep: passing the
            // store down by hand would thread it through every screen in between.
            .environment(\.mediaStore, environment.mediaStore)
            .preferredColorScheme(environment.colorScheme)
            .task { await environment.loadAppearance() }
            .alert(
                "storage.error.title",
                isPresented: Binding(
                    get: { installErrorMessage != nil },
                    set: { if !$0 { installErrorMessage = nil } }
                )
            ) {
                Button("common.ok") { installErrorMessage = nil }
            } message: {
                Text(installErrorMessage ?? "storage.error.unavailable")
            }
        }
    }
}

/// The recovery actions live at the root because Settings is not reachable when the store
/// cannot open. Raw exports are offered only when the persistence layer preserved an artifact.
private struct StorageRecoveryView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text("storage.recovery.title")
                .font(.headline)
            Text("storage.recovery.message")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let directoryURL = environment.storageRecovery?.artifact?.directoryURL {
                ShareLink(item: directoryURL) {
                    Label("storage.recovery.export", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("storage.recovery.export")
            }

            Link(destination: supportURL) {
                Label("storage.recovery.support", systemImage: "envelope")
            }
            .accessibilityIdentifier("storage.recovery.support")

            Button("storage.recovery.retry") {
#if DEBUG
                if environment.isRetryProbeEnabled {
                    Task { @MainActor in
                        async let first = environment.retryStorage()
                        async let second = environment.retryStorage()
                        _ = await (first, second)
                    }
                } else {
                    Task { await environment.retryStorage() }
                }
#else
                Task { await environment.retryStorage() }
#endif
            }
            .buttonStyle(.borderedProminent)
            .disabled(environment.isStorageRetrying)
            .accessibilityIdentifier("storage.recovery.retry")

#if DEBUG
            if environment.isRetryProbeEnabled {
                Text("\(environment.storageRetryRepositoryOpenCount)")
                    .accessibilityIdentifier("storage.recovery.repository-open-count")
            }
            if environment.isRetryProbeEnabled && environment.isStorageRetrying {
                Text("\(environment.storageRetryOpenCount)")
                    .accessibilityIdentifier("storage.recovery.open-count")
            }
#endif
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storage.recovery")
    }

    private var supportURL: URL {
        URL(string: "mailto:support@flashup.app?subject=FlashApp%20storage%20recovery")
            ?? URL(filePath: "/")
    }
}
