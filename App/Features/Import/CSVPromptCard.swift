import SwiftUI

/// A ready-made instruction the user pastes into ChatGPT (or any assistant) so the file it
/// produces imports without a single edit.
///
/// This is the shortest path from "my notes are in a PDF" to "my cards are in the app", and
/// it is the reason the import flow exists at all — so it sits in front of the file picker,
/// not buried in Help.
struct CSVPromptCard: View {
    @State private var didCopy = false
    /// Collapsed by default: the prompt is long, and nobody has to read it to use it —
    /// copying is enough. Expanding is for the curious and for selecting a piece by hand.
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            DisclosureGroup(isExpanded: $isExpanded.animation(Motion.snappy)) {
                Text(CSVPromptCard.promptText)
                    .font(.caption2.monospaced())
                    .padding(Spacing.tight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.terracotta.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
                    .padding(.top, Spacing.tight)
                    .accessibilityIdentifier("import.prompt.text")
            } label: {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Label("import.prompt.title", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))

                    Text("import.prompt.explanation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("import.prompt.disclosure")

            Button {
                UIPasteboard.general.string = CSVPromptCard.promptText
                withAnimation(Motion.snappy) { didCopy = true }
            } label: {
                Label(
                    didCopy ? "import.prompt.copied" : "import.prompt.copy",
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
            }
            .accessibilityIdentifier("import.prompt.copy")
        }
        .padding(.vertical, Spacing.tight)
    }

    /// Localized so the user pastes a prompt in their own language, which is also the
    /// language the assistant will answer and write the cards in.
    static var promptText: String {
        String(localized: "import.prompt.body")
    }
}
