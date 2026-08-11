import AVFoundation
import FlashUpDomain
import SwiftUI

/// Card text that can carry attachments.
///
/// `CardFaceView` builds `Text` values and concatenates them with `+`, which cannot hold an
/// image. So text that references media is split into blocks: the words stay `Text` (and
/// cloze still fills its blank in place, unchanged), and each attachment becomes its own
/// view underneath.
struct RichCardText: View {
    let text: String
    let font: Font
    var color: Color = .primary

    @Environment(\.mediaStore) private var mediaStore

    var body: some View {
        VStack(spacing: Spacing.normal) {
            let stripped = MediaReference.stripping(text)
            if !stripped.isEmpty {
                Text(stripped)
                    .font(font)
                    .foregroundStyle(color)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            ForEach(MediaReference.ids(in: text), id: \.self) { id in
                MediaAttachmentView(id: id, store: mediaStore)
            }
        }
    }
}

/// One attachment. Loads on appear rather than up front, so a deck of image cards does not
/// pull every picture into memory to show one card.
struct MediaAttachmentView: View {
    let id: UUID
    let store: (any MediaStore)?

    @State private var asset: MediaAsset?
    @State private var data: Data?
    @State private var didLoad = false

    var body: some View {
        Group {
            switch asset?.kind {
            case .image:
                image
            case .audio:
                AudioAttachmentButton(label: asset?.filename ?? "", data: data)
            case nil:
                // A reference whose blob is gone — a restored backup, which carries
                // references but not bytes (ADR-004 §7). The card still works.
                if didLoad { placeholder }
            }
        }
        .task {
            guard !didLoad else { return }
            // Marked loaded even when there is no store: an attachment that cannot be
            // resolved must show the placeholder, not silently disappear.
            didLoad = true
            guard let store else { return }
            asset = await store.asset(for: id)
            data = await store.data(for: id)
        }
    }

    @ViewBuilder
    private var image: some View {
        if let data, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                // Both bounds are needed: without a width proposal `scaledToFit` falls back
                // to the image's intrinsic size, so a small picture renders too small to see.
                .frame(maxWidth: .infinity, maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.controlCornerRadius))
                // Nothing here can describe the picture, so the original filename is the
                // most honest label available.
                .accessibilityLabel(Text(asset?.filename ?? ""))
        } else if didLoad {
            placeholder
        }
    }

    private var placeholder: some View {
        Label("media.unavailable", systemImage: "photo")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(Spacing.tight)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: Spacing.controlCornerRadius))
    }
}

/// Plays a sound attachment. Never autoplays: a card that starts talking on its own is a
/// surprise, and on shared devices an unwelcome one.
struct AudioAttachmentButton: View {
    let label: String
    let data: Data?

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        Button {
            play()
        } label: {
            Label(
                isPlaying ? "media.playing" : "media.play",
                systemImage: isPlaying ? "speaker.wave.2.fill" : "play.circle.fill"
            )
                .font(.body)
                .frame(minHeight: Spacing.minimumTapTarget)
        }
        .buttonStyle(.bordered)
        .disabled(data == nil)
        .accessibilityLabel(Text("media.play"))
        .accessibilityValue(Text(label))
        .accessibilityIdentifier("card.audio")
    }

    private func play() {
        guard let data else { return }
        do {
            let player = try AVAudioPlayer(data: data)
            self.player = player
            player.play()
            isPlaying = true
            // No delegate juggling for a progress dot: the label reverts on the next tap or
            // when the card changes, which is enough feedback for a one-shot sound.
            DispatchQueue.main.asyncAfter(deadline: .now() + player.duration) {
                isPlaying = false
            }
        } catch {
            isPlaying = false
        }
    }
}

/// Note text reduced to words, for lists and previews.
///
/// A row is a one-line summary, not a card face: it cannot show a picture, and showing the
/// raw `![](flashup-media://…)` markup instead would be worse than showing nothing.
extension String {
    var asNoteSummary: String {
        MediaReference.stripping(self)
    }
}

// MARK: - Environment

private struct MediaStoreKey: EnvironmentKey {
    static let defaultValue: (any MediaStore)? = nil
}

extension EnvironmentValues {
    var mediaStore: (any MediaStore)? {
        get { self[MediaStoreKey.self] }
        set { self[MediaStoreKey.self] = newValue }
    }
}
