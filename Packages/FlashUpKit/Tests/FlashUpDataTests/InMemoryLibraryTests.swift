import FlashUpDomain
import Foundation
import Testing
@testable import FlashUpData

/// Bead fu-04b: the preview repository has to behave like the real one, or the interface is
/// being designed against a lie.
@Suite("In-memory library")
struct InMemoryLibraryTests {
    @Test("A seeded library exposes decks with cards")
    func seededLibraryHasContent() async {
        let library = InMemoryLibrary()

        let decks = await library.decks()

        #expect(decks.count == 3)
        #expect(decks.allSatisfy { $0.totalCards > 0 })
    }

    @Test("An unseeded library is empty, so empty states can be designed")
    func unseededLibraryIsEmpty() async {
        let library = InMemoryLibrary(seeded: false)

        let snapshot = await library.todaySnapshot(now: Date())

        #expect(snapshot.decks.isEmpty)
        #expect(snapshot.hasWorkToDo == false)
    }

    @Test("The queue puts due cards before never-seen ones")
    func queueOrdersDueBeforeNew() async {
        let library = InMemoryLibrary()
        let now = Date()

        let queue = await library.studyQueue(scope: .allDecks, now: now)

        var seenNew = false
        for card in queue {
            let isNew = await library.schedule(for: card.id) == nil
            if isNew { seenNew = true } else { #expect(!seenNew, "a due card followed a new one") }
        }
        #expect(!queue.isEmpty)
    }

    @Test("A deck scope only returns that deck's cards")
    func deckScopeIsRespected() async {
        let library = InMemoryLibrary()
        guard let deck = await library.decks().first else {
            Issue.record("seeded library had no decks")
            return
        }

        let queue = await library.studyQueue(scope: .deck(deck.deck.id), now: Date())

        #expect(!queue.isEmpty)
        #expect(queue.allSatisfy { $0.deckID == deck.deck.id })
    }

    @Test("Answering a card records it and updates the snapshot")
    func answeringUpdatesState() async throws {
        let library = InMemoryLibrary()
        let scheduler = SwiftFSRSAdapter()
        let now = Date()
        let card = try #require(await library.studyQueue(scope: .allDecks, now: now).first)
        let before = await library.schedule(for: card.id) ?? .unseen(dueAt: now)

        let transition = try scheduler.next(before, grade: .good, at: now)
        await library.record(transition, for: card.id, durationMs: 1_100)

        let after = await library.schedule(for: card.id)
        #expect(after == transition.updated)
        #expect(await library.todaySnapshot(now: now).metrics.studiedToday == 1)
    }

    @Test("Undo restores the state the card had before the answer")
    func undoRestoresPreviousState() async throws {
        let library = InMemoryLibrary()
        let scheduler = SwiftFSRSAdapter()
        let now = Date()
        let card = try #require(await library.studyQueue(scope: .allDecks, now: now).first)
        let before = await library.schedule(for: card.id)

        let transition = try scheduler.next(before ?? .unseen(dueAt: now), grade: .again, at: now)
        await library.record(transition, for: card.id, durationMs: 1_100)
        await library.revokeLastAnswer(in: .allDecks)

        #expect(await library.schedule(for: card.id) == before)
        #expect(await library.todaySnapshot(now: now).metrics.studiedToday == 0)
    }
}
