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

    public init(
        state: ScheduleState,
        stability: Double,
        difficulty: Double,
        dueAt: Date,
        lastReviewedAt: Date?,
        reps: Int,
        lapses: Int
    ) {
        self.state = state
        self.stability = stability
        self.difficulty = difficulty
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
        self.reps = reps
        self.lapses = lapses
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
            lapses: 0
        )
    }
}
