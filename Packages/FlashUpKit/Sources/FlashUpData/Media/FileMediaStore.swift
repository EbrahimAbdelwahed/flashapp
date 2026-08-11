import CryptoKit
import FlashUpDomain
import Foundation

/// Attachment blobs on disk, content-addressed (ADR-004 §6).
///
/// The filename is the SHA-256 of the bytes, so importing the same picture in two decks — or
/// re-importing the same `.apkg` — writes one file, not two. The `MediaAsset` records that
/// map ids to those files are kept alongside in a small index.
public actor FileMediaStore: MediaStore {
    private let directory: URL
    private let indexURL: URL
    private let maxBytes: Int
    private var index: [UUID: MediaAsset] = [:]
    private var loaded = false

    public init(
        directory: URL? = nil,
        maxBytes: Int = 32 * 1024 * 1024
    ) {
        let base = directory ?? FileMediaStore.defaultDirectory()
        self.directory = base
        indexURL = base.appendingPathComponent("index.json")
        self.maxBytes = maxBytes
    }

    private static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Media", isDirectory: true)
    }

    // MARK: - MediaStore

    public func store(_ data: Data, filename: String, kind: MediaAsset.Kind) async throws -> MediaAsset {
        guard data.count <= maxBytes else {
            throw MediaStoreError.tooLarge(bytes: data.count, limit: maxBytes)
        }
        try load()

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        // Same bytes, same file: hand back the asset we already have rather than writing a
        // duplicate under a new id.
        if let existing = index.values.first(where: { $0.sha256 == digest }) {
            return existing
        }

        let asset = MediaAsset(kind: kind, filename: filename, sha256: digest, byteCount: data.count)
        let target = directory.appendingPathComponent("\(digest).\(asset.fileExtension)")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: target.path) {
                // Card content never leaves the device unprotected; the same rule applies to
                // the pictures on those cards (spec §A2).
                try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        } catch {
            throw MediaStoreError.writeFailed
        }

        index[asset.id] = asset
        try? persistIndex()
        return asset
    }

    public func asset(for id: UUID) async -> MediaAsset? {
        try? load()
        return index[id]
    }

    public func data(for id: UUID) async -> Data? {
        guard let url = await url(for: id) else { return nil }
        return try? Data(contentsOf: url)
    }

    public func url(for id: UUID) async -> URL? {
        try? load()
        guard let asset = index[id] else { return nil }
        let candidate = directory.appendingPathComponent("\(asset.sha256).\(asset.fileExtension)")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Sweeps unreferenced blobs. A blob survives while **any** kept asset shares its digest,
    /// which is what makes deduplication safe: dropping one of two notes that share a picture
    /// must not delete the picture.
    public func removeAll(except keeping: Set<UUID>) async {
        try? load()

        let survivors = index.filter { keeping.contains($0.key) }
        let keptDigests = Set(survivors.values.map(\.sha256))

        for (id, asset) in index where !keeping.contains(id) {
            guard !keptDigests.contains(asset.sha256) else { continue }
            let url = directory.appendingPathComponent("\(asset.sha256).\(asset.fileExtension)")
            try? FileManager.default.removeItem(at: url)
        }

        index = survivors
        try? persistIndex()
    }

    public func removeAll() async {
        try? FileManager.default.removeItem(at: directory)
        index = [:]
        loaded = true
    }

    // MARK: - Index

    private func load() throws {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: indexURL) else { return }
        index = (try? JSONDecoder().decode([UUID: MediaAsset].self, from: data)) ?? [:]
    }

    private func persistIndex() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL, options: .atomic)
    }
}
