import Foundation

/// FSRS lifecycle state of a single card.
///
/// Raw values are persisted in `CDSchedule.stateRaw` and match the swift-fsrs `CardState`
/// raw values.
public enum ScheduleState: Int16, CaseIterable, Codable, Sendable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}

/// The scheduling state of one card, as the domain sees it.
///
/// This is exactly the attribute set of `CDSchedule` (spec §A2): the scheduler recomputes
/// elapsed and scheduled days from `lastReviewedAt` and the review time, so nothing else
/// has to be persisted for a replay to reproduce the same result.
public struct ReviewState: Equatable, Sendable {
    public let state: ScheduleState
    public let stability: Double
    public let difficulty: Double
    public let dueAt: Date
    public let lastReviewedAt: Date?
    public let reps: Int
    public let lapses: Int
    /// Set while the card is suspended: it stays in the library but leaves every queue
    /// (spec §A6.3). Suspension is a user choice, not a scheduling outcome, so the engine
    /// never reads or writes it.
    public var suspendedAt: Date?
    /// Set while the card is buried: it leaves the queue until this moment passes, then
    /// returns on its own. Like suspension it is a user choice the engine never reads, and
    /// because the expiry is evaluated at read time no unbury pass ever has to run.
    public var buriedUntil: Date?

    public init(
        state: ScheduleState,
        stability: Double,
        difficulty: Double,
        dueAt: Date,
        lastReviewedAt: Date?,
        reps: Int,
        lapses: Int,
        suspendedAt: Date? = nil,
        buriedUntil: Date? = nil
    ) {
        self.state = state
        self.stability = stability
        self.difficulty = difficulty
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
        self.reps = reps
        self.lapses = lapses
        self.suspendedAt = suspendedAt
        self.buriedUntil = buriedUntil
    }

    /// Whether the card is out of the queue because it was buried, at the given moment.
    public func isBuried(at now: Date) -> Bool {
        buriedUntil.map { $0 > now } ?? false
    }

    public var isSuspended: Bool { suspendedAt != nil }

    /// True while the card has never actually been answered.
    ///
    /// Having a schedule is not the same as having been studied: suspending or burying a
    /// card the user has never seen has to be recorded somewhere, and that somewhere is a
    /// schedule carrying nothing but the flag. Anything that asks "is this card new?" has to
    /// ask this and not merely whether a schedule exists, or those placeholders would show
    /// up as reviews that are already overdue.
    public var isUnseen: Bool { state == .new && reps == 0 && lastReviewedAt == nil }

    /// Whether the user has hidden this card, by either means.
    public var carriesUserFlag: Bool { suspendedAt != nil || buriedUntil != nil }

    /// Returns this state carrying `other`'s suspension and burial.
    ///
    /// The scheduler produces states that know nothing about those two flags, so every write
    /// that replaces a schedule — recording an answer, replaying after an undo — has to move
    /// them across. Doing it here rather than at each call site is what stops the next flag
    /// from being silently dropped by one of them.
    public func carryingUserFlags(from other: ReviewState?) -> ReviewState {
        var copy = self
        copy.suspendedAt = other?.suspendedAt
        copy.buriedUntil = other?.buriedUntil
        return copy
    }

    /// The state of a card that has never been answered. A card with no `CDSchedule` row
    /// is treated as unseen at the moment it first enters a queue.
    public static func unseen(dueAt: Date) -> ReviewState {
        ReviewState(
            state: .new,
            stability: 0,
            difficulty: 0,
            dueAt: dueAt,
            lastReviewedAt: nil,
            reps: 0,
            lapses: 0,
            suspendedAt: nil,
            buriedUntil: nil
        )
    }
}
