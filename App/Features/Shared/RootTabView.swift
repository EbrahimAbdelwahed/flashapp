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
        TabView(selection: $selection) {
            ForEach(RootTab.allCases) { tab in
                NavigationStack {
                    content(for: tab)
                }
                .tabItem {
                    Label(tab.titleKey, systemImage: tab.systemImage)
                }
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func content(for tab: RootTab) -> some View {
        switch tab {
        case .today:
            TodayView(library: environment.library)
        case .library, .groups, .settings:
            TabPlaceholderView(tab: tab)
        }
    }
}
