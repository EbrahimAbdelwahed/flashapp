import CryptoKit
import FlashUpDomain
import Foundation

/// Attachment blobs on disk, content-addressed (ADR-004 §6).
///
/// The index is loaded and validated before the actor escapes. A missing or corrupt index,
/// missing blob, and unreadable/mutated blob are all typed failures; none becomes a false nil.
public actor FileMediaStore: MediaStore { // swiftlint:disable:this type_body_length
    private let directory: URL
    private let indexURL: URL
    private let maxBytes: Int
    private var index: [UUID: MediaAsset]
    private var loadError: MediaStoreError?
    private var closed = false

    /// Explicit directories are used by tests and import sandboxes. The constructor performs
    /// the same health check as the production constructor so an invalid store cannot escape.
    public init(directory: URL, maxBytes: Int = 32 * 1024 * 1024) throws {
        let base = directory.standardizedFileURL
        self.directory = base
        indexURL = base.appendingPathComponent("index.json")
        self.maxBytes = maxBytes
        index = try Self.readIndex(from: base, indexURL: indexURL)
        loadError = nil
    }

    /// A missing Application Support directory must surface as a boot error, never become a
    /// temporary store that can make a later launch appear to lose user attachments.
    public init() throws {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { throw MediaStoreError.unavailable }
        let base = support.appendingPathComponent("Media", isDirectory: true).standardizedFileURL
        directory = base
        indexURL = base.appendingPathComponent("index.json")
        maxBytes = 32 * 1024 * 1024
        index = try Self.readIndex(from: base, indexURL: indexURL)
        loadError = nil
    }

    // MARK: - MediaStore

    public func store(_ data: Data, filename: String, kind: MediaAsset.Kind) async throws -> MediaAsset {
        try ensureOpen()
        guard data.count <= maxBytes else {
            throw MediaStoreError.tooLarge(bytes: data.count, limit: maxBytes)
        }

        let digest = Self.digest(for: data)
        if let existing = index.values.first(where: { $0.sha256 == digest }) {
            return existing
        }

        let asset = MediaAsset(kind: kind, filename: filename, sha256: digest, byteCount: data.count)
        try validate(asset)
        let target = try containedURL(for: asset)
        let oldIndex = index
        let blobExisted = FileManager.default.fileExists(atPath: target.path)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !blobExisted {
                try data.write(
                    to: target,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            }
        } catch {
            loadError = .writeFailed
            throw MediaStoreError.writeFailed
        }

        var updatedIndex = index
        updatedIndex[asset.id] = asset
        do {
            try persistIndex(updatedIndex)
            index = updatedIndex
        } catch {
            index = oldIndex
            if !blobExisted { try? FileManager.default.removeItem(at: target) }
            loadError = .writeFailed
            throw MediaStoreError.writeFailed
        }
        return asset
    }

    public func asset(for id: UUID) async throws -> MediaAsset? {
        try ensureOpen()
        guard let asset = index[id] else { return nil }
        _ = try verifyStoredAsset(asset)
        return asset
    }

    public func data(for id: UUID) async throws -> Data? {
        try ensureOpen()
        guard let asset = index[id] else { return nil }
        let url = try verifyStoredAsset(asset)
        do {
            let data = try Data(contentsOf: url)
            guard data.count == asset.byteCount, Self.digest(for: data) == asset.sha256 else {
                loadError = .blobCorrupt
                throw MediaStoreError.blobCorrupt
            }
            return data
        } catch let error as MediaStoreError {
            throw error
        } catch {
            loadError = .readFailed
            throw MediaStoreError.readFailed
        }
    }

    public func url(for id: UUID) async throws -> URL? {
        try ensureOpen()
        guard let asset = index[id] else { return nil }
        return try verifyStoredAsset(asset)
    }

    /// Commits the survivor manifest before sweeping blobs. If either manifest or blob cleanup
    /// fails, the new manifest remains authoritative but the operation reports failure so the
    /// caller cannot present erase/sweep as complete while bytes remain.
    public func removeAll(except keeping: Set<UUID>) async throws {
        try ensureOpen()
        let survivors = index.filter { keeping.contains($0.key) }
        do {
            try persistIndex(survivors)
        } catch {
            loadError = .writeFailed
            throw MediaStoreError.writeFailed
        }

        let keptDigests = Set(survivors.values.map(\.sha256))
        var failures = false
        for (id, asset) in index where !keeping.contains(id) {
            guard !keptDigests.contains(asset.sha256) else { continue }
            do {
                try FileManager.default.removeItem(at: try containedURL(for: asset))
            } catch {
                failures = true
            }
        }
        index = survivors
        if failures {
            loadError = .removeFailed
            throw MediaStoreError.removeFailed
        }
    }

    public func removeAll() async throws {
        try ensureOpen()
        guard FileManager.default.fileExists(atPath: directory.path) else {
            index = [:]
            loadError = nil
            return
        }
        do {
            try FileManager.default.removeItem(at: directory)
            index = [:]
            loadError = nil
        } catch {
            loadError = .removeFailed
            throw MediaStoreError.removeFailed
        }
    }

    /// Stable diagnostic seam for the composition root and recovery UI.
    public func storageError() async -> MediaStoreError? { loadError }

    /// Seals a profile's media sidecar before account routing opens another profile.  The
    /// directory remains on disk for the profile that owns it; stale references only receive a
    /// typed unavailable error and cannot read the previous account's bytes.
    public func close() {
        closed = true
        index.removeAll()
    }

    // MARK: - Health and index

    private func ensureOpen() throws {
        guard !closed else { throw MediaStoreError.unavailable }
    }

    private static func readIndex(from directory: URL, indexURL: URL) throws -> [UUID: MediaAsset] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: indexURL)
            let decoded = try JSONDecoder().decode([UUID: MediaAsset].self, from: data)
            for (manifestID, asset) in decoded {
                guard manifestID == asset.id else {
                    throw MediaStoreError.indexCorrupt
                }
                try validate(asset, directory: directory)
                let blob = try containedURL(for: asset, directory: directory)
                guard FileManager.default.fileExists(atPath: blob.path) else {
                    throw MediaStoreError.blobMissing
                }
                let attributes = try FileManager.default.attributesOfItem(atPath: blob.path)
                guard let size = attributes[.size] as? NSNumber,
                      size.intValue == asset.byteCount else {
                    throw MediaStoreError.blobCorrupt
                }
                let blobData = try Data(contentsOf: blob)
                guard Self.digest(for: blobData) == asset.sha256 else {
                    throw MediaStoreError.blobCorrupt
                }
            }
            return decoded
        } catch let error as MediaStoreError {
            throw error
        } catch {
            throw MediaStoreError.indexCorrupt
        }
    }

    private func verifyStoredAsset(_ asset: MediaAsset) throws -> URL {
        let url = try containedURL(for: asset)
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadError = .blobMissing
            throw MediaStoreError.blobMissing
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            loadError = .readFailed
            throw MediaStoreError.readFailed
        }
        guard let size = attributes[.size] as? NSNumber,
              size.intValue == asset.byteCount else {
            loadError = .blobCorrupt
            throw MediaStoreError.blobCorrupt
        }
        do {
            guard Self.digest(for: try Data(contentsOf: url)) == asset.sha256 else {
                loadError = .blobCorrupt
                throw MediaStoreError.blobCorrupt
            }
        } catch let error as MediaStoreError {
            throw error
        } catch {
            loadError = .readFailed
            throw MediaStoreError.readFailed
        }
        return url
    }

    private static func validate(_ asset: MediaAsset, directory: URL) throws {
        guard asset.sha256.count == 64,
              asset.sha256.unicodeScalars.allSatisfy({ scalar in
                  (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
              }),
              asset.byteCount >= 0,
              asset.fileExtension.count <= 16,
              asset.fileExtension.unicodeScalars.allSatisfy({
                  (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value)
              })
        else { throw MediaStoreError.invalidAsset }
        _ = try containedURL(for: asset, directory: directory)
    }

    private func validate(_ asset: MediaAsset) throws {
        try Self.validate(asset, directory: directory)
    }

    private static func containedURL(for asset: MediaAsset, directory: URL) throws -> URL {
        let candidate = directory
            .appendingPathComponent("\(asset.sha256).\(asset.fileExtension)")
            .standardizedFileURL
        let base = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        guard candidate.path.hasPrefix(base) else { throw MediaStoreError.invalidAsset }
        return candidate
    }

    private func containedURL(for asset: MediaAsset) throws -> URL {
        try Self.containedURL(for: asset, directory: directory)
    }

    private static func digest(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func persistIndex(_ value: [UUID: MediaAsset]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        let temporary = directory.appendingPathComponent("index.json.tmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(
            to: temporary,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: indexURL.path) {
            _ = try fileManager.replaceItemAt(indexURL, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: indexURL)
        }
    }
}

/// A non-memory placeholder used only while the composition root presents recoverable boot
/// state. It never pretends that writes succeeded and is not a production data fallback.
public actor UnavailableMediaStore: MediaStore {
    public init() {}

    public func store(_ data: Data, filename: String, kind: MediaAsset.Kind) async throws -> MediaAsset {
        throw MediaStoreError.unavailable
    }

    public func asset(for id: UUID) async throws -> MediaAsset? { throw MediaStoreError.unavailable }
    public func data(for id: UUID) async throws -> Data? { throw MediaStoreError.unavailable }
    public func url(for id: UUID) async throws -> URL? { throw MediaStoreError.unavailable }
    public func removeAll(except keeping: Set<UUID>) async throws {
        _ = keeping
        throw MediaStoreError.unavailable
    }

    public func removeAll() async throws {
        throw MediaStoreError.unavailable
    }
}
