import CoreData
import Foundation
import Testing
@testable import FlashUpData
import FlashUpDomain

@Suite("Persistent library", .serialized)
struct CoreDataLibraryRepositoryTests {
    @Test("Decks, notes and settings survive a repository relaunch")
    func relaunchPreservesLibrary() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-library-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = root.appendingPathComponent("Private.sqlite")
        let sessionURL = root.appendingPathComponent("session-state.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let deckID: UUID
        let noteID: UUID
        let cardID: UUID
        let buriedUntil = Date(timeIntervalSince1970: 1_800_000_000)
        do {
            let controller = try PersistenceController(configuration: .onDisk(storeURL: storeURL))
            let library = CoreDataLibraryRepository(
                persistenceController: controller,
                sessionURL: sessionURL
            )
            let deck = try await library.createDeck(named: "Persistent deck")
            deckID = deck.id
            let note = try #require(try await library.saveNote(NoteDraft(
                deckID: deck.id,
                type: .basic,
                front: "front",
                back: "back",
                tags: [" Tag "]
            )))
            noteID = note.id
            cardID = try #require((try await library.cards(for: note.id)).first?.id)
            try await library.setBuried(true, cardIDs: [cardID], until: buriedUntil)
            var settings = StudySettings.default
            settings.newPerDay = 42
            try await library.updateSettings(settings)
            try await library.storeSession(SessionState(
                scope: .deck(deck.id),
                remainingCardIDs: [],
                answeredCount: 0,
                startedAt: Date(timeIntervalSince1970: 100)
            ))
            try controller.close()
        }

        let reopenedController = try PersistenceController(configuration: .onDisk(storeURL: storeURL))
        let reopened = CoreDataLibraryRepository(
            persistenceController: reopenedController,
            sessionURL: sessionURL
        )
        #expect(try await reopened.deck(deckID)?.name == "Persistent deck")
        #expect(try await reopened.note(noteID)?.tags == ["Tag"])
        #expect(try await reopened.settings().newPerDay == 42)
        #expect(try await reopened.storedSession()?.scope == .deck(deckID))
        #expect(try await reopened.schedule(for: cardID)?.buriedUntil == buriedUntil)
        try reopenedController.close()
    }

    @Test("Demo installation is idempotent and remains persistent")
    func demoInstallationIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-demo-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = root.appendingPathComponent("Private.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = try PersistenceController(configuration: .onDisk(storeURL: storeURL))
        let library = CoreDataLibraryRepository(persistenceController: controller)
        try await library.installDemoDeck()
        try await library.installDemoDeck()
        let installed = try #require((try await library.decks()).first(where: { $0.deck.isDemo }))
        #expect(installed.deck.demoSeedID == DemoContent.seedID)
        #expect(installed.deck.demoVersion == DemoContent.version)
        let demoID = installed.deck.id
        try controller.performBackgroundTask { context in
            let demo = try #require(try context.fetch(CDDeck.fetchRequest()).first(where: { $0.isDemo }))
            demo.demoVersion = 0
        }
        try await library.installDemoDeck()
        let upgraded = try #require((try await library.decks()).first(where: { $0.deck.isDemo }))
        #expect(upgraded.deck.id == demoID)
        #expect(upgraded.deck.demoVersion == DemoContent.version)
        #expect((try await library.decks()).filter(\.deck.isDemo).count == 1)
        try controller.close()

        let reopenedController = try PersistenceController(configuration: .onDisk(storeURL: storeURL))
        let reopened = CoreDataLibraryRepository(persistenceController: reopenedController)
        #expect((try await reopened.decks()).filter(\.deck.isDemo).count == 1)
        #expect((try await reopened.decks()).first(where: { $0.deck.isDemo })?.deck.demoSeedID == DemoContent.seedID)
        try reopenedController.close()
    }

    @Test("Same UUID edit/edit, edit/delete and restore/delete races preserve valid state")
    func sameUUIDRacesAreNonDestructive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-same-uuid-races", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try PersistenceController(
            configuration: .onDisk(storeURL: root.appendingPathComponent("Private.sqlite"))
        )
        let first = CoreDataLibraryRepository(persistenceController: controller)
        let second = CoreDataLibraryRepository(persistenceController: controller)
        let deck = try await first.createDeck(named: "Race deck")
        let noteID = UUID()
        _ = try #require(try await first.saveNote(NoteDraft(
            id: noteID, deckID: deck.id, type: .basic, front: "base", back: "answer"
        )))

        async let edit = first.saveNote(NoteDraft(
            id: noteID, deckID: deck.id, type: .basic, front: "edited", back: "answer"
        ))
        async let delete = second.trashNote(noteID)
        _ = try await (edit, delete)

        async let restore = first.restoreNote(noteID)
        async let deleteAgain = second.trashNote(noteID)
        _ = try await (restore, deleteAgain)

        let verifier = CoreDataLibraryRepository(persistenceController: controller)
        let live = try await verifier.note(noteID)
        let trash = try await verifier.trashedNotes()
        #expect(live?.id == noteID || trash.contains(where: { $0.id == noteID }))
        #expect(live?.front == "edited" || trash.first(where: { $0.id == noteID })?.front == "edited")
        try controller.close()
    }

    @Test("A save conflict retries from a fresh context and preserves the operation winner")
    func saveConflictRetriesFromFreshContext() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-save-conflict", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("Private.sqlite")
        let controller = try PersistenceController(configuration: .onDisk(storeURL: storeURL))
        let library = CoreDataLibraryRepository(persistenceController: controller)
        let deck = try await library.createDeck(named: "Conflict deck")
        let noteID = UUID()
        _ = try #require(try await library.saveNote(NoteDraft(
            id: noteID, deckID: deck.id, type: .basic, front: "base", back: "answer"
        )))

        var injected = false
        controller.saveConflictHook = { attempt in
            guard attempt == 1, !injected else { return }
            injected = true
            let context = controller.container.newBackgroundContext()
            context.mergePolicy = NSErrorMergePolicy
            var saveError: Error?
            context.performAndWait {
                do {
                    let request = CDNote.fetchRequest()
                    request.predicate = NSPredicate(format: "uuid == %@", noteID as CVarArg)
                    let note = try context.fetch(request).first
                    note?.front = "remote-winner"
                    try context.save()
                } catch {
                    saveError = error
                }
            }
            if let saveError { throw saveError }
        }
        defer { controller.saveConflictHook = nil }

        _ = try #require(try await library.saveNote(NoteDraft(
            id: noteID, deckID: deck.id, type: .basic, front: "local-winner", back: "answer"
        )))

        #expect(controller.saveConflictAttemptCount == 2)
        #expect(try await library.note(noteID)?.front == "local-winner")
        try controller.close()
    }

    @Test("Session state is atomic device-local JSON, independent of Core Data")
    func sessionFileIsSeparate() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-session-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = root.appendingPathComponent("Private.sqlite")
        let sessionURL = root.appendingPathComponent("session-state.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = try PersistenceController(configuration: .onDisk(storeURL: storeURL))
        let library = CoreDataLibraryRepository(persistenceController: controller, sessionURL: sessionURL)
        let state = SessionState(
            scope: .allDecks,
            remainingCardIDs: [UUID()],
            answeredCount: 1,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await library.storeSession(state)
        #expect(FileManager.default.fileExists(atPath: sessionURL.path))
        #expect(try await library.storedSession() == state)
        try await library.storeSession(nil)
        #expect(FileManager.default.fileExists(atPath: sessionURL.path) == false)
        try controller.close()
    }

    @Test("Concurrent repository actors preserve unrelated writes")
    func concurrentActorsDoNotClobberRows() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-concurrency-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = root.appendingPathComponent("Private.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = try PersistenceController(configuration: .onDisk(storeURL: storeURL))
        let first = CoreDataLibraryRepository(persistenceController: controller)
        let second = CoreDataLibraryRepository(persistenceController: controller)
        async let firstDeck = try first.createDeck(named: "First actor")
        async let secondDeck = try second.createDeck(named: "Second actor")
        _ = try await (firstDeck, secondDeck)

        let verifier = CoreDataLibraryRepository(persistenceController: controller)
        let names = Set((try await verifier.decks()).map(\.deck.name))
        #expect(names == ["First actor", "Second actor"])
        try controller.close()
    }

    @Test("A closed store reports a typed read failure instead of an empty success")
    func closedStoreReportsFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-failure-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try PersistenceController(
            configuration: .onDisk(storeURL: root.appendingPathComponent("Private.sqlite"))
        )
        let library = CoreDataLibraryRepository(persistenceController: controller)
        _ = try await library.createDeck(named: "Before close")
        try controller.close()

        await #expect(throws: LibraryRepositoryError.readFailed) {
            _ = try await library.decks()
        }
        #expect(await library.repositoryState() == .failed(.readFailed))
    }

    @Test("Malformed persisted rows remain untouched and publish a typed mapping failure")
    func malformedRowIsNonDestructive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-malformed-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try PersistenceController(
            configuration: .onDisk(storeURL: root.appendingPathComponent("Private.sqlite"))
        )
        let malformedID = UUID()
        try controller.performBackgroundTask { context in
            let object = try #require(
                NSEntityDescription.insertNewObject(forEntityName: "CDNote", into: context) as? CDNote
            )
            object.uuid = malformedID
            object.front = "forward row"
            object.back = "answer"
            object.type = NoteType.basic.rawValue
            object.tagsJSON = "[]"
            object.mediaIDsJSON = "[]"
            object.contentHash = "hash"
            // A note without a deck is a malformed/forward row, not an instruction to erase it.
        }
        let library = CoreDataLibraryRepository(persistenceController: controller)
        await #expect(throws: LibraryRepositoryError.malformedPersistedData) {
            _ = try await library.note(malformedID)
        }
        #expect(await library.repositoryState() == .failed(.malformedPersistedData))
        let persisted = try controller.performBackgroundTask { context in
            try context.fetch(CDNote.fetchRequest()).contains { $0.uuid == malformedID }
        }
        #expect(persisted)
        try controller.close()
    }
}
