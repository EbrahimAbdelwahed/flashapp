import Foundation
import Testing
@testable import FlashUpData
import FlashUpDomain

private struct HardeningIdentityResolver: CloudAccountIdentityResolver {
    let identity: CloudAccountIdentityResolution
    func resolve() async -> CloudAccountIdentityResolution { identity }
}

@Suite("Account routing hardening", .serialized)
struct AccountStoreRoutingHardeningTests {
    @Test("The account-change fence rejects repository writes before coordinator actor teardown")
    func accountChangeFenceIsSynchronous() async throws {
        let root = temporaryRoot("fence")
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: HardeningIdentityResolver(identity: .noAccount),
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 4, count: 32)),
            observeAccountChanges: false
        )
        let bundle = try await coordinator.open()
        _ = try await bundle.library.createDeck(named: "Before fence")

        coordinator.armAccountChangeWriteFenceForTesting()

        await #expect(throws: LibraryRepositoryError.writeFailed) {
            _ = try await bundle.library.createDeck(named: "After fence")
        }
        try await coordinator.close()
    }

    @Test("Catalog rejects duplicate account fingerprints")
    func duplicateAccountFingerprintIsCorrupt() async throws {
        let root = temporaryRoot("catalog-duplicate-account")
        defer { try? FileManager.default.removeItem(at: root) }
        let stores = root.appendingPathComponent("Stores", isDirectory: true)
        try FileManager.default.createDirectory(at: stores, withIntermediateDirectories: true)
        let fingerprint = String(repeating: "a", count: 64)
        try Data(
            "{\"version\":1,\"accountFingerprints\":[\"\(fingerprint)\",\"\(fingerprint)\"],\"legacyMigrationIDs\":[]}".utf8
        ).write(to: stores.appendingPathComponent("catalog.json"))
        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: HardeningIdentityResolver(identity: .noAccount),
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 5, count: 32)),
            observeAccountChanges: false
        )
        await #expect(throws: AccountStoreRoutingError.catalogCorrupt) {
            _ = try await coordinator.open()
        }
    }

    @Test("Catalog rejects multiple active legacy migration IDs")
    func multipleLegacyIDsAreCorrupt() async throws {
        let root = temporaryRoot("catalog-multiple-legacy")
        defer { try? FileManager.default.removeItem(at: root) }
        let stores = root.appendingPathComponent("Stores", isDirectory: true)
        try FileManager.default.createDirectory(at: stores, withIntermediateDirectories: true)
        let first = UUID().uuidString.lowercased()
        let second = UUID().uuidString.lowercased()
        try Data(
            "{\"version\":1,\"accountFingerprints\":[],\"legacyMigrationIDs\":[\"\(first)\",\"\(second)\"]}".utf8
        ).write(to: stores.appendingPathComponent("catalog.json"))
        let coordinator = AccountStoreCoordinator(
            rootURL: root,
            containerIdentifier: "iCloud.test.flashup",
            resolver: HardeningIdentityResolver(identity: .noAccount),
            secretStore: InMemoryDeviceSecretStore(value: Data(repeating: 6, count: 32)),
            observeAccountChanges: false
        )
        await #expect(throws: AccountStoreRoutingError.catalogCorrupt) {
            _ = try await coordinator.open()
        }
    }

#if canImport(Security)
    @Test("Keychain duplicate-add race rereads the winning secret")
    func keychainDuplicateAddRereadsWinner() throws {
        let winner = Data(repeating: 9, count: 32)
        let reads = LockedReadSequence([nil, winner])
        let store = KeychainDeviceSecretStore(operations: KeychainDeviceSecretOperations(
            read: { reads.next() },
            random: { Data(repeating: 3, count: 32) },
            add: { _ in .duplicate }
        ))
        #expect(try store.createIfMissing() == winner)
    }

    @Test("Keychain malformed values and unavailable operations fail closed")
    func keychainFailuresAreTyped() throws {
        let malformed = KeychainDeviceSecretStore(operations: KeychainDeviceSecretOperations(
            read: { Data(repeating: 1, count: 31) },
            random: { Data(repeating: 2, count: 32) },
            add: { _ in .added }
        ))
        #expect(throws: AccountStoreRoutingError.keychainUnavailable) {
            _ = try malformed.read()
        }

        let inaccessible = KeychainDeviceSecretStore(operations: KeychainDeviceSecretOperations(
            read: { throw AccountStoreRoutingError.keychainUnavailable },
            random: { Data(repeating: 2, count: 32) },
            add: { _ in .added }
        ))
        #expect(throws: AccountStoreRoutingError.keychainUnavailable) {
            _ = try inaccessible.createIfMissing()
        }
    }
#endif

    private func temporaryRoot(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-account-routing-hardening-\(suffix)", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class LockedReadSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data?]
    init(_ values: [Data?]) { self.values = values }
    func next() -> Data? {
        lock.withLock {
            guard !values.isEmpty else { return nil }
            return values.removeFirst()
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
