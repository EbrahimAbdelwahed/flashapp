import SwiftUI

/// Contextual guidance, replayable (spec §A11.4).
struct HelpView: View {
    private let topics: [(LocalizedStringKey, LocalizedStringKey)] = [
        ("help.import.q", "help.import.a"),
        ("help.cloze.q", "help.cloze.a"),
        ("help.grades.q", "help.grades.a"),
        ("help.sync.q", "help.sync.a"),
        ("help.groups.q", "help.groups.a")
    ]

    var body: some View {
        List {
            Section("help.faq") {
                ForEach(Array(topics.enumerated()), id: \.offset) { _, topic in
                    DisclosureGroup {
                        Text(topic.1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(topic.0).font(.body.weight(.medium))
                    }
                }
            }

            Section("help.support") {
                Link(destination: URL(string: "mailto:support@flashup.app?subject=Flash%20Up") ?? URL(filePath: "/")) {
                    Label("help.contact", systemImage: "envelope")
                }
            }
        }
        .navigationTitle("settings.help")
    }
}

/// What leaves the device, stated plainly (brief §Privacy).
struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text("privacy.summary")
            }
            Section("privacy.what_we_store") {
                Label("privacy.point.local", systemImage: "iphone")
                Label("privacy.point.icloud", systemImage: "icloud")
                Label("privacy.point.no_tracking", systemImage: "eye.slash")
                Label("privacy.point.no_account", systemImage: "person.crop.circle.badge.xmark")
            }
        }
        .navigationTitle("settings.privacy")
    }
}
