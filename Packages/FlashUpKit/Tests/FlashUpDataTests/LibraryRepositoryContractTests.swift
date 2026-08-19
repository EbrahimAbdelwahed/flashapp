import Foundation
import Testing
@testable import FlashUpData
import FlashUpDomain

/// The same observable contract is exercised against the preview and persistent adapters.
/// Keeping the scenario here prevents a new Core Data path from being validated only by a
/// relaunch smoke test.
@Suite("Library repository contract", .serialized)
struct LibraryRepositoryContractTests {
    @Test("In-memory repository covers content, trash, import, settings and sessions")
    func inMemoryContract() async throws {
        let library = InMemoryLibrary(seeded: false)
        try await exerciseContract(library)
    }

    @Test("Core Data repository covers content, trash, import, settings and sessions")
    func coreDataContract() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-contract", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try PersistenceController(
            configuration: .onDisk(storeURL: root.appendingPathComponent("Private.sqlite"))
        )
        let library = CoreDataLibraryRepository(persistenceController: controller)
        try await exerciseContract(library)
        try controller.close()
    }

    private func exerciseContract(_ library: any LibraryRepository) async throws {
        #expect(await library.repositoryState() == .ready)
        let deck = try await library.createDeck(named: "Contract deck")
        #expect((try await library.decks()).contains { $0.deck.id == deck.id })

        let note = try #require(try await library.saveNote(NoteDraft(
            deckID: deck.id, type: .basic, front: "front", back: "back", tags: [" Tag "]
        )))
        let cards = try await library.cards(for: note.id)
        #expect(cards.count == 1)
        #expect((try await library.note(note.id))?.tags == ["Tag"])

        let edited = try #require(try await library.saveNote(NoteDraft(
            id: note.id, deckID: deck.id, type: .basic, front: "edited", back: "back", tags: ["Tag"]
        )))
        #expect(try await library.cards(for: edited.id).map(\.id) == cards.map(\.id))

        try await exerciseStudy(library, cardID: cards[0].id, noteID: note.id)
        try await exerciseSettingsAndSession(library, deckID: deck.id, cardIDs: cards.map(\.id))
        try await exerciseImportTrashAndBackup(library, deckID: deck.id, noteID: note.id)
        try await library.deleteAllData()
        #expect(try await library.decks().isEmpty)
        #expect(try await library.storedSession() == nil)
    }

    private func exerciseStudy(
        _ library: any LibraryRepository,
        cardID: UUID,
        noteID: UUID
    ) async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let transition = try SwiftFSRSAdapter().next(
            .unseen(dueAt: now), grade: .good, at: now
        )
        try await library.record(transition, for: cardID, durationMs: 1_000)
        #expect(try await library.cardInfo(cardID)?.logs.count == 1)
        try await library.revokeLastAnswer(in: .allDecks)
        #expect(try await library.cardInfo(cardID)?.logs.isEmpty == true)

        try await library.setSuspended(true, cardIDs: [cardID])
        #expect(try await library.schedule(for: cardID)?.isSuspended == true)
        try await library.resumeNote(noteID)
        // Resuming an unseen card removes its flag-only placeholder; absence is the
        // canonical representation of an unseen, unflagged card in both adapters.
        #expect(try await library.schedule(for: cardID) == nil)
        try await library.setBuried(true, cardIDs: [cardID], until: now.addingTimeInterval(3_600))
        #expect(try await library.schedule(for: cardID)?.buriedUntil != nil)
        try await library.resetCard(cardID)
        #expect(try await library.cardInfo(cardID)?.logs.isEmpty == true)
    }

    private func exerciseSettingsAndSession(
        _ library: any LibraryRepository,
        deckID: UUID,
        cardIDs: [UUID]
    ) async throws {
        var settings = StudySettings.default
        settings.newPerDay = 37
        try await library.updateSettings(settings)
        #expect(try await library.settings() == settings)

        let session = SessionState(
            scope: .deck(deckID), remainingCardIDs: cardIDs, answeredCount: 0,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await library.storeSession(session)
        #expect(try await library.storedSession() == session)
    }

    private func exerciseImportTrashAndBackup(
        _ library: any LibraryRepository,
        deckID: UUID,
        noteID: UUID
    ) async throws {
        let row = ParsedRow(line: 2, type: .basic, front: "imported", back: "answer", tags: ["import"])
        let batch = try await library.commitImport(
            ImportPlan(valid: [row]), into: deckID, sourceName: "contract.csv", wasNewDeck: false
        )
        #expect(batch.createdNoteIDs.count == 1)
        try await library.undoImport(batch.id)
        #expect((try await library.trashedNotes()).contains { batch.createdNoteIDs.contains($0.id) })

        try await library.trashNote(noteID)
        #expect(try await library.note(noteID) == nil)
        try await library.restoreNote(noteID)
        #expect(try await library.note(noteID)?.id == noteID)

        let backup = try await library.backupDocument(appVersion: "contract", now: Date())
        #expect(backup.decks.contains { $0.uuid == deckID })
        try await library.emptyTrash()
        #expect(try await library.trashedNotes().isEmpty)
    }
}
