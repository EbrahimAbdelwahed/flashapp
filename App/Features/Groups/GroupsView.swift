import SwiftUI

/// Collaborative groups need CloudKit sharing, which is proven by `fu-02-sharing-spike` and
/// built by `fu-11` through `fu-13`.
///
/// Until an Apple Developer account exists, this screen states the situation honestly
/// instead of showing controls that cannot work. Wayfinding rule: every screen answers
/// "what is this and what can I do here?" — including this one.
struct GroupsView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Label("groups.unavailable.title", systemImage: "person.2.slash")
                        .font(.headline)
                    Text("groups.unavailable.body")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Spacing.tight)
                .accessibilityElement(children: .combine)
            }

            Section("groups.what_you_get") {
                Label("groups.feature.share", systemImage: "square.and.arrow.up")
                Label("groups.feature.private_progress", systemImage: "lock")
                Label("groups.feature.history", systemImage: "clock.arrow.circlepath")
            }
        }
        .navigationTitle("tab.groups")
    }
}
