import SwiftUI

/// Empty state shown by every tab until its feature bead lands.
///
/// Uses text styles only (Dynamic Type, spec §0.2) and carries no animation, so there is
/// nothing to reduce under `accessibilityReduceMotion` yet.
struct TabPlaceholderView: View {
    let tab: RootTab

    var body: some View {
        ContentUnavailableView {
            Label(tab.titleKey, systemImage: tab.systemImage)
        } description: {
            Text("shell.placeholder.description")
        }
        .screenCanvas()
        .navigationTitle(tab.titleKey)
        .accessibilityIdentifier("\(tab.accessibilityIdentifier).placeholder")
    }
}

#Preview {
    NavigationStack {
        TabPlaceholderView(tab: .today)
    }
}
