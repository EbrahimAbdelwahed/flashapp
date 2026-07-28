import Foundation

/// One answer, recorded append-only (spec §A2, §A6.2).
///
/// The pre-transition snapshot is what makes `ScheduleReplayer` able to rebuild a card's
/// schedule from history alone, on any device, in any merge order.
public struct ReviewLog: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let cardID: UUID
    public let deckID: UUID
    public let reviewedAt: Date
    public let durationMs: Int
    public let grade: Grade
    public let previous: ReviewState
    public let scheduledDays: Int
    public let elapsedDays: Int
    /// Set by "undo last answer" instead of deleting: append-only and multi-device safe.
    public var revokedAt: Date?

    public init(
        id: UUID = UUID(),
        cardID: UUID,
        deckID: UUID,
        reviewedAt: Date,
        durationMs: Int,
        grade: Grade,
        previous: ReviewState,
        scheduledDays: Int,
        elapsedDays: Int,
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.cardID = cardID
        self.deckID = deckID
        self.reviewedAt = reviewedAt
        self.durationMs = durationMs
        self.grade = grade
        self.previous = previous
        self.scheduledDays = scheduledDays
        self.elapsedDays = elapsedDays
        self.revokedAt = revokedAt
    }

    public var isRevoked: Bool { revokedAt != nil }

    /// Builds the audit record for a transition the engine just produced.
    public init(transition: ScheduleTransition, cardID: UUID, deckID: UUID, durationMs: Int, id: UUID = UUID()) {
        self.init(
            id: id,
            cardID: cardID,
            deckID: deckID,
            reviewedAt: transition.reviewedAt,
            durationMs: durationMs,
            grade: transition.grade,
            previous: transition.previous,
            scheduledDays: transition.scheduledDays,
            elapsedDays: transition.elapsedDays
        )
    }
}
