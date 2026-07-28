import Foundation

/// A deck with the counts the Today and Library screens display.
public struct DeckSummary: Identifiable, Equatable, Sendable {
    public let deck: Deck
    public let dueCount: Int
    public let newCount: Int
    public let totalCards: Int

    public var id: UUID { deck.id }

    public init(deck: Deck, dueCount: Int, newCount: Int, totalCards: Int) {
        self.deck = deck
        self.dueCount = dueCount
        self.newCount = newCount
        self.totalCards = totalCards
    }
}

/// Everything the Today screen needs in one read (spec §A11.2).
public struct TodaySnapshot: Equatable, Sendable {
    public let dueCount: Int
    public let newCount: Int
    public let studiedToday: Int
    public let streakDays: Int
    /// Share of non-again answers over the last 7 days; `nil` when there is too little
    /// history to be meaningful (spec §A6.7 hides noisy numbers).
    public let retention7Days: Double?
    public let decks: [DeckSummary]

    public var hasWorkToDo: Bool { dueCount + newCount > 0 }

    public init(
        dueCount: Int,
        newCount: Int,
        studiedToday: Int,
        streakDays: Int,
        retention7Days: Double?,
        decks: [DeckSummary]
    ) {
        self.dueCount = dueCount
        self.newCount = newCount
        self.studiedToday = studiedToday
        self.streakDays = streakDays
        self.retention7Days = retention7Days
        self.decks = decks
    }
}

/// What a study session is drawn from.
public enum StudyScope: Equatable, Hashable, Sendable {
    case allDecks
    case deck(UUID)
}

/// The read and write surface the app talks to.
///
/// Deliberately expressed in domain value types with no Core Data or CloudKit in sight, so
/// the interface layer can be built and tested against an in-memory implementation and
/// then run unchanged on the persistent one (`fu-04-data-core`).
public protocol LibraryRepository: Sendable {
    func todaySnapshot(now: Date) async -> TodaySnapshot
    func decks() async -> [DeckSummary]
    func cards(in scope: StudyScope) async -> [Card]
    /// Cards to study now, due first and then new, honouring the daily limits.
    func studyQueue(scope: StudyScope, now: Date) async -> [Card]
    func schedule(for cardID: UUID) async -> ReviewState?
    /// Records an answer and returns the resulting transition.
    func record(_ transition: ScheduleTransition, for cardID: UUID) async
    /// Reverts the most recent answer of the current session (spec §A6.3).
    func revokeLastAnswer(in scope: StudyScope) async
}
