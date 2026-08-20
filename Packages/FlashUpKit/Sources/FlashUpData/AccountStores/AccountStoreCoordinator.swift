// swiftlint:disable file_length

import CloudKit
import CryptoKit
import FlashUpDomain
import Foundation

/// The only identity information that leaves the account-routing seam.  The record name is
/// intentionally kept inside the resolver/registry boundary and is never carried by UI or
/// repository values.
public enum CloudAccountIdentityResolution: Sendable, Equatable {
    case available(recordName: String)
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case localOnly
}

public protocol CloudAccountIdentityResolver: Sendable {
    func resolve() async -> CloudAccountIdentityResolution
}

/// Production resolver.  CloudKit identity is resolved before the first persistent store is
/// constructed.  A transient failure is represented as indeterminate rather than guessed from
/// a previously opened profile.
public struct CloudKitAccountIdentityResolver: CloudAccountIdentityResolver {
    private let containerIdentifier: String

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    public func resolve() async -> CloudAccountIdentityResolution {
        let container = CKContainer(identifier: containerIdentifier)
        do {
            switch try await container.accountStatus() {
            case .available:
                let record = try await container.userRecordID()
                return .available(recordName: record.recordName)
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            case .couldNotDetermine:
                return .couldNotDetermine
            @unknown default:
                return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
    }
}

public protocol DeviceSecretStore: Sendable {
    func read() throws -> Data?
    func createIfMissing() throws -> Data
}

public enum AccountStoreRoutingError: Error, Equatable, LocalizedError, Sendable {
    case catalogUnavailable
    case catalogCorrupt
    case keyUnavailable
    case keychainUnavailable
    case invalidProfile
    case transitionSuperseded
    case legacyCloneFailed

    public var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            "FlashApp's profile catalog is unavailable. Existing data was preserved."
        case .catalogCorrupt:
            "FlashApp's profile catalog is corrupt. Existing data was preserved."
        case .keyUnavailable:
            "FlashApp's device key is unavailable. Existing data was preserved."
        case .keychainUnavailable:
            "FlashApp could not access its device key. Existing data was preserved."
        case .invalidProfile:
            "FlashApp's profile is invalid. Existing data was preserved."
        case .transitionSuperseded:
            "FlashApp's account transition was superseded by a newer transition."
        case .legacyCloneFailed:
            "FlashApp could not preserve the previous local store. Existing data was preserved."
        }
    }
}

#if canImport(Security)
import Security

/// A non-synchronizable, device-only Keychain secret.  The service/account labels are stable
/// implementation constants and contain no user identity.
public struct KeychainDeviceSecretStore: DeviceSecretStore {
    private static let service = "com.flashup.app.device-store-key"
    private static let account = "routing-key"

    public init() {}

    public func read() throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(Self.lookupQuery() as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else {
                throw AccountStoreRoutingError.keychainUnavailable
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw AccountStoreRoutingError.keychainUnavailable
        }
    }

    public func createIfMissing() throws -> Data {
        if let existing = try read() { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AccountStoreRoutingError.keychainUnavailable
        }
        let data = Data(bytes)
        let item = Self.addAttributes(data: data)
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard let reread = try read(), reread.count == 32 else {
                throw AccountStoreRoutingError.keychainUnavailable
            }
            return reread
        }
        guard status == errSecSuccess else { throw AccountStoreRoutingError.keychainUnavailable }
        return data
    }

    private static func lookupQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
    }

    private static func addAttributes(data: Data) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
#else
public struct KeychainDeviceSecretStore: DeviceSecretStore {
    public init() {}
    public func read() throws -> Data? { throw AccountStoreRoutingError.keychainUnavailable }
    public func createIfMissing() throws -> Data { throw AccountStoreRoutingError.keychainUnavailable }
}
#endif

/// Test/preview secret store.  It is deliberately not used by the production composition root.
public final class InMemoryDeviceSecretStore: @unchecked Sendable, DeviceSecretStore {
    private let lock = NSLock()
    private var value: Data?

    public init(value: Data? = nil) { self.value = value }

    public func read() throws -> Data? { lock.withLock { value } }

