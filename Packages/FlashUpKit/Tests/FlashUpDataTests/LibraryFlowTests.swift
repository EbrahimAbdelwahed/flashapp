import FlashUpDomain
import Foundation
import Testing
@testable import FlashUpData

/// End-to-end behaviour of the repository: the flows the interface depends on.
@Suite("Library flows")
struct LibraryFlowTests {
    private func emptyLibrary() -> InMemoryLibrary {
        InMemoryLibrary(seeded: false)
    }

    // MARK: - Authoring

    @Test("Creating a note generates its cards")
    func creatingANoteGeneratesCards() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")

        let note = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .reversed, front: "Bone", back: "Osso"))
        )

        let cards = await library.cards(for: note.id)
        #expect(cards.map(\.templateKey) == ["forward", "reverse"])
    }

    @Test("An invalid draft is refused rather than saved half-formed")
    func invalidDraftIsRefused() async {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")

        let saved = await library.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "Solo fronte", back: ""))

        #expect(saved == nil)
    }

    @Test("Editing a note keeps the card identity, and therefore its progress")
    func editingPreservesCardIdentity() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        let note = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "Domanda", back: "Risposta"))
        )
        let cardID = try #require(await library.cards(for: note.id).first?.id)

        let scheduler = SwiftFSRSAdapter()
        let transition = try scheduler.next(.unseen(dueAt: Date()), grade: .good, at: Date())
        await library.record(transition, for: cardID, durationMs: 1000)

        var edited = NoteDraft(note: note)
        edited.front = "Domanda riformulata"
        _ = await library.saveNote(edited)

        #expect(await library.cards(for: note.id).first?.id == cardID)
        #expect(await library.schedule(for: cardID) != nil)
    }

    @Test("Removing a cloze group drops that card only")
    func removingAClozeGroupDropsItsCard() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        let note = try #require(
            await library.saveNote(
                NoteDraft(deckID: deck.id, type: .cloze, front: "{{c1::A}} e {{c2::B}}")
            )
        )
        #expect(await library.cards(for: note.id).count == 2)

        var edited = NoteDraft(note: note)
        edited.front = "{{c1::A}} e B"
        _ = await library.saveNote(edited)

        #expect(await library.cards(for: note.id).map(\.templateKey) == ["cloze:1"])
    }

    // MARK: - Trash

    @Test("A trashed note leaves the library and can be restored")
    func trashRoundTrip() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        let note = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "A", back: "B"))
        )

        await library.trashNote(note.id)
        #expect(await library.notes(in: deck.id, filters: SearchFilters(), now: Date()).isEmpty)
        #expect(await library.trashedNotes().count == 1)

        await library.restoreNote(note.id)
        #expect(await library.notes(in: deck.id, filters: SearchFilters(), now: Date()).count == 1)
    }

    @Test("Emptying the trash removes the note and its cards for good")
    func emptyingTrashIsFinal() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        let note = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "A", back: "B"))
        )

        await library.trashNote(note.id)
        await library.emptyTrash()

        #expect(await library.trashedNotes().isEmpty)
        #expect(await library.cards(for: note.id).isEmpty)
    }

    // MARK: - Search

    @Test("Search matches front, back and tags")
    func searchMatchesContentAndTags() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        _ = await library.saveNote(
            NoteDraft(deckID: deck.id, type: .basic, front: "Mitocondri", back: "ATP", tags: ["biologia"])
        )

        #expect(await library.search(SearchFilters(text: "mitoc"), now: Date()).count == 1)
        #expect(await library.search(SearchFilters(text: "atp"), now: Date()).count == 1)
        #expect(await library.search(SearchFilters(text: "biolog"), now: Date()).count == 1)
        #expect(await library.search(SearchFilters(text: "chimica"), now: Date()).isEmpty)
    }

    // MARK: - Studying

    @Test("Daily limits cap the queue")
    func dailyLimitsCapTheQueue() async {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        for index in 0..<10 {
            _ = await library.saveNote(
                NoteDraft(deckID: deck.id, type: .basic, front: "D\(index)", back: "R\(index)")
            )
        }

        var settings = StudySettings.default
        settings.newPerDay = 3
        await library.updateSettings(settings)

        #expect(await library.studyQueue(scope: .allDecks, now: Date()).count == 3)
    }

    @Test("A stored session survives and is offered back")
    func sessionStateRoundTrip() async {
        let library = emptyLibrary()
        let ids = [UUID(), UUID()]

        await library.storeSession(
            SessionState(scope: .allDecks, remainingCardIDs: ids, answeredCount: 3, startedAt: Date())
        )

        let stored = await library.storedSession()
        #expect(stored?.remainingCardIDs == ids)
        #expect(stored?.isResumable(at: Date()) == true)
    }

    // MARK: - Import and portability

    @Test("Importing creates notes, and undo sends them to the trash")
    func importThenUndo() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Import")
        let outcome = try CSVParser.parse(Data(ImportFixtures.csv.utf8))
        let plan = ImportPlanner.plan(outcome, existingHashes: [:])

        let batch = await library.commitImport(plan, into: deck.id, sourceName: "test.csv", wasNewDeck: true)
        #expect(batch.createdNoteIDs.count == 2)
        #expect(await library.notes(in: deck.id, filters: SearchFilters(), now: Date()).count == 2)

        await library.undoImport(batch.id)
        #expect(await library.notes(in: deck.id, filters: SearchFilters(), now: Date()).isEmpty)
        #expect(await library.trashedNotes().count == 2)
    }

    @Test("A second import of the same file is flagged as duplicate, not silently doubled")
    func reimportingIsFlaggedAsDuplicate() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Import")
        let outcome = try CSVParser.parse(Data(ImportFixtures.csv.utf8))
        _ = await library.commitImport(
            ImportPlanner.plan(outcome, existingHashes: [:]),
            into: deck.id,
            sourceName: "test.csv",
            wasNewDeck: true
        )

        let secondPlan = ImportPlanner.plan(outcome, existingHashes: await library.contentHashes(in: deck.id))

        #expect(secondPlan.valid.isEmpty)
        #expect(secondPlan.duplicates.count == 2)
        #expect(secondPlan.rowsToImport.isEmpty)
    }

    @Test("Exported CSV re-imports to the same content")
    func csvRoundTrip() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Round trip")
        _ = await library.saveNote(
            NoteDraft(deckID: deck.id, type: .basic, front: "Con, virgola", back: "E \"virgolette\"", tags: ["a", "b"])
        )

        let data = await library.exportCSV(deckID: deck.id)
        let outcome = try CSVParser.parse(data)

        #expect(outcome.rejected.isEmpty)
        #expect(outcome.rows.first?.front == "Con, virgola")
        #expect(outcome.rows.first?.back == "E \"virgolette\"")
        #expect(outcome.rows.first?.tags == ["a", "b"])
    }

    @Test("A backup restores into an empty library with its progress intact")
    func backupRoundTrip() async throws {
        let source = emptyLibrary()
        let deck = await source.createDeck(named: "Backup")
        let note = try #require(
            await source.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "A", back: "B"))
        )
        let cardID = try #require(await source.cards(for: note.id).first?.id)
        let transition = try SwiftFSRSAdapter().next(.unseen(dueAt: Date()), grade: .good, at: Date())
        await source.record(transition, for: cardID, durationMs: 1200)

        let data = try BackupCodec.encode(await source.backupDocument(appVersion: "1.0 (1)", now: Date()))
        let restored = emptyLibrary()
        let summary = await restored.restore(try BackupCodec.decode(data))

        #expect(summary.decksAdded == 1)
        #expect(summary.notesAdded == 1)
        #expect(summary.logsAdded == 1)
        #expect(await restored.schedule(for: cardID) != nil)
    }

    @Test("Restoring twice adds nothing and never overwrites live data")
    func restoringTwiceIsSafe() async throws {
        let source = emptyLibrary()
        let deck = await source.createDeck(named: "Backup")
        _ = await source.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "A", back: "B"))
        let document = await source.backupDocument(appVersion: "1.0 (1)", now: Date())

        let target = emptyLibrary()
        _ = await target.restore(document)
        let second = await target.restore(document)

        #expect(second.notesAdded == 0)
        #expect(second.notesSkipped == 1)
    }

    @Test("A backup from a newer format version is refused")
    func newerBackupIsRefused() throws {
        let document = BackupDocument(
            formatVersion: BackupDocument.currentVersion + 1,
            appVersion: "9.0",
            exportedAt: Date(),
            settings: .default,
            decks: [],
            schedules: [],
            reviewLogs: []
        )
        let data = try BackupCodec.encode(document)

        #expect(throws: BackupError.unsupportedVersion(
            found: BackupDocument.currentVersion + 1,
            supported: BackupDocument.currentVersion
        )) {
            _ = try BackupCodec.decode(data)
        }
    }

    @Test("Erasing all data leaves nothing behind")
    func deleteAllDataClearsEverything() async {
        let library = InMemoryLibrary()
        #expect(await library.decks().isEmpty == false)

        await library.deleteAllData()

        #expect(await library.decks().isEmpty)
        #expect(await library.todaySnapshot(now: Date()).hasWorkToDo == false)
    }
}

enum ImportFixtures {
    static let csv = """
    type,front,back,tags
    basic,Domanda uno,Risposta uno,tag
    cloze,Il {{c1::cuore}} pompa,,anatomia
    """
}
