import Foundation

/// A card with everything the queue needs to rank it.
public struct QueueCandidate: Equatable, Sendable {
    public let card: Card
    public let schedule: ReviewState?
    /// Creation time of the card's note, used to introduce new cards in authoring order.
    public let noteCreatedAt: Date

    public init(card: Card, schedule: ReviewState?, noteCreatedAt: Date) {
        self.card = card
        self.schedule = schedule
        self.noteCreatedAt = noteCreatedAt
    }

    var isNew: Bool { schedule == nil }
    var isSuspended: Bool { schedule?.suspendedAt != nil }
}

/// Builds the study queue (spec §A6.5).
///
/// Pure by design: it takes candidates and counts and returns an order, so the ordering
/// rules can be tested exhaustively without a store.
public enum QueueBuilder {
    public struct DailyProgress: Equatable, Sendable {
        public let reviewsDoneToday: Int
        public let newIntroducedToday: Int

        public init(reviewsDoneToday: Int = 0, newIntroducedToday: Int = 0) {
            self.reviewsDoneToday = reviewsDoneToday
            self.newIntroducedToday = newIntroducedToday
        }
    }

    /// Due cards first, then new ones, each capped by what the day's limits leave.
    public static func build(
        candidates: [QueueCandidate],
        settings: StudySettings,
        progress: DailyProgress = DailyProgress(),
        now: Date,
        calendar: Calendar = .current
    ) -> [Card] {
        let eligible = candidates.filter { !$0.isSuspended }
        let endOfToday = calendar.startOfDay(for: now).addingTimeInterval(86_400)

        let due = eligible
            .compactMap { candidate -> (Card, Date)? in
                guard let schedule = candidate.schedule, schedule.dueAt < endOfToday else { return nil }
                return (candidate.card, schedule.dueAt)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(max(settings.reviewsPerDay - progress.reviewsDoneToday, 0))
            .map(\.0)

        let fresh = eligible
            .filter(\.isNew)
            .sorted { lhs, rhs in
                lhs.noteCreatedAt == rhs.noteCreatedAt
                    ? lhs.card.templateKey < rhs.card.templateKey
                    : lhs.noteCreatedAt < rhs.noteCreatedAt
            }
            .prefix(max(settings.newPerDay - progress.newIntroducedToday, 0))
            .map(\.card)

        return due + fresh
    }

    /// Cards due right now — the number Today shows.
    public static func dueCount(candidates: [QueueCandidate], now: Date) -> Int {
        candidates.filter { candidate in
            guard !candidate.isSuspended, let schedule = candidate.schedule else { return false }
            return schedule.dueAt <= now
        }.count
    }

    public static func newCount(candidates: [QueueCandidate]) -> Int {
        candidates.filter { !$0.isSuspended && $0.isNew }.count
    }
}
