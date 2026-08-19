import Foundation

/// A deck with the counts the Today and Library screens display.
public struct DeckSummary: Identifiable, Equatable, Sendable {
    public let deck: Deck
    public let dueCount: Int
    public let newCount: Int
    public let tomorrowCount: Int
    public let thisWeekCount: Int
    public let laterCount: Int
    public let suspendedCount: Int
    public let totalCards: Int

    public var id: UUID { deck.id }

    public init(
        deck: Deck,
        dueCount: Int,
        newCount: Int,
        tomorrowCount: Int = 0,
        thisWeekCount: Int = 0,
        laterCount: Int = 0,
        suspendedCount: Int = 0,
        totalCards: Int
    ) {
        self.deck = deck
        self.dueCount = dueCount
        self.newCount = newCount
        self.tomorrowCount = tomorrowCount
        self.thisWeekCount = thisWeekCount
        self.laterCount = laterCount
        self.suspendedCount = suspendedCount
        self.totalCards = totalCards
    }
}

/// Everything the Today screen needs in one read (spec §A11.2).
public struct TodaySnapshot: Equatable, Sendable {
    public let dueCount: Int
    public let newCount: Int
    public let metrics: StudyMetrics
    public let decks: [DeckSummary]

    public var hasWorkToDo: Bool { dueCount + newCount > 0 }

    public init(dueCount: Int, newCount: Int, metrics: StudyMetrics, decks: [DeckSummary]) {
        self.dueCount = dueCount
        self.newCount = newCount
        self.metrics = metrics
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
/// the interface layer can be built and tested against an in-memory implementation and then
/// run unchanged on the persistent one (`fu-04-data-core`).
public protocol LibraryRepository: Sendable {
    /// Health of the last repository operation. `failed` is never represented as an empty
    /// successful result by the persistent adapter.
    func repositoryState() async -> LibraryRepositoryState

    // MARK: Reading

    func todaySnapshot(now: Date) async throws -> TodaySnapshot
    func metrics(now: Date) async throws -> StudyMetrics
    func decks() async throws -> [DeckSummary]
    func deck(_ id: UUID) async throws -> Deck?
    func notes(in deckID: UUID, filters: SearchFilters, now: Date) async throws -> [NoteSummary]
    func search(_ filters: SearchFilters, now: Date) async throws -> [NoteSummary]
    func note(_ id: UUID) async throws -> Note?
    func cards(for noteID: UUID) async throws -> [Card]
    func trashedNotes() async throws -> [Note]
    func contentHashes(in deckID: UUID) async throws -> [UUID: String]
    func settings() async throws -> StudySettings
    func syncStatus() async throws -> SyncStatus

    // MARK: Studying

    func studyQueue(scope: StudyScope, now: Date) async throws -> [Card]
    func cards(withIDs ids: [UUID]) async throws -> [Card]
    func schedule(for cardID: UUID) async throws -> ReviewState?
    func record(_ transition: ScheduleTransition, for cardID: UUID, durationMs: Int) async throws
    func revokeLastAnswer(in scope: StudyScope) async throws
    /// Takes cards in or out of every queue indefinitely. Plural so a note's siblings are
    /// suspended together in one write.
    func setSuspended(_ suspended: Bool, cardIDs: [UUID]) async throws
    /// Takes cards out of the queue until `until`, after which they return on their own.
    /// `until` is the caller's to choose so the decision stays testable.
    func setBuried(_ buried: Bool, cardIDs: [UUID], until: Date) async throws
    /// Lifts both hiding flags from every card of a note, putting it back in the queues.
    ///
    /// One verb rather than two flag writes from the caller: from the Library the user is
    /// resuming a note, and does not distinguish which of the two ways it came to be hidden.
    func resumeNote(_ noteID: UUID) async throws
    /// Revokes every log for the card and drops its schedule, so it returns to "new".
    func resetCard(_ cardID: UUID) async throws
    /// Schedule plus surviving history for one card, for the card info screen.
    func cardInfo(_ cardID: UUID) async throws -> CardInfo?
    func storedSession() async throws -> SessionState?
    func storeSession(_ state: SessionState?) async throws

    // MARK: Writing

    func createDeck(named name: String) async throws -> Deck
    func renameDeck(_ deckID: UUID, to name: String) async throws
    func trashDeck(_ deckID: UUID) async throws
    @discardableResult func saveNote(_ draft: NoteDraft) async throws -> Note?
    func trashNote(_ noteID: UUID) async throws
    func restoreNote(_ noteID: UUID) async throws
    func emptyTrash() async throws
    func updateSettings(_ settings: StudySettings) async throws
    /// Installs the bundled demo deck once. Repeated calls are idempotent.
    func installDemoDeck() async throws

    // MARK: Portability

    func commitImport(
        _ plan: ImportPlan,
        into deckID: UUID,
        sourceName: String,
        wasNewDeck: Bool
    ) async throws -> ImportBatch
    func undoImport(_ batchID: UUID) async throws
    func exportCSV(deckID: UUID?) async throws -> Data
    func backupDocument(appVersion: String, now: Date) async throws -> BackupDocument
    func restore(_ document: BackupDocument) async throws -> RestoreSummary
    /// Irreversible local erasure (spec §A11.2 DeleteAllDataFlow).
    func deleteAllData() async throws
}
