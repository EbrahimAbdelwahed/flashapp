import FlashUpDomain
import SwiftUI

/// A deck with its pending work, tappable to study just that deck.
///
/// Tapping the row starts studying rather than opening a detail screen: the common path is
/// the direct one, and the deck's contents are one level deeper (`docs/ux-principles.md` §2).
struct DeckRow: View {
    let summary: DeckSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.normal) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.deck.name)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)

                    Text("deck.card_count \(summary.totalCards)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.tight)

                if summary.dueCount > 0 {
                    CountBadge(value: summary.dueCount, tint: Palette.dueText)
                }
                if summary.newCount > 0 {
                    CountBadge(value: summary.newCount, tint: Palette.newText)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Spacing.normal)
            .frame(minHeight: Spacing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableGlassButtonStyle(prominence: .regular))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(summary.deck.name))
        .accessibilityValue(Text("deck.accessibility_value \(summary.dueCount) \(summary.newCount)"))
        .accessibilityHint(Text("deck.accessibility_hint"))
        .accessibilityIdentifier("deck.row")
    }
}

private struct CountBadge: View {
    let value: Int
    let tint: Color

    var body: some View {
        Text(value, format: .number)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, Spacing.tight)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}
