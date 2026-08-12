import Foundation
import Testing
@testable import FlashUpDomain

@Suite("Media references in note text")
struct MediaReferenceTests {
    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID()

    private func asset(_ kind: MediaAsset.Kind, _ filename: String) -> MediaAsset {
        MediaAsset(id: id, kind: kind, filename: filename, sha256: "abc", byteCount: 1)
    }

    @Test("An image renders as Markdown image syntax")
    func imageMarkup() {
        let markup = MediaReference.markup(for: asset(.image, "a.png"))
        #expect(markup == "![](flashup-media://\(id.uuidString))")
    }

    @Test("Audio renders as a Markdown link")
    func audioMarkup() {
        let markup = MediaReference.markup(for: asset(.audio, "a.mp3"))
        #expect(markup == "[audio](flashup-media://\(id.uuidString))")
    }

    @Test("A reference round-trips through the scanner", arguments: [MediaAsset.Kind.image, .audio])
    func roundTrip(_ kind: MediaAsset.Kind) {
        let text = "Guarda qui \(MediaReference.markup(for: asset(kind, "a.png")))"
        #expect(MediaReference.ids(in: text) == [id])
        #expect(MediaReference.stripping(text) == "Guarda qui")
    }

    @Test("Several references are found in order")
    func multiple() {
        let first = UUID()
        let second = UUID()
        let text = "![](flashup-media://\(first.uuidString)) e [audio](flashup-media://\(second.uuidString))"
        #expect(MediaReference.ids(in: text) == [first, second])
        #expect(MediaReference.stripping(text) == "e")
    }

    @Test("Text with no reference is left exactly alone")
    func noReference() {
        let text = "Una nota normale, con [un link](https://example.com) dentro"
        #expect(MediaReference.ids(in: text).isEmpty)
        #expect(MediaReference.stripping(text) == text)
    }

    @Test("A malformed reference is ignored rather than half-parsed")
    func malformed() {
        #expect(MediaReference.ids(in: "![](flashup-media://non-un-uuid)").isEmpty)
        #expect(MediaReference.ids(in: "![](flashup-media://").isEmpty)
    }

    /// The whole reason references are text: two notes with the same picture must still
    /// deduplicate, and export/backup must survive untouched (ADR-004 §6).
    @Test("Two notes carrying the same attachment fingerprint identically")
    func fingerprintIsStable() {
        let text = "Domanda \(MediaReference.markup(for: asset(.image, "a.png")))"
        let first = ContentFingerprint.hash(type: .basic, front: text, back: "Risposta")
        let second = ContentFingerprint.hash(type: .basic, front: text, back: "Risposta")
        #expect(first == second)
    }

    @Test("Cloze deletions survive alongside a reference")
    func clozeAndMedia() {
        let text = "La {{c1::mitosi}} \(MediaReference.markup(for: asset(.image, "a.png")))"
        #expect(ClozeParser.hasValidDeletion(MediaReference.stripping(text)))
        #expect(MediaReference.ids(in: text) == [id])
    }
}

@Suite("Media asset kinds")
struct MediaAssetTests {
    @Test("Supported image and audio extensions are recognised", arguments: [
        ("foto.png", MediaAsset.Kind.image), ("foto.JPG", .image), ("clip.mp3", .audio), ("clip.WAV", .audio)
    ])
    func recognised(_ filename: String, _ expected: MediaAsset.Kind) {
        #expect(MediaAsset.Kind(filename: filename) == expected)
    }

    /// Video is deliberately unsupported: an `.apkg` note carrying one is refused with a
    /// reason rather than imported broken (ADR-004 §6).
    @Test("Anything else, video included, is not a supported kind", arguments: [
        "clip.mp4", "clip.mov", "documento.pdf", "senza_estensione"
    ])
    func rejected(_ filename: String) {
        #expect(MediaAsset.Kind(filename: filename) == nil)
    }

    @Test("The stored file keeps the original extension")
    func fileExtension() {
        let asset = MediaAsset(kind: .image, filename: "Foto.JPEG", sha256: "abc", byteCount: 1)
        #expect(asset.fileExtension == "jpeg")
    }
}
