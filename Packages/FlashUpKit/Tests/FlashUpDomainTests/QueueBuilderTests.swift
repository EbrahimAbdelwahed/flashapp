import Foundation
import Testing
@testable import FlashUpDomain

/// The two ways a user takes a card out of a queue (spec §A6.3): suspension, which lasts
/// until it is lifted, and burial, which lifts itself when its date passes.
@Suite("Queue exclusions")
struct QueueBuilderTests {
    /// A fixed instant so every expectation is reproducible in any time zone.
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private static let tomorrow = epoch.addingTimeInterval(86_400)

    private func candidate(
        due: Date? = nil,
        suspended: Bool = false,
        buriedUntil: Date? = nil
    ) -> QueueCandidate {
        let card = Card(
            noteID: UUID(),
            deckID: UUID(),
            template: CardTemplate(templateKey: "forward", front: "Q", back: "A")
        )
        // No due date means a card that has never been answered, and so has a schedule only
        // if the user hid it.
        let schedule: ReviewState? = {
            guard due != nil || suspended || buriedUntil != nil else { return nil }
            return ReviewState(
                state: due == nil ? .new : .review,
                stability: 12,
                difficulty: 5,
                dueAt: due ?? Self.epoch,
                lastReviewedAt: due == nil ? nil : Self.epoch,
                reps: due == nil ? 0 : 4,
                lapses: 0,
                suspendedAt: suspended ? Self.epoch : nil,
                buriedUntil: buriedUntil
            )
        }()
        return QueueCandidate(card: card, schedule: schedule, noteCreatedAt: Self.epoch)
    }

    @Test("A buried card is out of the queue and out of both counts")
    func buriedCardsAreExcluded() {
        let candidates = [
            candidate(due: Self.epoch, buriedUntil: Self.tomorrow),
            candidate(buriedUntil: Self.tomorrow)
        ]

        #expect(QueueBuilder.build(candidates: candidates, settings: .default, now: Self.epoch).isEmpty)
        #expect(QueueBuilder.dueCount(candidates: candidates, now: Self.epoch) == 0)
        #expect(QueueBuilder.newCount(candidates: candidates, now: Self.epoch) == 0)
    }

    @Test("Burial lifts itself once its date has passed — nothing has to unbury")
    func burialExpiresOnItsOwn() {
        let candidates = [
            candidate(due: Self.epoch, buriedUntil: Self.tomorrow),
            candidate(buriedUntil: Self.tomorrow)
        ]
        let later = Self.tomorrow.addingTimeInterval(60)

        #expect(QueueBuilder.build(candidates: candidates, settings: .default, now: later).count == 2)
        #expect(QueueBuilder.dueCount(candidates: candidates, now: later) == 1)
        #expect(QueueBuilder.newCount(candidates: candidates, now: later) == 1)
    }

    /// Hiding a card the user has never studied has to be recorded on a schedule, and that
    /// placeholder must not turn the card into an overdue review the moment it resurfaces.
    @Test("A new card hidden before it was ever studied comes back as new, not as due")
    func placeholderSchedulesDoNotFakeAReview() {
        let candidates = [candidate(buriedUntil: Self.tomorrow)]
        let later = Self.tomorrow.addingTimeInterval(60)

        #expect(QueueBuilder.dueCount(candidates: candidates, now: later) == 0)
        #expect(QueueBuilder.newCount(candidates: candidates, now: later) == 1)
        #expect(QueueBuilder.build(candidates: candidates, settings: .default, now: later).count == 1)
    }

    @Test("Suspension outlasts a burial that has already expired")
    func suspensionAndBurialAreIndependent() {
        let candidates = [candidate(due: Self.epoch, suspended: true, buriedUntil: Self.tomorrow)]
        let later = Self.tomorrow.addingTimeInterval(60)

        #expect(QueueBuilder.build(candidates: candidates, settings: .default, now: later).isEmpty)
        #expect(QueueBuilder.dueCount(candidates: candidates, now: later) == 0)
    }

    @Test("An unhidden card is still queued as normal")
    func plainCardsSurvive() {
        let candidates = [candidate(due: Self.epoch), candidate()]

        #expect(QueueBuilder.build(candidates: candidates, settings: .default, now: Self.epoch).count == 2)
        #expect(QueueBuilder.dueCount(candidates: candidates, now: Self.epoch) == 1)
        #expect(QueueBuilder.newCount(candidates: candidates, now: Self.epoch) == 1)
    }

    /// `sorted` is not stable in Swift and candidates arrive from a dictionary, so without a
    /// last-resort rule the queue came out in a different order on every launch. The order
    /// has to be total, and the same one on every device.
    @Test("Cards sharing a due date are ordered identically however they arrive")
    func theQueueOrderIsTotal() {
        let sameDate = [candidate(due: Self.epoch), candidate(due: Self.epoch), candidate(due: Self.epoch)]
        let sameCreation = [candidate(), candidate(), candidate()]

        func order(_ candidates: [QueueCandidate]) -> [UUID] {
            QueueBuilder.build(candidates: candidates, settings: .default, now: Self.epoch).map(\.id)
        }

        // Every permutation of the same input has to produce the same queue.
        #expect(order(sameDate) == order(sameDate.reversed()))
        #expect(order(sameDate) == order(sameDate.shuffled()))
        #expect(order(sameCreation) == order(sameCreation.reversed()))
        #expect(order(sameCreation) == order(sameCreation.shuffled()))
        #expect(order(sameDate).count == 3)
    }

    @Test("User flags survive a state the scheduler produced")
    func userFlagsAreCarriedAcrossAScheduledState() {
        let hidden = ReviewState(
            state: .review,
            stability: 3,
            difficulty: 5,
            dueAt: Self.epoch,
            lastReviewedAt: Self.epoch,
            reps: 1,
            lapses: 0,
            suspendedAt: Self.epoch,
            buriedUntil: Self.tomorrow
        )
        let fresh = ReviewState.unseen(dueAt: Self.tomorrow)

        let carried = fresh.carryingUserFlags(from: hidden)

        #expect(carried.suspendedAt == Self.epoch)
        #expect(carried.buriedUntil == Self.tomorrow)
        // Only the flags move: the schedule itself is the scheduler's.
        #expect(carried.dueAt == Self.tomorrow)
        #expect(carried.carryingUserFlags(from: nil).suspendedAt == nil)
        #expect(carried.carryingUserFlags(from: nil).buriedUntil == nil)
    }
}
