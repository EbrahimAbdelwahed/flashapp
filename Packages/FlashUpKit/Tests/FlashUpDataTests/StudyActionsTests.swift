import FlashUpDomain
import Foundation
import Testing
@testable import FlashUpData

/// The card actions the reviewer offers (spec §A6.3): suspension, burial, reset, and the
/// read the card info screen depends on.
///
/// The point most of these guard is the same: suspension and burial are user choices, not
/// scheduling outcomes, so they have to survive every path that rewrites a schedule.
@Suite("Study card actions")
struct StudyActionsTests {
    private func emptyLibrary() -> InMemoryLibrary {
        InMemoryLibrary(seeded: false)
    }

    @Test("A suspended card leaves the queue and the counts")
    func suspendedCardsAreExcluded() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        let note = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "A", back: "B"))
        )
        let cardID = try #require(await library.cards(for: note.id).first?.id)

        await library.setSuspended(true, cardIDs: [cardID])

        #expect(await library.studyQueue(scope: .allDecks, now: Date()).isEmpty)
        #expect(await library.todaySnapshot(now: Date()).newCount == 0)

        await library.setSuspended(false, cardIDs: [cardID])

        #expect(await library.studyQueue(scope: .allDecks, now: Date()).count == 1)
        // Un-suspending a card that was never studied must not leave it looking seen.
        #expect(await library.schedule(for: cardID) == nil)
    }

    @Test("Burying a note takes its siblings out of today's queue and lets them back in")
    func buryingHidesSiblingsUntilTheDatePasses() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        let note = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .reversed, front: "A", back: "B"))
        )
        let cardIDs = await library.cards(for: note.id).map(\.id)
        #expect(cardIDs.count == 2)

        let now = Date()
        let tomorrow = now.addingTimeInterval(86_400)
        await library.setBuried(true, cardIDs: cardIDs, until: tomorrow)

        #expect(await library.studyQueue(scope: .allDecks, now: now).isEmpty)
        #expect(await library.todaySnapshot(now: now).newCount == 0)

        // Nothing has to unbury them: the queue re-reads the date.
        #expect(await library.studyQueue(scope: .allDecks, now: tomorrow.addingTimeInterval(60)).count == 2)
    }

    @Test("Burial survives an answer and the undo that replays it")
    func burialSurvivesRecordAndReplay() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        let note = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "A", back: "B"))
        )
        let cardID = try #require(await library.cards(for: note.id).first?.id)
        let until = Date().addingTimeInterval(86_400)
        await library.setBuried(true, cardIDs: [cardID], until: until)

        let transition = try SwiftFSRSAdapter().next(.unseen(dueAt: Date()), grade: .good, at: Date())
        await library.record(transition, for: cardID, durationMs: 900)
        #expect(await library.schedule(for: cardID)?.buriedUntil == until)

        await library.revokeLastAnswer(in: .allDecks)
        #expect(await library.schedule(for: cardID)?.buriedUntil == until)
    }

    /// The way back out of a suspension: find them with the filter, lift them with one
    /// action. Without this the reviewer's Suspend was a one-way door.
    @Test("The Suspended and Buried filters find hidden notes, and resuming clears both")
    func hiddenNotesCanBeFoundAndResumed() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        let suspendedNote = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .reversed, front: "A", back: "B"))
        )
        let buriedNote = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "C", back: "D"))
        )
        let now = Date()

        // Only one of the reversed note's two cards is suspended: the filter and the badge
        // must both still find it, or the note would be unreachable.
        let oneSibling = try #require(await library.cards(for: suspendedNote.id).first?.id)
        await library.setSuspended(true, cardIDs: [oneSibling])
        await library.setBuried(
            true,
            cardIDs: await library.cards(for: buriedNote.id).map(\.id),
            until: now.addingTimeInterval(86_400)
        )

        func notes(_ state: SearchFilters.State) async -> [NoteSummary] {
            await library.notes(in: deck.id, filters: SearchFilters(state: state), now: now)
        }

        let suspended = await notes(.suspended)
        #expect(suspended.map(\.note.id) == [suspendedNote.id])
        #expect(suspended.first?.isSuspended == true)

        let buried = await notes(.buried)
        #expect(buried.map(\.note.id) == [buriedNote.id])
        #expect(buried.first?.isBuried == true)

        await library.resumeNote(suspendedNote.id)
        await library.resumeNote(buriedNote.id)

        #expect(await notes(.suspended).isEmpty)
        #expect(await notes(.buried).isEmpty)
        #expect(await library.studyQueue(scope: .deck(deck.id), now: now).count == 3)
    }

    @Test("Card info reports the surviving history, newest first")
    func cardInfoExcludesRevokedLogs() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        let note = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "A", back: "B"))
        )
        let cardID = try #require(await library.cards(for: note.id).first?.id)
        let scheduler = SwiftFSRSAdapter()

        let first = Date()
        let firstTransition = try scheduler.next(.unseen(dueAt: first), grade: .good, at: first)
        await library.record(firstTransition, for: cardID, durationMs: 900)

        let second = first.addingTimeInterval(60)
        let secondTransition = try scheduler.next(firstTransition.updated, grade: .again, at: second)
        await library.record(secondTransition, for: cardID, durationMs: 400)

        let info = try #require(await library.cardInfo(cardID))
        #expect(info.logs.count == 2)
        #expect(info.logs.first?.grade == .again)
        #expect(info.isNew == false)

        await library.revokeLastAnswer(in: .allDecks)

        let afterUndo = try #require(await library.cardInfo(cardID))
        #expect(afterUndo.logs.count == 1)
        #expect(afterUndo.logs.first?.grade == .good)
    }

    @Test("Resetting a card sends it back to new and revokes its history")
    func resettingACardClearsProgress() async throws {
        let library = emptyLibrary()
        let deck = await library.createDeck(named: "Test")
        let note = try #require(
            await library.saveNote(NoteDraft(deckID: deck.id, type: .basic, front: "A", back: "B"))
        )
        let cardID = try #require(await library.cards(for: note.id).first?.id)
        let transition = try SwiftFSRSAdapter().next(.unseen(dueAt: Date()), grade: .good, at: Date())
        await library.record(transition, for: cardID, durationMs: 900)

        await library.resetCard(cardID)

        #expect(await library.schedule(for: cardID) == nil)
        #expect(await library.metrics(now: Date()).studiedToday == 0)
    }
}
