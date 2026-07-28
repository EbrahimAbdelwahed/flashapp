import FlashUpDomain
import Foundation

/// In-memory `LibraryRepository` used to build and demo the interface before the Core Data
/// stack exists (`fu-04-data-core`).
///
/// It is a real implementation of the real protocol, not a stub: schedules move through the
/// pinned FSRS adapter, answers accumulate, and undo works. What it does not do is persist
/// anything or talk to CloudKit. When the persistent repository lands, the interface layer
/// is unchanged — only `AppEnvironment` picks a different implementation.
///
/// The queue and metric rules here are the smallest thing that behaves correctly for the
/// screens; `fu-06-study-engine` replaces them with the real `QueueBuilder` and
/// `MetricsService`.
public actor InMemoryLibrary: LibraryRepository {
    /// Spec §A6.5 defaults.
    private let newPerDay = 20
    private let reviewsPerDay = 200

    private let scheduler: FSRSService
    private var decksByID: [UUID: Deck] = [:]
    private var notesByID: [UUID: Note] = [:]
    private var cards: [Card] = []
    private var schedules: [UUID: ReviewState] = [:]
    private var answers: [ScheduleTransition] = []
    private var answeredCardIDs: [UUID] = []

    public init(scheduler: FSRSService = SwiftFSRSAdapter(), seeded: Bool = true) {
        self.scheduler = scheduler
        guard seeded else { return }

        // Seeding is computed outside the actor's isolation and then assigned, so `init`
        // never calls an isolated method.
        let seed = Self.seedContent(scheduler: scheduler)
        self.decksByID = seed.decksByID
        self.notesByID = seed.notesByID
        self.cards = seed.cards
        self.schedules = seed.schedules
    }

    // MARK: - Reads

    public func todaySnapshot(now: Date) async -> TodaySnapshot {
        let summaries = deckSummaries(now: now)
        return TodaySnapshot(
            dueCount: summaries.reduce(0) { $0 + $1.dueCount },
            newCount: summaries.reduce(0) { $0 + $1.newCount },
            studiedToday: answers.filter { Calendar.current.isDate($0.reviewedAt, inSameDayAs: now) }.count,
            streakDays: answers.isEmpty ? 0 : 1,
            retention7Days: retention(now: now),
            decks: summaries
        )
    }

    public func decks() async -> [DeckSummary] {
        deckSummaries(now: Date())
    }

    public func cards(in scope: StudyScope) async -> [Card] {
        cards.filter { matches($0, scope) }
    }

    public func studyQueue(scope: StudyScope, now: Date) async -> [Card] {
        let eligible = cards.filter { matches($0, scope) }

        let due = eligible
            .compactMap { card -> (Card, Date)? in
                guard let state = schedules[card.id], state.dueAt <= now else { return nil }
                return (card, state.dueAt)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(reviewsPerDay)
            .map(\.0)

        let unseen = eligible
            .filter { schedules[$0.id] == nil }
            .sorted { lhs, rhs in
                let left = notesByID[lhs.noteID]?.createdAt ?? .distantPast
                let right = notesByID[rhs.noteID]?.createdAt ?? .distantPast
                return left == right ? lhs.templateKey < rhs.templateKey : left < right
            }
            .prefix(newPerDay)

        // Due first, then new (brief §Study).
        return due + unseen
    }

    public func schedule(for cardID: UUID) async -> ReviewState? {
        schedules[cardID]
    }

    // MARK: - Writes

    public func record(_ transition: ScheduleTransition, for cardID: UUID) async {
        schedules[cardID] = transition.updated
        answers.append(transition)
        answeredCardIDs.append(cardID)
    }

    public func revokeLastAnswer(in scope: StudyScope) async {
        guard let cardID = answeredCardIDs.last, let transition = answers.last else { return }
        answeredCardIDs.removeLast()
        answers.removeLast()
        // The pre-transition snapshot is exactly what undo restores; a `new` card loses its
        // schedule entirely so it returns to the unseen queue.
        schedules[cardID] = transition.previous.state == .new ? nil : transition.previous
    }

    // MARK: - Derived values

    private func deckSummaries(now: Date) -> [DeckSummary] {
        decksByID.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { deck in
                let deckCards = cards.filter { $0.deckID == deck.id }
                return DeckSummary(
                    deck: deck,
                    dueCount: deckCards.filter { (schedules[$0.id]?.dueAt).map { $0 <= now } ?? false }.count,
                    newCount: deckCards.filter { schedules[$0.id] == nil }.count,
                    totalCards: deckCards.count
                )
            }
    }

    private func retention(now: Date) -> Double? {
        let window = now.addingTimeInterval(-7 * 86_400)
        let mature = answers.filter { $0.reviewedAt >= window && $0.previous.state != .new }
        guard mature.count >= 10 else { return nil }
        return Double(mature.filter { $0.grade != .again }.count) / Double(mature.count)
    }

    private func matches(_ card: Card, _ scope: StudyScope) -> Bool {
        switch scope {
        case .allDecks: true
        case let .deck(id): card.deckID == id
        }
    }

    // MARK: - Seeding

    private struct Seed {
        var decksByID: [UUID: Deck] = [:]
        var notesByID: [UUID: Note] = [:]
        var cards: [Card] = []
        var schedules: [UUID: ReviewState] = [:]
    }

    private static func seedContent(scheduler: FSRSService) -> Seed {
        var seed = Seed()

        let decks = DemoContent.decks()
        for deck in decks { seed.decksByID[deck.id] = deck }

        for note in DemoContent.notes(in: decks) {
            seed.notesByID[note.id] = note
            for template in CardGenerator.generate(note) {
                seed.cards.append(Card(noteID: note.id, deckID: note.deckID, template: template))
            }
        }

        seed.schedules = seedHistory(for: seed.cards, scheduler: scheduler)
        return seed
    }

    /// Gives roughly a third of the cards a plausible past, so the interface is designed
    /// against a used library rather than an empty one: some cards due now, some later.
    private static func seedHistory(for cards: [Card], scheduler: FSRSService) -> [UUID: ReviewState] {
        let now = Date()
        let grades: [Grade] = [.good, .easy, .hard, .good]
        var schedules: [UUID: ReviewState] = [:]

        for (offset, card) in cards.enumerated() where offset % 3 == 0 {
            let answeredAt = now.addingTimeInterval(-Double((offset % 5) + 1) * 86_400)
            guard let transition = try? scheduler.next(
                .unseen(dueAt: answeredAt),
                grade: grades[offset % grades.count],
                at: answeredAt
            ) else { continue }
            schedules[card.id] = transition.updated
        }

        return schedules
    }
}
