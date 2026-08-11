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

    @Environment(\.mediaStore) private var mediaStore

    var body: some View {
        VStack(spacing: Spacing.loose) {
            if let cloze = card.cloze {
                // The sentence keeps its in-place blank; only the attachments are appended,
                // because concatenated `Text` cannot hold an image.
                clozeSentence(cloze)
                ForEach(MediaReference.ids(in: cloze.source), id: \.self) { id in
                    MediaAttachmentView(id: id, store: mediaStore)
                }
            } else {
                frontBack
            }

            if isRevealed, let extra = card.extra, !extra.isEmpty {
                Divider()
                RichCardText(text: extra, font: .subheadline, color: .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Cloze

    private func clozeSentence(_ cloze: ClozeContext) -> some View {
        let source = MediaReference.stripping(cloze.source)
        let segments = ClozeParser.segments(source, group: cloze.group, revealed: isRevealed)

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
            RichCardText(text: card.front, font: .title2)

            if isRevealed {
                Divider()
                RichCardText(text: card.back, font: .title3, color: .secondary)
            }
        }
    }
}
