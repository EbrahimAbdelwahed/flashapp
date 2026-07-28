import FSRS
import Foundation

/// The one and only file in Flash Up that imports swift-fsrs (spec §A6.1).
///
/// Configuration is fixed by the brief: library default weights, desired retention 0.90,
/// and **fuzz disabled** — fuzz randomises intervals per call, which would make the
/// multi-device replay of §A6.4 produce different schedules on different devices.
public struct SwiftFSRSAdapter: FSRSService {
    public static let defaultDesiredRetention = 0.90

    public let desiredRetention: Double
    private let engine: FSRS

    public init(desiredRetention: Double = SwiftFSRSAdapter.defaultDesiredRetention) {
        self.desiredRetention = desiredRetention
        self.engine = FSRS(
            parameters: FSRSParameters(
                requestRetention: desiredRetention,
                enableFuzz: false
            )
        )
    }

    public func next(_ state: ReviewState, grade: Grade, at now: Date) throws -> ScheduleTransition {
        let outcome = try schedule(state, grade: grade, at: now)
        return ScheduleTransition(
            previous: state,
            updated: Self.reviewState(from: outcome.card),
            grade: grade,
            reviewedAt: now,
            elapsedDays: Int(outcome.log.elapsedDays.rounded()),
            scheduledDays: Int(outcome.card.scheduledDays.rounded())
        )
    }

    public func preview(_ state: ReviewState, at now: Date) throws -> SchedulePreview {
        SchedulePreview(
            again: Self.reviewState(from: try schedule(state, grade: .again, at: now).card),
            hard: Self.reviewState(from: try schedule(state, grade: .hard, at: now).card),
            good: Self.reviewState(from: try schedule(state, grade: .good, at: now).card),
            easy: Self.reviewState(from: try schedule(state, grade: .easy, at: now).card)
        )
    }

    private func schedule(_ state: ReviewState, grade: Grade, at now: Date) throws -> RecordLogItem {
        do {
            return try engine.next(card: Self.card(from: state), now: now, grade: Self.rating(for: grade))
        } catch {
            throw SchedulingError.engineRejected(reason: String(describing: error))
        }
    }

    // MARK: - Mapping (the table in ADR-003)

    private static func rating(for grade: Grade) -> Rating {
        switch grade {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }

    private static func scheduleState(for state: CardState) -> ScheduleState {
        switch state {
        case .new: .new
        case .learning: .learning
        case .review: .review
        case .relearning: .relearning
        }
    }

    private static func cardState(for state: ScheduleState) -> CardState {
        switch state {
        case .new: .new
        case .learning: .learning
        case .review: .review
        case .relearning: .relearning
        }
    }

    /// `elapsedDays` and `scheduledDays` are recomputed by the engine from `lastReview`
    /// and the review time, so they are passed as zero rather than persisted.
    private static func card(from state: ReviewState) -> Card {
        Card(
            due: state.dueAt,
            stability: state.stability,
            difficulty: state.difficulty,
            elapsedDays: 0,
            scheduledDays: 0,
            reps: state.reps,
            lapses: state.lapses,
            state: cardState(for: state.state),
            lastReview: state.lastReviewedAt
        )
    }

    private static func reviewState(from card: Card) -> ReviewState {
        ReviewState(
            state: scheduleState(for: card.state),
            stability: card.stability,
            difficulty: card.difficulty,
            dueAt: card.due,
            lastReviewedAt: card.lastReview,
            reps: card.reps,
            lapses: card.lapses
        )
    }
}
