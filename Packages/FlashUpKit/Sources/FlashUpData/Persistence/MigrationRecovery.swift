import CoreData
import Foundation

internal enum RecoveryCopyEvent {
    case beforeCopy(sourceURL: URL)
    case afterCopy(sourceURL: URL, destinationURL: URL)
}

internal typealias RecoveryCopyHook = (RecoveryCopyEvent) throws -> Void

/// Preserves store files only when preflight shows a migration risk or an unreadable store.
///
/// This is intentionally copy-only. Recovery never deletes, replaces, or recreates the
/// user's original SQLite, WAL, or SHM files.
public enum MigrationRecovery {
    public enum Preflight: Equatable, Sendable {
        case newStore
        case compatible
        case migrationRequired
        case unreadable
    }

    private static let storeSuffixes = ["", "-wal", "-shm"]

    public static func preflight(
        at storeURL: URL,
        model: NSManagedObjectModel,
        fileManager: FileManager = .default
    ) -> Preflight {
        let existingURLs = existingStoreURLs(at: storeURL, fileManager: fileManager)
        guard !existingURLs.isEmpty else { return .newStore }
        guard fileManager.fileExists(atPath: storeURL.path) else { return .unreadable }

        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: storeURL,
                options: nil
            )
            return model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
                ? .compatible
                : .migrationRequired
        } catch {
            return .unreadable
        }
    }

    public static func preserveStoreFiles(
        at storeURL: URL,
        fileManager: FileManager = .default
    ) throws -> RecoveryArtifact? {
        try preserveStoreFiles(at: storeURL, fileManager: fileManager, copyHook: nil)
    }

    internal static func preserveStoreFiles(
        at storeURL: URL,
        fileManager: FileManager,
        copyHook: RecoveryCopyHook?
    ) throws -> RecoveryArtifact? {
        let existingURLs = existingStoreURLs(at: storeURL, fileManager: fileManager)
        guard !existingURLs.isEmpty else { return nil }
        let initialSnapshot = try sourceSnapshot(at: existingURLs)

        let recoveryRoot = storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("Recovery", isDirectory: true)
        let directoryURL = recoveryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var copiedFiles: [RecoveryFile] = []
            for sourceURL in existingURLs {
                try copyHook?(.beforeCopy(sourceURL: sourceURL))
                let sourceDigest = try initialSnapshot.digest(for: sourceURL)
                let destinationURL = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                let copiedDigest = try StoreFileHasher.digest(at: destinationURL)
                guard sourceDigest == copiedDigest else {
                    throw PersistenceError.recoverySnapshotFailed
                }
                copiedFiles.append(
                    RecoveryFile(
                        url: destinationURL,
                        byteCount: copiedDigest.byteCount,
                        sha256: copiedDigest.sha256
                    )
                )
                try copyHook?(.afterCopy(sourceURL: sourceURL, destinationURL: destinationURL))
            }

            let finalSnapshot = try sourceSnapshot(at: existingStoreURLs(at: storeURL, fileManager: fileManager))
            guard initialSnapshot == finalSnapshot else {
                throw PersistenceError.recoverySnapshotFailed
            }
            let artifact = RecoveryArtifact(directoryURL: directoryURL, files: copiedFiles)
            guard artifact.isValid(fileManager: fileManager) else {
                throw PersistenceError.recoverySnapshotFailed
            }
            pruneRecoveryDirectories(at: recoveryRoot, keeping: 2, fileManager: fileManager)
            return artifact
        } catch let error as PersistenceError {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw PersistenceError.recoverySnapshotFailed
        }
    }

    internal static func stageStoreFiles(
        from artifact: RecoveryArtifact,
        fileManager: FileManager = .default
    ) throws -> URL {
        let stagingDirectory = artifact.directoryURL.appendingPathComponent("Staged", isDirectory: true)
        let stagedStoreURL = stagingDirectory.appendingPathComponent("Private.sqlite")
        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            for file in artifact.files {
                let destinationURL = stagingDirectory.appendingPathComponent(file.url.lastPathComponent)
                try fileManager.copyItem(at: file.url, to: destinationURL)
                let copiedDigest = try StoreFileHasher.digest(at: destinationURL)
                guard copiedDigest.byteCount == file.byteCount, copiedDigest.sha256 == file.sha256 else {
                    throw PersistenceError.recoverySnapshotFailed
                }
            }
            guard fileManager.fileExists(atPath: stagedStoreURL.path) else {
                throw PersistenceError.recoverySnapshotFailed
            }
            return stagedStoreURL
        } catch let error as PersistenceError {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw PersistenceError.recoverySnapshotFailed
        }
    }

    internal static func discardStoreFiles(
        at storeURL: URL,
        fileManager: FileManager = .default
    ) {
        for url in existingStoreURLs(at: storeURL, fileManager: fileManager) {
            try? fileManager.removeItem(at: url)
        }
    }

    internal static func discardStagedStore(
        at stagedStoreURL: URL,
        fileManager: FileManager = .default
    ) {
        discardStoreFiles(at: stagedStoreURL, fileManager: fileManager)
        try? fileManager.removeItem(at: stagedStoreURL.deletingLastPathComponent())
    }

    /// Core Data performs the destination replacement while preserving its SQLite semantics.
    internal static func adoptStagedStore(
        at stagedStoreURL: URL,
        to destinationURL: URL,
        model: NSManagedObjectModel
    ) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.replacePersistentStore(
            at: destinationURL,
            destinationOptions: nil,
            withPersistentStoreFrom: stagedStoreURL,
            sourceOptions: nil,
            ofType: NSSQLiteStoreType
        )
    }

    private static func existingStoreURLs(
        at storeURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        storeSuffixes.map { suffix in
            guard !suffix.isEmpty else { return storeURL }
            return URL(fileURLWithPath: storeURL.path + suffix)
        }.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private struct SourceSnapshot: Equatable {
        let urls: [URL]
        let digests: [URL: StoreFileDigest]

        func digest(for url: URL) throws -> StoreFileDigest {
            guard let digest = digests[url] else {
                throw PersistenceError.recoverySnapshotFailed
            }
            return digest
        }
    }

    private static func sourceSnapshot(at urls: [URL]) throws -> SourceSnapshot {
        for url in urls {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw PersistenceError.recoverySnapshotFailed
            }
        }
        return SourceSnapshot(
            urls: urls.sorted { $0.lastPathComponent < $1.lastPathComponent },
            digests: try Dictionary(uniqueKeysWithValues: urls.map { ($0, try StoreFileHasher.digest(at: $0)) })
        )
    }

    private static func pruneRecoveryDirectories(
        at recoveryRoot: URL,
        keeping count: Int,
        fileManager: FileManager
    ) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: recoveryRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        ) else { return }

        let directories = contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return lhsDate > rhsDate
        }
        for directory in directories.dropFirst(count) {
            try? fileManager.removeItem(at: directory)
        }
    }
}
