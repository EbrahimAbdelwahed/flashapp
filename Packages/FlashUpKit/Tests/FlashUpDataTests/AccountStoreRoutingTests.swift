import Foundation
import Testing
@testable import FlashUpData
import FlashUpDomain

private struct FixedIdentityResolver: CloudAccountIdentityResolver {
    let identity: CloudAccountIdentityResolution

    func resolve() async -> CloudAccountIdentityResolution { identity }
}

private actor SequenceIdentityResolver: CloudAccountIdentityResolver {
    private var identities: [CloudAccountIdentityResolution]

    init(_ identities: [CloudAccountIdentityResolution]) {
        self.identities = identities
    }

    func resolve() async -> CloudAccountIdentityResolution {
        if identities.count > 1 { return identities.removeFirst() }
        return identities.first ?? .couldNotDetermine
    }
}

private actor SupersededIdentityResolver: CloudAccountIdentityResolver {
    private var waitsForFirstResolve = true
    private var firstResolveStarted = false
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var releaseFirst: CheckedContinuation<Void, Never>?

    func waitUntilFirstResolveStarts() async {
        if firstResolveStarted { return }
        await withCheckedContinuation { continuation in
            startedWaiter = continuation
        }
    }

    func releaseFirstResolve() {
        releaseFirst?.resume()
        releaseFirst = nil
    }

    func resolve() async -> CloudAccountIdentityResolution {
        guard waitsForFirstResolve else { return .available(recordName: "account-A") }
        waitsForFirstResolve = false
        firstResolveStarted = true
        startedWaiter?.resume()
        startedWaiter = nil
        await withCheckedContinuation { continuation in
            releaseFirst = continuation
        }
        return .available(recordName: "account-A")
    }
}

private func localProfileOpener() -> AccountStoreCoordinator.ProfileOpener {
    { configuration, sessionURL, mediaURL, _ in
        guard let storeURL = configuration.storeURL else {
            throw AccountStoreRoutingError.invalidProfile
        }
        let library = try CoreDataLibraryRepository(
            configuration: .onDisk(storeURL: storeURL),
            sessionURL: sessionURL
        )
        let mediaStore = try FileMediaStore(directory: mediaURL)
        return (library: library, mediaStore: mediaStore)
    }
}

