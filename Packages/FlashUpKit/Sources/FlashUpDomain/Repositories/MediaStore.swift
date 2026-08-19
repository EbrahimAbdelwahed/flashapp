import Foundation

/// Where attachment bytes live.
///
/// The protocol is pure so it can sit in `FlashUpDomain`; the filesystem implementation is in
/// `FlashUpData` (ADR-004 §4). Blobs are content-addressed, so storing the same bytes twice
/// returns the same asset instead of writing a second copy.
public protocol MediaStore: Sendable {
    /// Stores bytes and returns the asset describing them. Storing identical bytes again is
    /// cheap and returns an equivalent asset rather than duplicating the file.
    func store(_ data: Data, filename: String, kind: MediaAsset.Kind) async throws -> MediaAsset

    /// Returns `nil` only when the id is not present in the healthy manifest. Corrupt
    /// manifests, missing blobs and unreadable bytes are reported as typed failures.
    func asset(for id: UUID) async throws -> MediaAsset?
    func data(for id: UUID) async throws -> Data?
    /// A file URL, for players that need one instead of bytes in memory.
    func url(for id: UUID) async throws -> URL?

    /// Removes every blob **not** in `keeping`.
    ///
    /// Called only when the set of live references is fully known — never on import undo,
    /// where notes are soft-deleted and can come back: deleting their blobs there would be
    /// data loss, which `AGENTS.md` forbids outright.
    func removeAll(except keeping: Set<UUID>) async throws

    func removeAll() async throws
}

public enum MediaStoreError: Error, Equatable, Sendable {
    case unsupportedKind(filename: String)
    case tooLarge(bytes: Int, limit: Int)
    case writeFailed
    case readFailed
    case unavailable
    case indexCorrupt
    case invalidAsset
    case blobMissing
    case blobCorrupt
    case removeFailed
}
