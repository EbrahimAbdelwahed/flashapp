import Foundation

/// User-adjustable study preferences (spec §A6.5, §A11.2).
public struct StudySettings: Equatable, Codable, Sendable {
    public var newPerDay: Int
    public var reviewsPerDay: Int
    public var appearance: Appearance
    public var reminder: Reminder

    public enum Appearance: String, CaseIterable, Codable, Sendable {
        case system, light, dark
    }

    public struct Reminder: Equatable, Codable, Sendable {
        public var isEnabled: Bool
        public var hour: Int
        public var minute: Int

        public init(isEnabled: Bool = false, hour: Int = 20, minute: Int = 30) {
            self.isEnabled = isEnabled
            self.hour = hour
            self.minute = minute
        }
    }

    public static let `default` = StudySettings(
        newPerDay: 20,
        reviewsPerDay: 200,
        appearance: .system,
        reminder: Reminder()
    )

    public init(newPerDay: Int, reviewsPerDay: Int, appearance: Appearance, reminder: Reminder) {
        self.newPerDay = newPerDay
        self.reviewsPerDay = reviewsPerDay
        self.appearance = appearance
        self.reminder = reminder
    }
}

/// Where the app resumes from after being closed mid-session (spec §A6.6).
///
/// Device-local and never synced: a session is a physical act on one device.
public struct SessionState: Equatable, Codable, Sendable {
    public let scope: ScopeSnapshot
    public var remainingCardIDs: [UUID]
    public var answeredCount: Int
    public let startedAt: Date

    /// Codable mirror of `StudyScope`.
    public enum ScopeSnapshot: Equatable, Codable, Sendable {
        case allDecks
        case deck(UUID)

        public var scope: StudyScope {
            switch self {
            case .allDecks: .allDecks
            case let .deck(id): .deck(id)
            }
        }

        public init(_ scope: StudyScope) {
            switch scope {
            case .allDecks: self = .allDecks
            case let .deck(id): self = .deck(id)
            }
        }
    }

    public init(scope: StudyScope, remainingCardIDs: [UUID], answeredCount: Int, startedAt: Date) {
        self.scope = ScopeSnapshot(scope)
        self.remainingCardIDs = remainingCardIDs
        self.answeredCount = answeredCount
        self.startedAt = startedAt
    }

    /// A stored session is only offered back for a day; after that it is stale.
    public func isResumable(at now: Date, maximumAge: TimeInterval = 86_400) -> Bool {
        !remainingCardIDs.isEmpty && now.timeIntervalSince(startedAt) < maximumAge
    }
}
