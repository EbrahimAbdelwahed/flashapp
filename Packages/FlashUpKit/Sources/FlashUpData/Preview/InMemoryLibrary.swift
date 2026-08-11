import FlashUpDomain
import Foundation

/// In-memory `LibraryRepository` used to build, demo and test the interface before the Core
/// Data stack exists (`fu-04-data-core`).
///
/// It is a real implementation of the real protocol, not a stub: content is generated into
/// cards, schedules move through the pinned FSRS adapter, undo replays history, import and
/// backup round-trip. What it does not do is persist anything or talk to CloudKit. When the
/// persistent repository lands, the interface layer is unchanged — only `AppEnvironment`
/// picks a different implementation.
public actor InMemoryLibrary: LibraryRepository {
    // Internal rather than private so the `+Studying` and `+Demo` extensions in this module
    // can reach them; still invisible outside `FlashUpData`.
    let scheduler: FSRSService
    var store: LibraryStore
    /// Fixed while sync is not wired; the interface is built against every state.
    private var status: SyncStatus

    public init(
        scheduler: FSRSService = SwiftFSRSAdapter(),
        seeded: Bool = true,
        status: SyncStatus = .upToDate(lastSyncedAt: Date())
    ) {
        self.scheduler = scheduler
        self.status = status
        self.store = seeded ? DemoContent.seededStore(scheduler: scheduler) : LibraryStore()
    }

    /// Adopts a store built elsewhere — today only the marketing pipeline's demo seed.
    init(
        scheduler: FSRSService,
        store: LibraryStore,
        status: SyncStatus = .upToDate(lastSyncedAt: Date())
    ) {
        self.scheduler = scheduler
        self.store = store
        self.status = status
    }

    // MARK: - Reading

    public func todaySnapshot(now: Date) async -> TodaySnapshot {
        let candidates = store.candidates(in: .allDecks)
        return TodaySnapshot(
            dueCount: QueueBuilder.dueCount(candidates: candidates, now: now),
            newCount: QueueBuilder.newCount(candidates: candidates, now: now),
            metrics: MetricsCalculator.metrics(logs: store.logs, now: now),
            decks: deckSummaries(now: now)
        )
    }

    public func metrics(now: Date) async -> StudyMetrics {
        MetricsCalculator.metrics(logs: store.logs, now: now)
    }

    public func decks() async -> [DeckSummary] {
        deckSummaries(now: Date())
    }

    public func deck(_ id: UUID) async -> Deck? {
        store.deckDeletedAt[id] == nil ? store.decks[id] : nil
    }

    public func notes(in deckID: UUID, filters: SearchFilters, now: Date) async -> [NoteSummary] {
        summaries(for: store.liveNotes(in: deckID), filters: filters, now: now)
    }

    public func search(_ filters: SearchFilters, now: Date) async -> [NoteSummary] {
        summaries(for: store.liveNotes(), filters: filters, now: now)
    }

    public func note(_ id: UUID) async -> Note? {
        store.noteDeletedAt[id] == nil ? store.notes[id] : nil
    }

    public func cards(for noteID: UUID) async -> [Card] {
        store.cards(forNote: noteID)
    }

    public func trashedNotes() async -> [Note] {
        store.noteDeletedAt.keys
            .compactMap { store.notes[$0] }
            .sorted { ($0.updatedAt) > ($1.updatedAt) }
    }

    public func contentHashes(in deckID: UUID) async -> [UUID: String] {
        var result: [UUID: String] = [:]
        for note in store.liveNotes(in: deckID) {
            result[note.id] = store.contentHashes[note.id]
        }
        return result
    }

    public func settings() async -> StudySettings {
        store.settings
    }

    public func syncStatus() async -> SyncStatus {
        status
    }

    // MARK: - Writing

    public func createDeck(named name: String) async -> Deck {
        let deck = Deck(name: name)
        store.decks[deck.id] = deck
        return deck
    }

    public func renameDeck(_ deckID: UUID, to name: String) async {
        guard var deck = store.decks[deckID] else { return }
        deck.name = name
        deck.updatedAt = Date()
        store.decks[deckID] = deck
    }

    public func trashDeck(_ deckID: UUID) async {
        store.deckDeletedAt[deckID] = Date()
    }

    @discardableResult
    public func saveNote(_ draft: NoteDraft) async -> Note? {
        store.save(draft, now: Date())
    }

    public func trashNote(_ noteID: UUID) async {
        store.noteDeletedAt[noteID] = Date()
    }

    public func restoreNote(_ noteID: UUID) async {
        store.noteDeletedAt.removeValue(forKey: noteID)
    }

    public func emptyTrash() async {
        for noteID in store.noteDeletedAt.keys {
            for card in store.cards(forNote: noteID) {
                store.cards.removeValue(forKey: card.id)
                store.schedules.removeValue(forKey: card.id)
            }
            store.notes.removeValue(forKey: noteID)
            store.contentHashes.removeValue(forKey: noteID)
        }
        store.noteDeletedAt.removeAll()

        for deckID in store.deckDeletedAt.keys {
            store.decks.removeValue(forKey: deckID)
        }
        store.deckDeletedAt.removeAll()
    }

    public func updateSettings(_ settings: StudySettings) async {
        store.settings = settings
    }

    // MARK: - Derived

    private func deckSummaries(now: Date) -> [DeckSummary] {
        store.liveDecks.map { deck in
            let candidates = store.candidates(in: .deck(deck.id))
            let upcoming = Self.upcomingCounts(candidates: candidates, now: now)
            return DeckSummary(
                deck: deck,
                dueCount: QueueBuilder.dueCount(candidates: candidates, now: now),
                newCount: QueueBuilder.newCount(candidates: candidates, now: now),
                tomorrowCount: upcoming.tomorrow,
                thisWeekCount: upcoming.thisWeek,
                laterCount: upcoming.later,
                suspendedCount: candidates.filter { $0.schedule?.suspendedAt != nil }.count,
                totalCards: candidates.count
            )
        }
    }

    /// Forecasts only cards that already have a review date. New cards stay visible under
    /// Today's "New" count; suspended cards deliberately stay out of every to-do bucket.
    struct UpcomingCounts: Equatable, Sendable {
        let tomorrow: Int
        let thisWeek: Int
        let later: Int
    }

    static func upcomingCounts(candidates: [QueueCandidate], now: Date) -> UpcomingCounts {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let startOfDayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday),
              let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday)
        else {
            return UpcomingCounts(tomorrow: 0, thisWeek: 0, later: 0)
        }

        var tomorrow = 0
        var thisWeek = 0
        var later = 0

        for candidate in candidates {
            guard candidate.schedule?.suspendedAt == nil, let dueAt = candidate.schedule?.dueAt else { continue }
            if dueAt >= startOfTomorrow, dueAt < startOfDayAfterTomorrow {
                tomorrow += 1
            } else if dueAt >= startOfDayAfterTomorrow, dueAt < endOfWeek {
                thisWeek += 1
            } else if dueAt >= endOfWeek {
                later += 1
            }
        }

        return UpcomingCounts(tomorrow: tomorrow, thisWeek: thisWeek, later: later)
    }

    private func summaries(for notes: [Note], filters: SearchFilters, now: Date) -> [NoteSummary] {
        notes
            .filter { matches($0, filters: filters, now: now) }
            .map { summary(for: $0, now: now) }
            .sorted { lhs, rhs in
                switch filters.sorting {
                case .updated: lhs.note.updatedAt > rhs.note.updatedAt
                case .created: lhs.note.createdAt > rhs.note.createdAt
                case .name: lhs.note.front.localizedCaseInsensitiveCompare(rhs.note.front) == .orderedAscending
                }
            }
    }

    private func summary(for note: Note, now: Date) -> NoteSummary {
        let cards = store.cards(forNote: note.id)
        let states = cards.map { store.schedules[$0.id] }
        return NoteSummary(
            note: note,
            cardCount: cards.count,
            dueCount: states.filter { ($0?.dueAt).map { $0 <= now } ?? false }.count,
            isNew: states.allSatisfy { $0?.isUnseen ?? true },
            // "Any", not "all": the same question `matches` asks, so a filtered list never
            // shows a row without the badge that put it there.
            isSuspended: states.contains { $0?.isSuspended ?? false },
            isBuried: states.contains { $0?.isBuried(at: now) ?? false }
        )
    }

    private func matches(_ note: Note, filters: SearchFilters, now: Date) -> Bool {
        let query = filters.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let haystack = [note.front, note.back ?? ""] + note.tags
            guard haystack.contains(where: { $0.localizedCaseInsensitiveContains(query) }) else { return false }
        }

        if let type = filters.type, note.type != type { return false }

        switch filters.state {
        case .any:
            return true
        case .new:
            return store.cards(forNote: note.id).allSatisfy { store.schedules[$0.id] == nil }
        case .due:
            return store.cards(forNote: note.id).contains { card in
                guard let state = store.schedules[card.id],
                      !state.isSuspended, !state.isBuried(at: now) else { return false }
                return state.dueAt <= now
            }
        case .suspended:
            return store.cards(forNote: note.id).contains { store.schedules[$0.id]?.isSuspended ?? false }
        case .buried:
            return store.cards(forNote: note.id).contains { store.schedules[$0.id]?.isBuried(at: now) ?? false }
        }
    }

    // MARK: - Portability (see InMemoryLibrary+Portability)

    func mutate(_ change: (inout LibraryStore) -> Void) {
        change(&store)
    }

    func read<T>(_ value: (LibraryStore) -> T) -> T {
        value(store)
    }
}