    public func createIfMissing() throws -> Data {
        lock.withLock {
            if let value { return value }
            let value = Data((0..<32).map { UInt8($0) })
            self.value = value
            return value
        }
    }
}

public enum AccountProfileKind: String, Equatable, Sendable {
    case anonymous
    case account
    case legacy
}

/// Sanitized public profile information.  The underlying profile identifier and URLs are
/// internal routing data and cannot leak into UI, defaults, logs or exports.
public struct AccountStoreProfile: Equatable, Sendable {
    public let kind: AccountProfileKind
}

public struct AccountStoreBundle: Sendable {
    public let library: CoreDataLibraryRepository
    public let mediaStore: FileMediaStore
    public let profile: AccountStoreProfile

}

public enum AccountStoreTransitionEvent: Sendable {
    case bootstrapping(generation: UInt64)
    case switching(generation: UInt64)
    case ready(generation: UInt64, bundle: AccountStoreBundle)
    case failed(generation: UInt64, error: AccountStoreRoutingError)
}

/// Registry and lifecycle coordinator for exactly one open profile.  It owns all profile-side
/// paths; callers receive only repository/media ports and a sanitized profile kind.
public actor AccountStoreCoordinator { // swiftlint:disable:this type_body_length
    internal typealias ProfileOpener = @Sendable (
        PersistenceConfiguration,
        URL,
        URL,
        AccountProfileKind
    ) throws -> (library: CoreDataLibraryRepository, mediaStore: FileMediaStore)

    private struct Catalog: Codable, Equatable {
        var version: Int = 1
        var accountFingerprints: [String] = []
        var legacyMigrationIDs: [String] = []
    }

    private struct LegacyCloneEntry: Codable, Equatable {
        let sourceRelativePath: String
        let destinationRelativePath: String
        let byteCount: Int
        let sha256: String
    }

    private struct LegacyCloneManifest: Codable, Equatable {
        let version: Int
        let sourceRoot: String
        let destinationRoot: String
        let entries: [LegacyCloneEntry]
    }

    private struct ProfileDescriptor: Equatable, Sendable {
        let kind: AccountProfileKind
        let identifier: String
        let directoryURL: URL
        let storeURL: URL
        let sessionURL: URL
        let mediaURL: URL
        let configuration: PersistenceConfiguration
    }

    private struct ActiveStore {
        let generation: UInt64
        let descriptor: ProfileDescriptor
        let library: CoreDataLibraryRepository
        let mediaStore: FileMediaStore
    }

    internal struct RoutingDescriptor: Equatable, Sendable {
        let kind: AccountProfileKind
        let storeURL: URL
        let mediaURL: URL
        let cloudKit: Bool
    }

    private let rootURL: URL
    private let storesURL: URL
    private let containerIdentifier: String
    private let resolver: any CloudAccountIdentityResolver
    private let secretStore: any DeviceSecretStore
    private let fileManager: FileManager
    private let profileOpener: ProfileOpener?
    private let transitionStream: AsyncStream<AccountStoreTransitionEvent>
    private let transitionContinuation: AsyncStream<AccountStoreTransitionEvent>.Continuation
    private var catalog: Catalog?
    private var secret: Data?
    private var active: ActiveStore?
    private var generation: UInt64 = 0
    private var accountChangeObserver: NSObjectProtocol?
    private var accountChangeTask: Task<Void, Never>?
    private let observesAccountChanges: Bool

    public init(
        rootURL: URL,
        containerIdentifier: String,
        resolver: (any CloudAccountIdentityResolver)? = nil,
        secretStore: any DeviceSecretStore = KeychainDeviceSecretStore(),
        fileManager: FileManager = .default,
        observeAccountChanges: Bool = true
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.storesURL = rootURL.appendingPathComponent("Stores", isDirectory: true).standardizedFileURL
        self.containerIdentifier = containerIdentifier
        self.resolver = resolver ?? CloudKitAccountIdentityResolver(containerIdentifier: containerIdentifier)
        self.secretStore = secretStore
        self.fileManager = fileManager
        self.profileOpener = nil
        let stream = AsyncStream<AccountStoreTransitionEvent>.makeStream()
        self.transitionStream = stream.stream
        self.transitionContinuation = stream.continuation
        self.observesAccountChanges = observeAccountChanges
    }

    internal init(
        rootURL: URL,
        containerIdentifier: String,
        resolver: (any CloudAccountIdentityResolver)? = nil,
        secretStore: any DeviceSecretStore = KeychainDeviceSecretStore(),
        fileManager: FileManager = .default,
        observeAccountChanges: Bool = false,
        profileOpener: @escaping ProfileOpener
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.storesURL = rootURL.appendingPathComponent("Stores", isDirectory: true).standardizedFileURL
        self.containerIdentifier = containerIdentifier
        self.resolver = resolver ?? CloudKitAccountIdentityResolver(containerIdentifier: containerIdentifier)
        self.secretStore = secretStore
        self.fileManager = fileManager
        self.profileOpener = profileOpener
        let stream = AsyncStream<AccountStoreTransitionEvent>.makeStream()
        self.transitionStream = stream.stream
        self.transitionContinuation = stream.continuation
        self.observesAccountChanges = observeAccountChanges
    }

    deinit {
        accountChangeTask?.cancel()
        if let accountChangeObserver {
            NotificationCenter.default.removeObserver(accountChangeObserver)
        }
        transitionContinuation.finish()
    }

    public nonisolated func transitionEvents() -> AsyncStream<AccountStoreTransitionEvent> {
        transitionStream
    }

    public func currentProfile() -> AccountStoreProfile? {
        active.map { AccountStoreProfile(kind: $0.descriptor.kind) }
    }

    /// Opens the profile selected by a fresh identity preflight.  No persistent Core Data
    /// container is created until this method has resolved account state and catalog safety.
    public func open() async throws -> AccountStoreBundle {
        try await performTransition(phase: .bootstrapping)
    }

    /// Closes the current owner before resolving and opening the next profile.  Generation
    /// checks ensure a stale asynchronous result can never replace a newer transition.
    public func transition() async throws -> AccountStoreBundle {
        try await performTransition(phase: .switching)
    }

    private enum TransitionPhase {
        case bootstrapping
        case switching
    }

    private func performTransition(phase: TransitionPhase) async throws -> AccountStoreBundle {
        generation &+= 1
        let transitionGeneration = generation
        do {
            if let active {
                // Seal media before publishing the transition state. The old bundle can no
                // longer serve bytes while the repository write fence is installed.
                await active.mediaStore.close()
                await active.library.beginAccountTransition()
            }
            emit(phase: phase, generation: transitionGeneration)
            try await closeActive()

            try prepareRegistry()
            let identity = await resolver.resolve()
            guard generation == transitionGeneration else {
                throw AccountStoreRoutingError.transitionSuperseded
            }
            let descriptor = try descriptor(for: identity)
            let opened = try open(descriptor: descriptor)
            guard generation == transitionGeneration else {
                try? await opened.library.close()
                await opened.mediaStore.close()
                throw AccountStoreRoutingError.transitionSuperseded
            }
            active = ActiveStore(
                generation: transitionGeneration,
                descriptor: descriptor,
                library: opened.library,
                mediaStore: opened.mediaStore
            )
            let bundle = AccountStoreBundle(
                library: opened.library,
                mediaStore: opened.mediaStore,
                profile: AccountStoreProfile(kind: descriptor.kind)
            )
            transitionContinuation.yield(.ready(generation: transitionGeneration, bundle: bundle))
            return bundle
        } catch let error as AccountStoreRoutingError {
            if error != .transitionSuperseded {
                transitionContinuation.yield(.failed(generation: transitionGeneration, error: error))
            }
            throw error
        } catch {
            transitionContinuation.yield(
                .failed(generation: transitionGeneration, error: .invalidProfile)
            )
            throw AccountStoreRoutingError.invalidProfile
        }
    }

    public func close() async throws {
        generation &+= 1
        accountChangeTask?.cancel()
        accountChangeTask = nil
        if let accountChangeObserver {
            NotificationCenter.default.removeObserver(accountChangeObserver)
            self.accountChangeObserver = nil
        }
        transitionContinuation.finish()
        try await closeActive()
    }

    private func emit(phase: TransitionPhase, generation: UInt64) {
        switch phase {
        case .bootstrapping:
            transitionContinuation.yield(.bootstrapping(generation: generation))
        case .switching:
            transitionContinuation.yield(.switching(generation: generation))
        }
    }

    /// Returns a sanitized descriptor for tests/recovery tooling without exposing it through the
    /// public bundle.  This method is internal to FlashUpData and never used by UI/export.
    internal func profileDescriptor(for identity: CloudAccountIdentityResolution) throws -> RoutingDescriptor {
        try prepareRegistry()
        let descriptor = try descriptor(for: identity)
        return RoutingDescriptor(
            kind: descriptor.kind,
            storeURL: descriptor.storeURL,
            mediaURL: descriptor.mediaURL,
            cloudKit: descriptor.configuration.kind.isCloudKit
        )
    }

    internal func legacyMigrationIDs() throws -> [String] {
        try prepareRegistry()
        return catalog?.legacyMigrationIDs ?? []
    }

    internal func legacyDescriptor(for migrationID: String) throws -> RoutingDescriptor {
        try prepareRegistry()
        guard catalog?.legacyMigrationIDs.contains(migrationID) == true else {
            throw AccountStoreRoutingError.invalidProfile
        }
        let descriptor = makeDescriptor(kind: .legacy, identifier: migrationID, cloudKit: false)
        return RoutingDescriptor(
            kind: descriptor.kind,
            storeURL: descriptor.storeURL,
            mediaURL: descriptor.mediaURL,
            cloudKit: descriptor.configuration.kind.isCloudKit
        )
    }

    private func closeActive() async throws {
        guard let active else { return }
        await active.mediaStore.close()
        do {
            try await active.library.close()
            self.active = nil
        } catch {
            // The repository is terminally revoked even when its underlying close fails. Do
            // not retain it as an active owner and never proceed to opening profile B.
            self.active = nil
            throw LibraryRepositoryError.writeFailed
        }
    }

    private func prepareRegistry() throws { // swiftlint:disable:this cyclomatic_complexity
        installAccountChangeObserverIfNeeded()
        if catalog != nil, secret != nil { return }
        do {
            try fileManager.createDirectory(at: storesURL, withIntermediateDirectories: true)
            var loaded = try loadCatalog()
            if loaded == nil {
                let hasProfiles = try hasProfileDirectories()
                if hasProfiles {
                    throw AccountStoreRoutingError.catalogUnavailable
                }
                let newCatalog = Catalog()
                loaded = newCatalog
                try saveCatalog(newCatalog)
            }
            guard let loaded else { throw AccountStoreRoutingError.catalogUnavailable }
            let hasAccountProfiles = !loaded.accountFingerprints.isEmpty || hasAccountDirectories()
            let loadedSecret = try secretStore.read()
            if let loadedSecret, loadedSecret.count != 32 {
                throw AccountStoreRoutingError.keychainUnavailable
            }
            if hasAccountProfiles {
                guard let loadedSecret else { throw AccountStoreRoutingError.keyUnavailable }
                secret = loadedSecret
            } else {
                if let loadedSecret {
                    secret = loadedSecret
                } else {
                    let created = try secretStore.createIfMissing()
                    guard created.count == 32 else {
                        throw AccountStoreRoutingError.keychainUnavailable
                    }
                    secret = created
                }
            }
            catalog = loaded
            try quarantineLegacyIfNeeded()
        } catch let error as AccountStoreRoutingError {
            throw error
        } catch {
            throw AccountStoreRoutingError.catalogCorrupt
        }
    }

    private func installAccountChangeObserverIfNeeded() {
        guard observesAccountChanges, accountChangeObserver == nil else { return }
        accountChangeObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.scheduleAccountTransition() }
        }
    }

    private func scheduleAccountTransition() {
        accountChangeTask?.cancel()
        accountChangeTask = Task { [weak self] in
            _ = try? await self?.transition()
        }
    }

    private func loadCatalog() throws -> Catalog? {
        let url = storesURL.appendingPathComponent("catalog.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
            guard catalog.version == 1,
                  catalog.accountFingerprints.allSatisfy(Self.isValidFingerprint),
                  catalog.legacyMigrationIDs.allSatisfy(Self.isValidMigrationID) else {
                throw AccountStoreRoutingError.catalogCorrupt
            }
            return catalog
        } catch let error as AccountStoreRoutingError {
            throw error
        } catch {
            throw AccountStoreRoutingError.catalogCorrupt
        }
    }

    private func saveCatalog(_ value: Catalog) throws {
        let url = storesURL.appendingPathComponent("catalog.json")
        let temporary = storesURL.appendingPathComponent("catalog.json.tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        do {
            try JSONEncoder().encode(value).write(to: temporary, options: [.atomic])
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: url)
            }
        } catch {
            throw AccountStoreRoutingError.catalogUnavailable
        }
    }

    private func descriptor(for identity: CloudAccountIdentityResolution) throws -> ProfileDescriptor {
        guard var catalog, let secret else { throw AccountStoreRoutingError.catalogUnavailable }
        // A provenance-unknown store is quarantined until an explicit archive transfer. This
        // rule applies even when a current account is available or identity is indeterminate.
        if let migrationID = catalog.legacyMigrationIDs.first {
            return makeDescriptor(kind: .legacy, identifier: migrationID, cloudKit: false)
        }
        switch identity {
        case let .available(recordName):
            let fingerprint = Self.fingerprint(
                secret: secret,
                containerIdentifier: containerIdentifier,
                recordName: recordName
            )
            if !catalog.accountFingerprints.contains(fingerprint) {
                catalog.accountFingerprints.append(fingerprint)
                catalog.accountFingerprints.sort()
                try saveCatalog(catalog)
                self.catalog = catalog
            }
            return makeDescriptor(kind: .account, identifier: fingerprint, cloudKit: true)
        case .noAccount, .localOnly:
            return makeDescriptor(kind: .anonymous, identifier: "Anonymous", cloudKit: false)
        case .restricted, .temporarilyUnavailable, .couldNotDetermine:
            return makeDescriptor(kind: .anonymous, identifier: "Anonymous", cloudKit: false)
        }
    }

    private func makeDescriptor(kind: AccountProfileKind, identifier: String, cloudKit: Bool) -> ProfileDescriptor {
        let directory: URL
        switch kind {
        case .anonymous:
            directory = storesURL.appendingPathComponent("Anonymous", isDirectory: true)
        case .account:
            directory = storesURL.appendingPathComponent("Accounts", isDirectory: true)
                .appendingPathComponent(identifier, isDirectory: true)
        case .legacy:
            directory = storesURL.appendingPathComponent("Legacy", isDirectory: true)
                .appendingPathComponent(identifier, isDirectory: true)
        }
        let storeURL = directory.appendingPathComponent("Private.sqlite")
        return ProfileDescriptor(
            kind: kind,
            identifier: identifier,
            directoryURL: directory,
            storeURL: storeURL,
            sessionURL: directory.appendingPathComponent("session-state.json"),
            mediaURL: directory.appendingPathComponent("Media", isDirectory: true),
            configuration: cloudKit
                ? .cloudKit(storeURL: storeURL, containerIdentifier: containerIdentifier)
                : .onDisk(storeURL: storeURL)
        )
    }

    private func open(
        descriptor: ProfileDescriptor
    ) throws -> (library: CoreDataLibraryRepository, mediaStore: FileMediaStore) {
        try fileManager.createDirectory(at: descriptor.directoryURL, withIntermediateDirectories: true)
        do {
            if let profileOpener {
                return try profileOpener(
                    descriptor.configuration,
                    descriptor.sessionURL,
                    descriptor.mediaURL,
                    descriptor.kind
                )
            }
            let mediaStore = try FileMediaStore(directory: descriptor.mediaURL)
            let library = try CoreDataLibraryRepository(
                configuration: descriptor.configuration,
                sessionURL: descriptor.sessionURL,
                status: descriptor.kind == .account
                    ? .failed(reason: "iCloud account status is being resolved.")
                    : .offline
            )
            return (library, mediaStore)
        } catch {
            // Persistence errors may carry a filesystem recovery URL.  Keep the artifact on
            // disk for support, but do not let an account fingerprint/path reach App/UI export.
            throw AccountStoreRoutingError.invalidProfile
        }
    }

    private func quarantineLegacyIfNeeded() throws {
        guard var catalog else { throw AccountStoreRoutingError.catalogUnavailable }
        let sourceStore = rootURL.appendingPathComponent("Private.sqlite")
        guard fileManager.fileExists(atPath: sourceStore.path), catalog.legacyMigrationIDs.isEmpty else { return }
        let migrationID = UUID().uuidString.lowercased()
        let destination = storesURL.appendingPathComponent("Legacy", isDirectory: true)
            .appendingPathComponent(migrationID, isDirectory: true)
        let temporary = storesURL.appendingPathComponent("Legacy", isDirectory: true)
            .appendingPathComponent(".quarantine-\(migrationID)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            var entries: [LegacyCloneEntry] = []
            try copyStoreFamily(from: rootURL, to: temporary, entries: &entries)
            try copyLegacySidecars(to: temporary, entries: &entries)
            try verifyLegacyClone(entries: entries, at: temporary)
            try writeLegacyManifest(entries: entries, at: temporary)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: temporary, to: destination)
            catalog.legacyMigrationIDs = [migrationID]
            try saveCatalog(catalog)
            self.catalog = catalog
        } catch let error as AccountStoreRoutingError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw AccountStoreRoutingError.legacyCloneFailed
        }
    }

    private func copyStoreFamily(
        from sourceRoot: URL,
        to destinationRoot: URL,
        entries: inout [LegacyCloneEntry]
    ) throws {
        for suffix in ["", "-wal", "-shm"] {
            let sourceRelativePath = "Private.sqlite\(suffix)"
            let source = sourceRoot.appendingPathComponent(sourceRelativePath)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try copyLegacyFile(
                source,
                sourceRelativePath: sourceRelativePath,
                destinationRelativePath: sourceRelativePath,
                to: destinationRoot,
                entries: &entries
            )
        }
        let historyToken = sourceRoot.appendingPathComponent("Private.history-token")
        if fileManager.fileExists(atPath: historyToken.path) {
            try copyLegacyFile(
                historyToken,
                sourceRelativePath: "Private.history-token",
                destinationRelativePath: "Private.history-token",
                to: destinationRoot,
                entries: &entries
            )
        }
    }

    private func copyLegacySidecars(
        to destinationRoot: URL,
        entries: inout [LegacyCloneEntry]
    ) throws {
        let session = rootURL.appendingPathComponent("session-state.json")
        if fileManager.fileExists(atPath: session.path) {
            try copyLegacyFile(
                session,
                sourceRelativePath: "session-state.json",
                destinationRelativePath: "session-state.json",
                to: destinationRoot,
                entries: &entries
            )
        }
        let externalMedia = rootURL.deletingLastPathComponent()
            .appendingPathComponent("Media", isDirectory: true)
        let scopedMedia = rootURL.appendingPathComponent("Media", isDirectory: true)
        if fileManager.fileExists(atPath: externalMedia.path) {
            try copyLegacyDirectory(
                externalMedia,
                sourceRelativeRoot: "../Media",
                destinationRelativeRoot: "Media",
                to: destinationRoot,
                entries: &entries
            )
        }
        if fileManager.fileExists(atPath: scopedMedia.path),
           scopedMedia.standardizedFileURL != externalMedia.standardizedFileURL {
            try copyLegacyDirectory(
                scopedMedia,
                sourceRelativeRoot: "Media",
                destinationRelativeRoot: "Media",
                to: destinationRoot,
                entries: &entries
            )
        }
        let recoverySource = rootURL.appendingPathComponent("Recovery", isDirectory: true)
        if fileManager.fileExists(atPath: recoverySource.path) {
            try copyLegacyDirectory(
                recoverySource,
                sourceRelativeRoot: "Recovery",
                destinationRelativeRoot: "Recovery",
                to: destinationRoot,
                entries: &entries
            )
        }
    }

    private func copyLegacyFile(
        _ source: URL,
        sourceRelativePath: String,
        destinationRelativePath: String,
        to destinationRoot: URL,
        entries: inout [LegacyCloneEntry]
    ) throws {
        let destination = destinationRoot.appendingPathComponent(destinationRelativePath)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            guard try Self.digest(at: source) == Self.digest(at: destination) else {
                throw AccountStoreRoutingError.legacyCloneFailed
            }
        } else {
            try fileManager.copyItem(at: source, to: destination)
        }
        entries.append(LegacyCloneEntry(
            sourceRelativePath: sourceRelativePath,
            destinationRelativePath: destinationRelativePath,
            byteCount: try Data(contentsOf: source).count,
            sha256: try Self.digest(at: source)
        ))
    }

    private func copyLegacyDirectory(
        _ sourceRoot: URL,
        sourceRelativeRoot: String,
        destinationRelativeRoot: String,
        to destinationRoot: URL,
        entries: inout [LegacyCloneEntry]
    ) throws {
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { throw AccountStoreRoutingError.legacyCloneFailed }
        let sourcePrefix = sourceRoot.standardizedFileURL.path + "/"
        for case let source as URL in enumerator where !source.hasDirectoryPath {
            let relative = String(source.standardizedFileURL.path.dropFirst(sourcePrefix.count))
            try copyLegacyFile(
                source,
                sourceRelativePath: "\(sourceRelativeRoot)/\(relative)",
                destinationRelativePath: "\(destinationRelativeRoot)/\(relative)",
                to: destinationRoot,
                entries: &entries
            )
        }
    }

    private func verifyLegacyClone(entries: [LegacyCloneEntry], at destinationRoot: URL) throws {
        let destinationFiles = try cloneFiles(root: destinationRoot, excludingStores: false)
            .filter { $0.key != "legacy-manifest.json" }
        let expectedPaths = Set(entries.map(\.destinationRelativePath))
        guard Set(destinationFiles.keys) == expectedPaths else {
            throw AccountStoreRoutingError.legacyCloneFailed
        }
        for entry in entries {
            guard let destination = destinationFiles[entry.destinationRelativePath],
                  try Self.digest(at: destination) == entry.sha256,
                  try Data(contentsOf: destination).count == entry.byteCount else {
                throw AccountStoreRoutingError.legacyCloneFailed
            }
        }
    }

    private func writeLegacyManifest(entries: [LegacyCloneEntry], at destinationRoot: URL) throws {
        let manifest = LegacyCloneManifest(
            version: 1,
            sourceRoot: "Application Support/FlashApp",
            destinationRoot: "Stores/Legacy/<migration-id>",
            entries: entries.sorted { $0.destinationRelativePath < $1.destinationRelativePath }
        )
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(
                to: destinationRoot.appendingPathComponent("legacy-manifest.json"),
                options: [.atomic]
            )
        } catch {
            throw AccountStoreRoutingError.legacyCloneFailed
        }
    }

    private func cloneFiles(root: URL, excludingStores: Bool) throws -> [String: URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys) else { return [:] }
        var files: [String: URL] = [:]
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolvedStores = storesURL.resolvingSymlinksInPath().standardizedFileURL
        for case let url as URL in enumerator {
            let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
            let isOutsideStores = !excludingStores || !resolvedURL.path.hasPrefix(resolvedStores.path)
            guard isOutsideStores, !url.hasDirectoryPath else { continue }
            let prefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
            let relative = String(resolvedURL.path.dropFirst(prefix.count))
            files[relative] = resolvedURL
        }
        return files
    }

    private func hasProfileDirectories() throws -> Bool {
        let names = ["Anonymous", "Accounts", "Legacy"]
        return names.contains {
            fileManager.fileExists(atPath: storesURL.appendingPathComponent($0).path)
        }
    }

    private func hasAccountDirectories() -> Bool {
        let url = storesURL.appendingPathComponent("Accounts", isDirectory: true)
        return (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
            .contains(where: { $0.hasDirectoryPath }) == true
    }

    private static func fingerprint(secret: Data, containerIdentifier: String, recordName: String) -> String {
        let input = Data(containerIdentifier.utf8) + Data([0]) + Data(recordName.utf8)
        return HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: secret))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func digest(at url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isValidFingerprint(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }

    private static func isValidMigrationID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}

private extension PersistenceConfiguration.StoreKind {
    var isCloudKit: Bool {
        if case .cloudKit = self { return true }
        return false
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
