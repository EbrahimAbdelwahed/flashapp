import Foundation

/// Rebuilds a card's schedule from its history (spec §A6.4).
///
/// This is what makes multi-device merging safe: logs are append-only and unordered on
/// arrival, so the schedule is never "merged" — it is recomputed. Sorting by
/// (`reviewedAt`, `uuid`) makes the order total and identical on every device.
public enum ScheduleReplayer {
    public static func replay(
        logs: [ReviewLog],
        using scheduler: FSRSService,
        initialDueAt: Date
    ) -> ReviewState? {
        let ordered = logs
            .filter { !$0.isRevoked }
            .sorted { lhs, rhs in
                lhs.reviewedAt == rhs.reviewedAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.reviewedAt < rhs.reviewedAt
            }

        guard !ordered.isEmpty else { return nil }

        var state = ReviewState.unseen(dueAt: initialDueAt)
        for log in ordered {
            guard let transition = try? scheduler.next(state, grade: log.grade, at: log.reviewedAt) else { continue }
            state = transition.updated
        }
        return state
    }
}