@Suite("Account-scoped store routing", .serialized)
struct AccountStoreRoutingTests { // swiftlint:disable:this type_body_length
    @Test("Anonymous and identified profiles are isolated before opening a store")
    func profilesAreDistinctAndCloudKitScoped() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let secret = InMemoryDeviceSecretStore(value: Data(repeating: 7, count: 32))
        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: FixedIdentityResolver(identity: .noAccount),
            secretStore: secret,
            observeAccountChanges: false
        )

        let anonymous = try await coordinator.profileDescriptor(for: .noAccount)
        let accountA = try await coordinator.profileDescriptor(for: .available(recordName: "record-A"))
        let accountB = try await coordinator.profileDescriptor(for: .available(recordName: "record-B"))

        #expect(anonymous.kind == .anonymous)
        #expect(anonymous.cloudKit == false)
        #expect(accountA.kind == .account)
        #expect(accountA.cloudKit)
        #expect(accountB.cloudKit)
        #expect(accountA.storeURL != accountB.storeURL)
        #expect(accountA.mediaURL != accountB.mediaURL)
        #expect(accountA.storeURL.lastPathComponent == "Private.sqlite")
        let catalogBytes = try Data(
            contentsOf: root.appendingPathComponent("Stores/catalog.json")
        )
        let catalogText = try #require(String(bytes: catalogBytes, encoding: .utf8))
        #expect(!catalogText.contains("record-A"))
        #expect(!catalogText.contains("record-B"))
    }

    @Test("An existing account profile cannot silently create a replacement device key")
    func missingKeyEntersRecovery() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let accounts = root.appendingPathComponent("Stores/Accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: accounts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: accounts.appendingPathComponent(String(repeating: "a", count: 64), isDirectory: true),
            withIntermediateDirectories: true
        )
        let catalog = root.appendingPathComponent("Stores/catalog.json")
        let fingerprint = String(repeating: "a", count: 64)
        let data = Data(
            "{\"version\":1,\"accountFingerprints\":[\"\(fingerprint)\"],\"legacyMigrationIDs\":[]}".utf8
        )
        try data.write(to: catalog)

        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: FixedIdentityResolver(identity: .noAccount),
            secretStore: InMemoryDeviceSecretStore(),
            observeAccountChanges: false
        )
        await #expect(throws: AccountStoreRoutingError.keyUnavailable) {
            _ = try await coordinator.open()
        }
    }

    @Test("Legacy global data is cloned with sidecars and originals remain")
    func legacyCloneIsRecoverable() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = root.appendingPathComponent("Private.sqlite")
        let session = root.appendingPathComponent("session-state.json")
        let recovery = root.appendingPathComponent("Recovery/previous", isDirectory: true)
        let media = root.appendingPathComponent("Media", isDirectory: true)
        let externalMedia = root.deletingLastPathComponent().appendingPathComponent("Media", isDirectory: true)
        try Data("legacy-store".utf8).write(to: store)
        try Data("legacy-wal".utf8).write(to: URL(fileURLWithPath: store.path + "-wal"))
        try Data("legacy-shm".utf8).write(to: URL(fileURLWithPath: store.path + "-shm"))
        try Data("legacy-history".utf8).write(to: root.appendingPathComponent("Private.history-token"))
        try Data("legacy-session".utf8).write(to: session)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        try Data("recovery-copy".utf8).write(to: recovery.appendingPathComponent("artifact.bin"))
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("media-index".utf8).write(to: media.appendingPathComponent("index.json"))
        try FileManager.default.createDirectory(at: externalMedia, withIntermediateDirectories: true)
        try Data("historical-media".utf8).write(to: externalMedia.appendingPathComponent("old.bin"))

        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: FixedIdentityResolver(identity: .noAccount),
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 3, count: 32)),
            observeAccountChanges: false
        )
        let migrationIDs = try await coordinator.legacyMigrationIDs()
        let migrationID = try #require(migrationIDs.first)
        let legacy = try await coordinator.legacyDescriptor(for: migrationID)
        #expect(try Data(contentsOf: store) == Data("legacy-store".utf8))
        #expect(try Data(contentsOf: legacy.storeURL) == Data("legacy-store".utf8))
        #expect(legacy.cloudKit == false)
        #expect(FileManager.default.fileExists(atPath: session.path))
        let legacySession = legacy.storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("session-state.json")
        #expect(FileManager.default.fileExists(atPath: legacySession.path))
        let legacyRoot = legacy.storeURL.deletingLastPathComponent()
        #expect(try Data(contentsOf: URL(fileURLWithPath: legacy.storeURL.path + "-wal")) == Data("legacy-wal".utf8))
        #expect(
            try Data(contentsOf: legacyRoot.appendingPathComponent("Private.history-token")) ==
                Data("legacy-history".utf8)
        )
        #expect(
            try Data(contentsOf: legacyRoot.appendingPathComponent("Recovery/previous/artifact.bin")) ==
                Data("recovery-copy".utf8)
        )
        #expect(try Data(contentsOf: legacyRoot.appendingPathComponent("Media/index.json")) == Data("media-index".utf8))
        #expect(try Data(contentsOf: legacyRoot.appendingPathComponent("Media/old.bin")) == Data("historical-media".utf8))
        let manifest = try Data(contentsOf: legacyRoot.appendingPathComponent("legacy-manifest.json"))
        let manifestText = try #require(String(data: manifest, encoding: .utf8))
        #expect(manifestText.contains("old.bin"))
        #expect(manifestText.contains("sourceRelativePath"))
    }

    @Test("A cloned legacy profile is selected local-only until explicit transfer")
    func legacyProfileIsActiveAfterClone() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceStore = root.appendingPathComponent("Private.sqlite")
        let controller = try PersistenceController(configuration: .onDisk(storeURL: sourceStore))
        try controller.close()

        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: FixedIdentityResolver(identity: .noAccount),
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 4, count: 32)),
            profileOpener: localProfileOpener()
        )
        let bundle = try await coordinator.open()
        #expect(bundle.profile.kind == .legacy)
        #expect(await coordinator.currentProfile()?.kind == .legacy)
        let descriptor = try await coordinator.profileDescriptor(for: .noAccount)
        #expect(descriptor.kind == .legacy)
        #expect(descriptor.cloudKit == false)
        try await coordinator.close()
    }

    @Test("A quarantined legacy profile wins over available account identity")
    func legacyProfileRemainsActiveWhenAccountIsAvailable() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let controller = try PersistenceController(
            configuration: .onDisk(storeURL: root.appendingPathComponent("Private.sqlite"))
        )
        try controller.close()

        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: FixedIdentityResolver(identity: .available(recordName: "account-A")),
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 8, count: 32)),
            profileOpener: localProfileOpener()
        )
        let bundle = try await coordinator.open()
        #expect(bundle.profile.kind == .legacy)
        let descriptor = try await coordinator.profileDescriptor(
            for: .available(recordName: "account-A")
        )
        #expect(descriptor.kind == .legacy)
        #expect(descriptor.cloudKit == false)
        try await coordinator.close()
    }

    @Test("A to B to A and sign-out preserve exact profile ownership")
    func accountTransitionsPreserveProfileData() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = SequenceIdentityResolver([
            .available(recordName: "account-A"),
            .available(recordName: "account-B"),
            .noAccount,
            .available(recordName: "account-A")
        ])
        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: resolver,
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 5, count: 32)),
            profileOpener: localProfileOpener()
        )
        let events = coordinator.transitionEvents()
        let collected = Task {
            var values: [AccountStoreTransitionEvent] = []
            for await event in events { values.append(event) }
            return values
        }

        let accountA = try await coordinator.open()
        _ = try await accountA.library.createDeck(named: "A data")
        let accountB = try await coordinator.transition()
        #expect(accountB.profile.kind == .account)
        _ = try await accountB.library.createDeck(named: "B data")
        let anonymous = try await coordinator.transition()
        #expect(anonymous.profile.kind == .anonymous)
        let returnedA = try await coordinator.transition()
        #expect(returnedA.profile.kind == .account)
        let returnedADecks = try await returnedA.library.decks()
        #expect(returnedADecks.contains(where: { $0.deck.name == "A data" }))
        await #expect(throws: LibraryRepositoryError.readFailed) {
            _ = try await accountB.library.decks()
        }
        try await coordinator.close()

        let transitionEvents = await collected.value
        let generations = transitionEvents.map { event -> UInt64 in
            switch event {
            case let .bootstrapping(generation), let .switching(generation),
                 let .ready(generation, _), let .failed(generation, _):
                return generation
            }
        }
        #expect(generations == [1, 1, 2, 2, 3, 3, 4, 4])
    }

    @Test("Cold indeterminate identity never guesses an account")
    func indeterminateIdentityUsesAnonymousRoute() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 6, count: 32)),
            observeAccountChanges: false
        )
        let descriptor = try await coordinator.profileDescriptor(for: .couldNotDetermine)
        #expect(descriptor.kind == .anonymous)
        #expect(descriptor.cloudKit == false)
    }

    @Test("Malformed or missing device keys enter recovery without replacement")
    func malformedKeyEntersRecovery() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 1, count: 31)),
            observeAccountChanges: false
        )
        await #expect(throws: AccountStoreRoutingError.keychainUnavailable) {
            _ = try await coordinator.profileDescriptor(for: .noAccount)
        }
    }

    @Test("A corrupt profile catalog fails closed without opening a replacement")
    func corruptCatalogEntersRecovery() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stores = root.appendingPathComponent("Stores", isDirectory: true)
        try FileManager.default.createDirectory(at: stores, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: stores.appendingPathComponent("catalog.json"))

        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: FixedIdentityResolver(identity: .couldNotDetermine),
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 2, count: 32)),
            observeAccountChanges: false
        )
        await #expect(throws: AccountStoreRoutingError.catalogCorrupt) {
            _ = try await coordinator.open()
        }
        #expect(await coordinator.currentProfile() == nil)
    }

    @Test("A superseded generation cannot publish a stale owner")
    func supersededGenerationIsRejected() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = SupersededIdentityResolver()
        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: resolver,
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 2, count: 32)),
            profileOpener: localProfileOpener()
        )
        let first = Task { () -> AccountStoreRoutingError? in
            do {
                _ = try await coordinator.open()
                return nil
            } catch let error as AccountStoreRoutingError {
                return error
            }
        }
        await resolver.waitUntilFirstResolveStarts()
        let second = Task { try await coordinator.transition() }
        _ = try await second.value
        await resolver.releaseFirstResolve()
        let firstResult = try await first.value
        #expect(firstResult == .transitionSuperseded)
        #expect(await coordinator.currentProfile()?.kind == .account)
        try await coordinator.close()
    }

    @Test("A transition closes the old owner before opening the new profile")
    func transitionReplacesSingleOwner() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: FixedIdentityResolver(identity: .noAccount),
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 9, count: 32)),
            observeAccountChanges: false
        )
        let first = try await coordinator.open()
        _ = try await first.library.createDeck(named: "A only")
        let oldAsset = try await first.mediaStore.store(
            Data("A media".utf8),
            filename: "a.txt",
            kind: .image
        )
        let second = try await coordinator.transition()
        #expect(second.profile.kind == .anonymous)
        #expect(await coordinator.currentProfile()?.kind == .anonymous)
        await #expect(throws: LibraryRepositoryError.readFailed) {
            _ = try await first.library.decks()
        }
        await #expect(throws: MediaStoreError.unavailable) {
            _ = try await first.mediaStore.data(for: oldAsset.id)
        }
        try await coordinator.close()
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-account-routing", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
