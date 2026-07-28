import Foundation

/// One scheduling step: the state before the answer, the state after it, and the values
/// `CDReviewLog` records as its pre-transition snapshot (spec §A2, §A6.2).
public struct ScheduleTransition: Equatable, Sendable {
    public let previous: ReviewState
    public let updated: ReviewState
    public let grade: Grade
    public let reviewedAt: Date
    /// Whole days between the previous review and this one; 0 for a card's first answer.
    public let elapsedDays: Int
    /// Whole days the engine scheduled forward from this answer.
    public let scheduledDays: Int

    public init(
        previous: ReviewState,
        updated: ReviewState,
        grade: Grade,
        reviewedAt: Date,
        elapsedDays: Int,
        scheduledDays: Int
    ) {
        self.previous = previous
        self.updated = updated
        self.grade = grade
        self.reviewedAt = reviewedAt
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
    }
}

/// The four outcomes a learner can choose between, used to caption the grade buttons with
/// their next interval (spec §A11.3).
public struct SchedulePreview: Equatable, Sendable {
    public let again: ReviewState
    public let hard: ReviewState
    public let good: ReviewState
    public let easy: ReviewState

    public init(again: ReviewState, hard: ReviewState, good: ReviewState, easy: ReviewState) {
        self.again = again
        self.hard = hard
        self.good = good
        self.easy = easy
    }

    public subscript(grade: Grade) -> ReviewState {
        switch grade {
        case .again: again
        case .hard: hard
        case .good: good
        case .easy: easy
        }
    }

    /// Time from `now` until the card would next be due if answered with `grade`.
    public func interval(for grade: Grade, from now: Date) -> TimeInterval {
        self[grade].dueAt.timeIntervalSince(now)
    }
}

public enum SchedulingError: Error, Equatable, Sendable {
    /// The engine refused the transition. `reason` is engine text for logs only; it is
    /// never shown to the user and never contains card content.
    case engineRejected(reason: String)
}

/// The only scheduling contract the rest of Flash Up sees.
///
/// Nothing outside the adapter imports swift-fsrs (spec §A6.1), so the engine can be
/// replaced or re-pinned without touching storage, queues or UI.
public protocol FSRSService: Sendable {
    /// Target probability of recall at review time. Flash Up ships 0.90 and exposes no
    /// user-facing parameter UI (brief).
    var desiredRetention: Double { get }

    /// Applies `grade` to `state` at `now` and returns the resulting transition.
    func next(_ state: ReviewState, grade: Grade, at now: Date) throws -> ScheduleTransition

    /// Computes all four outcomes without committing any of them.
    func preview(_ state: ReviewState, at now: Date) throws -> SchedulePreview
}
