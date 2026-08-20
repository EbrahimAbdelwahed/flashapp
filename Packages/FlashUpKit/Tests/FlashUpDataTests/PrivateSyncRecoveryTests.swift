import Foundation
import FlashUpDomain
import Testing
@testable import FlashUpData

@Suite("Private sync recovery", .serialized)
struct PrivateSyncRecoveryTests {
    @Test("No-account authoring survives availability and keeps the same private store")
    func noAccountAuthoringBecomesExportEligible() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-private-sync-fixture", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = root.appendingPathComponent("Private.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let monitor = SyncMonitor(
            initialAccountState: .noAccount,
            accountStatusProvider: { .available }
        )
        let controller = try PersistenceController(configuration: .onDisk(storeURL: storeURL))
        let library = CoreDataLibraryRepository(
            persistenceController: controller,
            syncMonitor: monitor
        )
        let deck = try await library.createDeck(named: "Offline authored")
        #expect(try await library.syncStatus() == .accountUnavailable)

        try await library.retrySync()

        let status = try await library.syncStatus()
        guard case .syncing = status else {
            Issue.record("A newly available private store did not report an in-progress sync")
            try controller.close()
            return
        }
        #expect(controller.configuration.storeURL == storeURL)
        let backup = try await library.backupDocument(
            appVersion: "1.0",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(backup.decks.contains { $0.uuid == deck.id && $0.name == "Offline authored" })
        #expect(try await library.deck(deck.id)?.name == "Offline authored")
        try controller.close()
    }

    @Test("A history-processing failure does not block local authoring or study reads")
    func syncFailureDoesNotPoisonLocalRepository() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-sync-failure-local", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try PersistenceController(
            configuration: .onDisk(storeURL: root.appendingPathComponent("Private.sqlite"))
        )
        try Data([0xFF]).write(to: controller.historyTokenURL, options: [.atomic])
        let monitor = SyncMonitor(
            initialAccountState: .available,
            accountStatusProvider: { .available }
        )
        let library = CoreDataLibraryRepository(
            persistenceController: controller,
            syncMonitor: monitor
        )
        let deck = try await library.createDeck(named: "Offline deck")

        await #expect(throws: LibraryRepositoryError.writeFailed) {
            try await library.retrySync()
        }
        let status = try await library.syncStatus()
        guard case .failed = status else {
            Issue.record("A failed retry did not preserve a failed sync status")
            try controller.close()
            return
        }
        await #expect(throws: RemoteChangeProcessorError.historyReadFailed) {
            _ = try await library.refreshRemoteChanges()
        }
        #expect(try await library.deck(deck.id)?.name == "Offline deck")
        #expect((try await library.studyQueue(scope: .allDecks, now: Date())).isEmpty)
        try controller.close()
    }
}
