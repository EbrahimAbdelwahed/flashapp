import FlashUpDomain
import Foundation

/// The studying half of `InMemoryLibrary`: the queue, the answers, and the two ways a user
/// takes a card out of a queue (spec §A6.3).
///
/// Split out so the actor stays readable; the scheduling rules themselves live in
/// `QueueBuilder` and `LibraryStore`, which are pure and testable without an actor.
extension InMemoryLibrary {
    public func studyQueue(scope: StudyScope, now: Date) async -> [Card] {
        QueueBuilder.build(
            candidates: store.candidates(in: scope),
            settings: store.settings,
            progress: store.progress(in: scope, now: now),
            now: now
        )
    }

    public func cards(withIDs ids: [UUID]) async -> [Card] {
        ids.compactMap { store.cards[$0] }
    }

    public func schedule(for cardID: UUID) async -> ReviewState? {
        store.schedules[cardID]
    }

    public func record(_ transition: ScheduleTransition, for cardID: UUID, durationMs: Int) async {
        store.record(transition, for: cardID, durationMs: durationMs)
    }

    public func revokeLastAnswer(in scope: StudyScope) async {
        store.revokeLastAnswer(in: scope, using: scheduler, now: Date())
    }

    public func setSuspended(_ suspended: Bool, cardIDs: [UUID]) async {
        let now = Date()
        for cardID in cardIDs {
            setFlag(on: cardID, now: now) { $0.suspendedAt = suspended ? now : nil }
        }
    }

    public func setBuried(_ buried: Bool, cardIDs: [UUID], until: Date) async {
        let now = Date()
        for cardID in cardIDs {
            setFlag(on: cardID, now: now) { $0.buriedUntil = buried ? until : nil }
        }
    }

    /// Applies a user flag to a card's schedule, creating one if the card has never been
    /// studied — a new card can be suspended or buried just like any other. The schedule is
    /// dropped again when it ends up carrying no flag and no history, so hiding and then
    /// un-hiding a new card leaves no trace that would make it look seen.
    private func setFlag(on cardID: UUID, now: Date, _ change: (inout ReviewState) -> Void) {
        var state = store.schedules[cardID] ?? .unseen(dueAt: now)
        change(&state)

        if !state.carriesUserFlag, state.isUnseen {
            store.schedules.removeValue(forKey: cardID)
        } else {
            store.schedules[cardID] = state
        }
    }

    public func resumeNote(_ noteID: UUID) async {
        let now = Date()
        for card in store.cards(forNote: noteID) {
            setFlag(on: card.id, now: now) {
                $0.suspendedAt = nil
                $0.buriedUntil = nil
            }
        }
    }

    public func resetCard(_ cardID: UUID) async {
        store.resetCard(cardID, now: Date())
    }

    public func cardInfo(_ cardID: UUID) async -> CardInfo? {
        guard let card = store.cards[cardID] else { return nil }
        return CardInfo(
            card: card,
            schedule: store.schedules[cardID],
            logs: store.logs(forCard: cardID)
                .filter { !$0.isRevoked }
                .sorted { $0.reviewedAt > $1.reviewedAt }
        )
    }

    public func storedSession() async -> SessionState? {
        store.session
    }

    public func storeSession(_ state: SessionState?) async {
        store.session = state
    }
}
