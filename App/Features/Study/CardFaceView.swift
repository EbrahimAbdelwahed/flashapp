import FlashUpDomain
import SwiftUI

/// The card itself, in whichever state the session is in.
///
/// A cloze card keeps **one** sentence on screen: the blank is filled in place when the
/// card is flipped. Repeating the whole sentence underneath would make the learner read it
/// twice and hide the one word that matters.
struct CardFaceView: View {
    let card: Card
    let isRevealed: Bool

    var body: some View {
        VStack(spacing: Spacing.loose) {
            if let cloze = card.cloze {
                clozeSentence(cloze)
            } else {
                frontBack
            }

            if isRevealed, let extra = card.extra, !extra.isEmpty {
                Divider()
                Text(extra)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Cloze

    private func clozeSentence(_ cloze: ClozeContext) -> some View {
        let segments = ClozeParser.segments(cloze.source, group: cloze.group, revealed: isRevealed)

        return segments
            .enumerated()
            .reduce(Text(verbatim: "")) { partial, item in
                partial + styled(item.element)
            }
            .font(.title2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(segments.map(\.text).joined()))
    }

    /// The answered word is the only thing that changes, so it is the only thing emphasised:
    /// dim and underlined while hidden, solid and coloured once filled in.
    private func styled(_ segment: ClozeSegment) -> Text {
        guard segment.isAnswer else {
            return Text(segment.text)
        }
        return Text(segment.text)
            .foregroundColor(isRevealed ? .accentColor : .secondary)
            .fontWeight(.semibold)
    }

    // MARK: - Basic and reversed

    private var frontBack: some View {
        VStack(spacing: Spacing.loose) {
            Text(card.front)
                .font(.title2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if isRevealed {
                Divider()
                Text(card.back)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
