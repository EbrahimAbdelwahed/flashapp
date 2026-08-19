import CryptoKit
import Foundation

/// The storage shapes understood by the V1 persistence seam.
///
/// `cloudKit` is intentionally configuration-only in this package pass: opening a real
/// container needs an Apple account and a deployed schema, so those checks remain a
/// human-required release gate. Tests use the same model and store URL with `onDisk`.
public struct PersistenceConfiguration: Equatable, Sendable {
    public enum StoreKind: Equatable, Sendable {
        case inMemory
        case onDisk
        case cloudKit(containerIdentifier: String)
    }

    public let kind: StoreKind
    public let storeURL: URL?

    public static let inMemory = PersistenceConfiguration(kind: .inMemory, storeURL: nil)

    public static func onDisk(storeURL: URL) -> PersistenceConfiguration {
        PersistenceConfiguration(kind: .onDisk, storeURL: storeURL)
    }

    public static func cloudKit(
        storeURL: URL,
        containerIdentifier: String
    ) -> PersistenceConfiguration {
        PersistenceConfiguration(
            kind: .cloudKit(containerIdentifier: containerIdentifier),
            storeURL: storeURL
        )
    }

    private init(kind: StoreKind, storeURL: URL?) {
        self.kind = kind
        self.storeURL = storeURL
    }
}

public struct RecoveryFile: Equatable, Sendable {
    public let url: URL
    public let byteCount: Int64
    public let sha256: String

    public init(url: URL, byteCount: Int64, sha256: String) {
        self.url = url
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct RecoveryArtifact: Equatable, Sendable {
    public let directoryURL: URL
    public let files: [RecoveryFile]

    public init(directoryURL: URL, files: [RecoveryFile]) {
        self.directoryURL = directoryURL
        self.files = files
    }

    /// Confirms that every preserved file still has the byte count and digest captured at copy time.
    public func isValid(fileManager: FileManager = .default) -> Bool {
        files.allSatisfy { file in
            guard fileManager.fileExists(atPath: file.url.path),
                  let current = try? StoreFileHasher.digest(at: file.url),
                  current.byteCount == file.byteCount else {
                return false
            }
            return current.sha256 == file.sha256
        }
    }
}

public enum PersistenceFailureReason: String, Equatable, Sendable {
    case corruptStore
    case incompatibleModel
    case migrationFailed
    case storeUnreadable
}

public enum PersistenceError: Error, Equatable, LocalizedError {
    case modelUnavailable
    case invalidCloudKitContainerIdentifier
    case invalidStoreURL
    case storeURLRequired
    case storeLoadFailed(recoveryArtifact: RecoveryArtifact?, reason: PersistenceFailureReason)
    case recoverySnapshotFailed
    case storeCloseFailed
    case backgroundWorkRejected

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "The FlashApp V1 Core Data model could not be loaded."
        case .invalidCloudKitContainerIdentifier:
            "The CloudKit container identifier is invalid."
        case .invalidStoreURL:
            "The FlashApp store must use a file URL named Private.sqlite."
        case .storeURLRequired:
            "An on-disk or CloudKit store requires a Private.sqlite URL."
        case .storeLoadFailed:
            "The FlashApp store could not be opened. Existing data was preserved."
        case .recoverySnapshotFailed:
            "The FlashApp store could not be safely prepared. Existing data was preserved."
        case .storeCloseFailed:
            "The FlashApp store could not be closed safely."
        case .backgroundWorkRejected:
            "Background FlashApp work cannot start while the store is closing."
        }
    }
}

struct StoreFileDigest: Equatable {
    let byteCount: Int64
    let sha256: String
}

enum StoreFileHasher {
    static func digest(at url: URL) throws -> StoreFileDigest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
            byteCount += Int64(chunk.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return StoreFileDigest(byteCount: byteCount, sha256: digest)
    }
}
