import SwiftUI

/// Identifiers for the four-tab shell (spec §A11.1). Statistics pushes from Today,
/// so there is deliberately no fifth tab.
enum RootTab: String, CaseIterable, Identifiable {
    case today
    case library
    case groups
    case settings

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .today: "tab.today"
        case .library: "tab.library"
        case .groups: "tab.groups"
        case .settings: "tab.settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "calendar"
        case .library: "books.vertical"
        case .groups: "person.2"
        case .settings: "gearshape"
        }
    }

    /// Stable identifier for UI tests; not user-facing, so it is not localized.
    var accessibilityIdentifier: String { "tab.\(rawValue)" }
}

/// The adaptive four-tab shell used on both iPhone and iPad.
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: RootTab = .today

    var body: some View {
        tabs
            // Injected here as well as at the app root: card rendering and the import sheet
            // both live under the tabs, and this is the closest ancestor that owns the
            // store, so nothing depends on how the root scene happens to be composed.
            .environment(\.mediaStore, environment.mediaStore)
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            ForEach(RootTab.allCases) { tab in
                NavigationStack {
                    content(for: tab)
                }
                .tabItem {
                    Label(tab.titleKey, systemImage: tab.systemImage)
                        // On the tab bar button, not only on the tab's content. The
                        // identifier applied to the page below reaches whichever tab is
                        // already showing, which is of no use to anything trying to switch
                        // tabs — UI tests and the recording flows both need the control.
                        .accessibilityIdentifier(tab.accessibilityIdentifier)
                }
                .accessibilityIdentifier("\(tab.accessibilityIdentifier).page")
                .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func content(for tab: RootTab) -> some View {
        switch tab {
        case .today:
            TodayView(library: environment.library)
        case .library:
            LibraryView(library: environment.library)
        case .groups:
            GroupsView()
        case .settings:
            SettingsView(library: environment.library, reminders: environment.reminders)
        }
    }
}
