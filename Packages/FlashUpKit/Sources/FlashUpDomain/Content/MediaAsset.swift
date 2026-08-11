import Foundation

/// One attachment: an image or a sound belonging to a note (ADR-004 §6).
///
/// The bytes live outside this type, addressed by `sha256`, so two decks that share the same
/// picture share one blob on disk.
public struct MediaAsset: Identifiable, Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case image
        case audio
    }

    public let id: UUID
    public let kind: Kind
    /// The original name, kept for diagnostics and as the accessibility label of an image
    /// that has nothing better to describe it.
    public let filename: String
    /// Content address. Identical bytes deduplicate to one file, whichever deck they arrive in.
    public let sha256: String
    public let byteCount: Int

    public init(id: UUID = UUID(), kind: Kind, filename: String, sha256: String, byteCount: Int) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.sha256 = sha256
        self.byteCount = byteCount
    }

    /// Lower-cased extension of the original filename, used to name the stored blob.
    public var fileExtension: String {
        let candidate = (filename as NSString).pathExtension.lowercased()
        return candidate.isEmpty ? kind.defaultExtension : candidate
    }
}

extension MediaAsset.Kind {
    /// What Flash Up will carry. Deliberately conservative: every one of these renders or
    /// plays natively on iOS 17, so an accepted attachment always works (ADR-004 §6).
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]
    public static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "ogg"]

    /// `nil` for anything we cannot render or play — video included, which is why an
    /// `.apkg` note carrying one is refused with a reason rather than imported broken.
    public init?(filename: String) {
        let ext = (filename as NSString).pathExtension.lowercased()
        if Self.imageExtensions.contains(ext) {
            self = .image
        } else if Self.audioExtensions.contains(ext) {
            self = .audio
        } else {
            return nil
        }
    }

    var defaultExtension: String {
        switch self {
        case .image: "png"
        case .audio: "mp3"
        }
    }
}
