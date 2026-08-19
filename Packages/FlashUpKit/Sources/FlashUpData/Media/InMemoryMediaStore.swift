import CryptoKit
import FlashUpDomain
import Foundation

/// The `MediaStore` for previews and tests, mirroring `InMemoryLibrary`'s role.
///
/// Content-addressed like the real one, so deduplication behaviour is exercised by tests
/// rather than only existing on disk.
public actor InMemoryMediaStore: MediaStore {
    private var assets: [UUID: MediaAsset] = [:]
    private var blobs: [String: Data] = [:]

    public init() {}

    public func store(_ data: Data, filename: String, kind: MediaAsset.Kind) async throws -> MediaAsset {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let existing = assets.values.first(where: { $0.sha256 == digest }) {
            return existing
        }

        let asset = MediaAsset(kind: kind, filename: filename, sha256: digest, byteCount: data.count)
        assets[asset.id] = asset
        blobs[digest] = data
        return asset
    }

    public func asset(for id: UUID) async throws -> MediaAsset? { assets[id] }

    public func data(for id: UUID) async throws -> Data? {
        guard let asset = assets[id] else { return nil }
        return blobs[asset.sha256]
    }

    /// Always `nil`: nothing here is on disk. Callers that need a URL — the audio player —
    /// must fall back to `data(for:)`.
    public func url(for id: UUID) async throws -> URL? { nil }

    public func removeAll(except keeping: Set<UUID>) async throws {
        let survivors = assets.filter { keeping.contains($0.key) }
        let keptDigests = Set(survivors.values.map(\.sha256))
        blobs = blobs.filter { keptDigests.contains($0.key) }
        assets = survivors
    }

    public func removeAll() async throws {
        assets = [:]
        blobs = [:]
    }
}
