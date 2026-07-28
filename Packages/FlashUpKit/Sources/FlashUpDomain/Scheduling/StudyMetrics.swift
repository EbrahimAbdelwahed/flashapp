import Foundation

/// The numbers Today and Statistics display (spec §A6.7).
public struct StudyMetrics: Equatable, Sendable {
    public let studiedToday: Int
    public let streakDays: Int
    /// `nil` when fewer than `minimumRetentionSample` mature answers exist in the window:
    /// a percentage computed from three reviews is noise, not information.
    public let retention7Days: Double?
    public let retention30Days: Double?
    /// Answers per day over the last 30 days, oldest first, for the history chart.
    public let dailyReviews: [DailyCount]

    public struct DailyCount: Equatable, Identifiable, Sendable {
        public let day: Date
        public let count: Int
        public var id: Date { day }

        public init(day: Date, count: Int) {
            self.day = day
            self.count = count
        }
    }
}

public enum MetricsCalculator {
    public static let minimumRetentionSample = 10

    public static func metrics(
        logs: [ReviewLog],
        now: Date,
        calendar: Calendar = .current
    ) -> StudyMetrics {
        let live = logs.filter { !$0.isRevoked }

        return StudyMetrics(
            studiedToday: live.filter { calendar.isDate($0.reviewedAt, inSameDayAs: now) }.count,
            streakDays: streak(logs: live, now: now, calendar: calendar),
            retention7Days: retention(logs: live, days: 7, now: now),
            retention30Days: retention(logs: live, days: 30, now: now),
            dailyReviews: dailyReviews(logs: live, days: 30, now: now, calendar: calendar)
        )
    }

    /// Share of mature answers that were not "Again".
    ///
    /// Only cards already in review or relearning count: grading a brand-new card says
    /// nothing about how well it was retained.
    static func retention(logs: [ReviewLog], days: Int, now: Date) -> Double? {
        let window = now.addingTimeInterval(-Double(days) * 86_400)
        let mature = logs.filter { log in
            log.reviewedAt >= window && (log.previous.state == .review || log.previous.state == .relearning)
        }
        guard mature.count >= minimumRetentionSample else { return nil }
        return Double(mature.filter { $0.grade != .again }.count) / Double(mature.count)
    }

    /// Consecutive days ending today or yesterday with at least one answer.
    ///
    /// Yesterday counts as the end so that a streak is not declared broken before the day
    /// the user is still living through.
    static func streak(logs: [ReviewLog], now: Date, calendar: Calendar) -> Int {
        let studiedDays = Set(logs.map { calendar.startOfDay(for: $0.reviewedAt) })
        guard !studiedDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var cursor = studiedDays.contains(today) ? today : yesterday
        guard studiedDays.contains(cursor) else { return 0 }

        var count = 0
        while studiedDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func dailyReviews(
        logs: [ReviewLog],
        days: Int,
        now: Date,
        calendar: Calendar
    ) -> [StudyMetrics.DailyCount] {
        let today = calendar.startOfDay(for: now)
        let counts = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.reviewedAt) }

        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return StudyMetrics.DailyCount(day: day, count: counts[day]?.count ?? 0)
        }
    }
}
