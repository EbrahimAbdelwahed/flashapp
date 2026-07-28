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
            updated: Self.reviewState(from: outcome),
            grade: grade,
            reviewedAt: now,
            elapsedDays: Int(outcome.log.elapsedDays.rounded()),
            scheduledDays: Int(outcome.card.scheduledDays.rounded())
        )
    }

    public func preview(_ state: ReviewState, at now: Date) throws -> SchedulePreview {
        SchedulePreview(
            again: Self.reviewState(from: try schedule(state, grade: .again, at: now)),
            hard: Self.reviewState(from: try schedule(state, grade: .hard, at: now)),
            good: Self.reviewState(from: try schedule(state, grade: .good, at: now)),
            easy: Self.reviewState(from: try schedule(state, grade: .easy, at: now))
        )
    }

    private func schedule(_ state: ReviewState, grade: Grade, at now: Date) throws -> RecordLogItem {
        do {
            // The engine's own `Card` type cannot be written down here: the module `FSRS`
            // and its class `FSRS` share a name, so `FSRS.Card` does not resolve. `.init`
            // infers it from the parameter, which is why this is the only construction site.
            return try engine.next(
                card: .init(
                    due: state.dueAt,
                    stability: state.stability,
                    difficulty: state.difficulty,
                    // Recomputed by the engine from `lastReview` and the review time, so
                    // they are never persisted on our side.
                    elapsedDays: 0,
                    scheduledDays: 0,
                    reps: state.reps,
                    lapses: state.lapses,
                    state: Self.cardState(for: state.state),
                    lastReview: state.lastReviewedAt
                ),
                now: now,
                grade: Self.rating(for: grade)
            )
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

    /// Reads through `RecordLogItem`, whose name does not collide, so the engine's card
    /// type never has to be named.
    private static func reviewState(from item: RecordLogItem) -> ReviewState {
        ReviewState(
            state: scheduleState(for: item.card.state),
            stability: item.card.stability,
            difficulty: item.card.difficulty,
            dueAt: item.card.due,
            lastReviewedAt: item.card.lastReview,
            reps: item.card.reps,
            lapses: item.card.lapses
        )
    }
}
