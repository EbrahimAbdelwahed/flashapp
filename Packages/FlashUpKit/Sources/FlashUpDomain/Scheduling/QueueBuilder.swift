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

    /// A card with no schedule is new, and so is one whose schedule exists only to carry a
    /// suspension or a burial the user applied before ever studying it.
    var isNew: Bool { schedule?.isUnseen ?? true }
    var isSuspended: Bool { schedule?.isSuspended ?? false }

    /// Buried cards leave the queue until their date passes; nothing has to unbury them.
    func isBuried(at now: Date) -> Bool { schedule?.isBuried(at: now) ?? false }

    /// Out of every queue right now, whichever of the two user choices put it there.
    func isHidden(at now: Date) -> Bool { isSuspended || isBuried(at: now) }
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
        let eligible = candidates.filter { !$0.isHidden(at: now) }
        let endOfToday = calendar.startOfDay(for: now).addingTimeInterval(86_400)

        let due = eligible
            .compactMap { candidate -> (Card, Date)? in
                // New cards belong to the second pass even when a placeholder schedule
                // gives them a date in the past.
                guard !candidate.isNew, let schedule = candidate.schedule,
                      schedule.dueAt < endOfToday else { return nil }
                return (candidate.card, schedule.dueAt)
            }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? isBefore(lhs.0, rhs.0) : lhs.1 < rhs.1
            }
            .prefix(max(settings.reviewsPerDay - progress.reviewsDoneToday, 0))
            .map(\.0)

        let fresh = eligible
            .filter(\.isNew)
            .sorted { lhs, rhs in
                guard lhs.noteCreatedAt == rhs.noteCreatedAt else {
                    return lhs.noteCreatedAt < rhs.noteCreatedAt
                }
                guard lhs.card.templateKey == rhs.card.templateKey else {
                    return lhs.card.templateKey < rhs.card.templateKey
                }
                return isBefore(lhs.card, rhs.card)
            }
            .prefix(max(settings.newPerDay - progress.newIntroducedToday, 0))
            .map(\.card)

        return due + fresh
    }

    /// Last-resort tie-break, so the order is total rather than merely mostly-decided.
    ///
    /// `sorted` is not stable in Swift and the candidates arrive from a dictionary, so two
    /// cards sharing a due date came out in a different order on every launch — and, once
    /// the two schedules are in play, on different devices. Ordering by uuid is the same
    /// device-independent rule `ScheduleReplayer` uses to make replay reproducible.
    private static func isBefore(_ lhs: Card, _ rhs: Card) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    /// Cards due right now — the number Today shows.
    public static func dueCount(candidates: [QueueCandidate], now: Date) -> Int {
        candidates.filter { candidate in
            guard !candidate.isHidden(at: now), !candidate.isNew,
                  let schedule = candidate.schedule else { return false }
            return schedule.dueAt <= now
        }.count
    }

    public static func newCount(candidates: [QueueCandidate], now: Date) -> Int {
        candidates.filter { !$0.isHidden(at: now) && $0.isNew }.count
    }
}
