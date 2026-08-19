import Foundation
import Testing
@testable import FlashUpData
import FlashUpDomain

@Suite("Persistent backup restore", .serialized)
struct CoreDataBackupRestoreTests {
    private struct Fixture {
        let document: BackupDocument
        let noteID: UUID
        let sourceInfo: CardInfo
    }

    @Test("Backup restore maps generated cards and preserves progress after relaunch")
    func backupRestorePreservesProgressAfterRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-backup-restore-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try await makeFixture(root: root)
        let targetURL = root.appendingPathComponent("target/Private.sqlite")
        let targetController = try PersistenceController(configuration: .onDisk(storeURL: targetURL))
        let target = CoreDataLibraryRepository(persistenceController: targetController)
        let summary = try await target.restore(fixture.document)
        #expect(summary.decksAdded == 1)
        #expect(summary.notesAdded == 1)
        #expect(summary.logsAdded == 1)

        let restoredCardID = try await cardID(in: target, noteID: fixture.noteID)
        #expect(restoredCardID != fixture.sourceInfo.card.id)
        let targetInfo = try #require(try await target.cardInfo(restoredCardID))
        assertProgress(targetInfo, matches: fixture.sourceInfo)
        try targetController.close()

        let reopenedController = try PersistenceController(configuration: .onDisk(storeURL: targetURL))
        let reopened = CoreDataLibraryRepository(persistenceController: reopenedController)
        let reopenedCardID = try await cardID(in: reopened, noteID: fixture.noteID)
        #expect(reopenedCardID == restoredCardID)
        let reopenedInfo = try #require(try await reopened.cardInfo(reopenedCardID))
        assertProgress(reopenedInfo, matches: targetInfo)
        try reopenedController.close()
    }

    private func makeFixture(root: URL) async throws -> Fixture {
        let sourceURL = root.appendingPathComponent("source/Private.sqlite")
        let sourceController = try PersistenceController(configuration: .onDisk(storeURL: sourceURL))
        let source = CoreDataLibraryRepository(persistenceController: sourceController)
        let deck = try await source.createDeck(named: "Backup source")
        let note = try #require(try await source.saveNote(NoteDraft(
            deckID: deck.id,
            type: .basic,
            front: "backup front",
            back: "backup back"
        )))
        let cardID = try #require((try await source.cards(for: note.id)).first?.id)
        let transition = try SwiftFSRSAdapter().next(
            .unseen(dueAt: Date(timeIntervalSince1970: 1_700_000_000)),
            grade: .good,
            at: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try await source.record(transition, for: cardID, durationMs: 1_200)
        let info = try #require(try await source.cardInfo(cardID))
        let document = try await source.backupDocument(
            appVersion: "test",
            now: Date(timeIntervalSince1970: 1_700_000_200)
        )
        try sourceController.close()
        return Fixture(document: document, noteID: note.id, sourceInfo: info)
    }

    private func cardID(in library: CoreDataLibraryRepository, noteID: UUID) async throws -> UUID {
        try #require((try await library.cards(for: noteID)).first?.id)
    }

    private func assertProgress(_ actual: CardInfo, matches expected: CardInfo) {
        #expect(actual.schedule == expected.schedule)
        #expect(actual.logs.map(\.previous) == expected.logs.map(\.previous))
        #expect(actual.logs.map(\.grade) == expected.logs.map(\.grade))
        #expect(actual.logs.map(\.durationMs) == expected.logs.map(\.durationMs))
    }
}
