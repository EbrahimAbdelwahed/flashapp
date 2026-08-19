import FlashUpDomain
import Foundation
import Observation

/// Drives one study session (spec §A11.3).
@Observable
@MainActor
final class StudySessionModel { // swiftlint:disable:this type_body_length
    /// Whether a card action applies to the card on screen or to every card its note makes.
    ///
    /// A reversed or cloze note generates siblings, and meeting the sibling ten seconds after
    /// the card that prompted the action is exactly what burying is for.
    enum ActionTarget {
        case card
        case note
    }

    /// The last thing the user did that a single undo can take back.
    ///
    /// Reset and delete are absent on purpose: undoing a reset would need an API to
    /// un-revoke logs, and a deleted note is recoverable from the Trash instead.
    enum SessionAction {
        case answered
        /// Cards pulled out of the queue, each with the position it occupied.
        case suspended(removals: [QueueRemoval])
        case buried(removals: [QueueRemoval])
    }

    struct QueueRemoval {
        let card: Card
        let index: Int
    }

    private let library: any LibraryRepository
    private let scheduler: FSRSService
    private let scope: StudyScope

    private(set) var queue: [Card] = []
    private(set) var index = 0
    private(set) var isRevealed = false
    private(set) var preview: SchedulePreview?
    private(set) var answeredCount = 0
    private(set) var lastAction: SessionAction?
    /// Every card the current note generates, so the note-level actions can be offered only
    /// when there is actually a sibling to act on.
    private(set) var siblingIDs: [UUID] = []
    private(set) var errorMessage: String?
    /// When the current prompt appeared, so the answer can record how long it took.
    private var shownAt = Date()
    private var startedAt = Date()

    init(library: any LibraryRepository, scope: StudyScope, scheduler: FSRSService = SwiftFSRSAdapter()) {
        self.library = library
        self.scope = scope
        self.scheduler = scheduler
    }

    var current: Card? {
        index < queue.count ? queue[index] : nil
    }

    var isFinished: Bool { current == nil }

    var progress: Double {
        queue.isEmpty ? 1 : Double(index) / Double(queue.count)
    }

    var remaining: Int { max(queue.count - index, 0) }

    var canUndo: Bool { lastAction != nil }

    /// Note-level actions are pointless on a note that made a single card.
    var hasSiblings: Bool { siblingIDs.count > 1 }

    func start() async {
        errorMessage = nil
        // A stored session for this scope wins: the user asked to carry on, not to be
        // handed a freshly built queue.
        do {
            if let stored = try await library.storedSession(),
               stored.scope.scope == scope,
               stored.isResumable(at: Date()) {
                queue = try await library.cards(withIDs: stored.remainingCardIDs)
                answeredCount = stored.answeredCount
                startedAt = stored.startedAt
            } else {
                queue = try await library.studyQueue(scope: scope, now: Date())
                answeredCount = 0
                startedAt = Date()
            }
        } catch {
            queue = []
            errorMessage = String(localized: "study.error.unavailable")
            return
        }
        index = 0
        lastAction = nil
        await persistSession()
        await loadCardContext()
    }

    private func persistSession() async {
        guard !isFinished else {
            do {
                try await library.storeSession(nil)
            } catch {
                errorMessage = String(localized: "study.error.unavailable")
            }
            return
        }
        do {
            try await library.storeSession(
                SessionState(
                    scope: scope,
                    remainingCardIDs: queue[index...].map(\.id),
                    answeredCount: answeredCount,
                    startedAt: startedAt
                )
            )
        } catch { errorMessage = String(localized: "study.error.unavailable") }
    }

    func reveal() {
        isRevealed = true
    }

    private func durationMs(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    func answer(_ grade: Grade) async {
        guard let card = current else { return }
        let now = Date()
        let state: ReviewState
        do {
            state = try await library.schedule(for: card.id) ?? .unseen(dueAt: now)
        } catch {
            reportStorageFailure()
            return
        }
        guard let transition = try? scheduler.next(state, grade: grade, at: now) else { return }

        do {
            try await library.record(transition, for: card.id, durationMs: durationMs(since: shownAt))
        } catch {
            reportStorageFailure()
            return
        }
        answeredCount += 1
        lastAction = .answered
        advance()
        await persistSession()
        await loadCardContext()
    }

    // MARK: - Card actions

    /// The note behind the card on screen, for the editor.
    func currentNote() async -> Note? {
        guard let card = current else { return nil }
        do {
            return try await library.note(card.noteID)
        } catch {
            reportStorageFailure()
            return nil
        }
    }

    func currentCardInfo() async -> CardInfo? {
        guard let card = current else { return nil }
        do {
            return try await library.cardInfo(card.id)
        } catch {
            reportStorageFailure()
            return nil
        }
    }

    /// Takes the card — or its whole note — out of every queue until the user lifts it.
    func suspend(_ target: ActionTarget) async {
        let ids = cardIDs(for: target)
        guard !ids.isEmpty else { return }
        do { try await library.setSuspended(true, cardIDs: ids) } catch {
            reportStorageFailure()
            return
        }
        let removals = removeFromQueue(Set(ids))
        lastAction = .suspended(removals: removals)
        await afterQueueChange()
    }

    /// Takes the card out of today's queue; it returns tomorrow on its own.
    func bury(_ target: ActionTarget) async {
        let ids = cardIDs(for: target)
        guard !ids.isEmpty else { return }
        do { try await library.setBuried(true, cardIDs: ids, until: Self.endOfDay(from: Date())) } catch {
            reportStorageFailure()
            return
        }
        let removals = removeFromQueue(Set(ids))
        lastAction = .buried(removals: removals)
        await afterQueueChange()
    }

    /// Sends the card back to new. It stays in the queue: the user reset it in order to
    /// learn it again, so handing it straight back is the useful thing to do.
    func resetCurrentCard() async {
        guard let card = current else { return }
        do { try await library.resetCard(card.id) } catch {
            reportStorageFailure()
            return
        }
        isRevealed = false
        shownAt = Date()
        // The reset revoked answers this session may have counted; undoing it would need an
        // API to bring revoked logs back, so the trail stops here.
        lastAction = nil
        await loadCardContext()
    }

    /// Moves the whole note to the Trash, from which it can be restored.
    func deleteCurrentNote() async {
        guard let card = current else { return }
        do { try await library.trashNote(card.noteID) } catch {
            reportStorageFailure()
            return
        }
        _ = removeFromQueue(Set(siblingIDs.isEmpty ? [card.id] : siblingIDs))
        lastAction = nil
        await afterQueueChange()
    }

    /// Picks up an edit made in the note editor.
    ///
    /// Saving regenerates the note's cards: a card whose template key survived keeps its
    /// identity and its FSRS progress, but the `Card` value sitting in the queue still holds
    /// the old text. A card whose template is gone — a deleted cloze group — leaves.
    func refreshAfterEdit() async {
        guard let noteID = current?.noteID else { return }
        let fresh: [Card]
        do {
            fresh = try await library.cards(for: noteID)
        } catch {
            reportStorageFailure()
            return
        }
        let byID = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })

        var updated = Array(queue[..<index])
        for card in queue[index...] {
            guard card.noteID == noteID else {
                updated.append(card)
                continue
            }
            if let replacement = byID[card.id] { updated.append(replacement) }
        }
        queue = updated

        isRevealed = false
        shownAt = Date()
        await afterQueueChange()
    }

    // MARK: - Undo

    /// Undo applies to the most recent action only (brief).
    func undo() async {
        switch lastAction {
        case .answered:
            guard index > 0 else { return }
            do {
                try await library.revokeLastAnswer(in: scope)
            } catch {
                reportStorageFailure()
                return
            }
            index -= 1
            answeredCount = max(answeredCount - 1, 0)
        case let .suspended(removals):
            do {
                try await library.setSuspended(false, cardIDs: removals.map(\.card.id))
            } catch {
                reportStorageFailure()
                return
            }
            restore(removals)
        case let .buried(removals):
            do {
                try await library.setBuried(false, cardIDs: removals.map(\.card.id), until: Date())
            } catch {
                reportStorageFailure()
                return
            }
            restore(removals)
        case nil:
            return
        }

        lastAction = nil
        isRevealed = false
        shownAt = Date()
        // The stored session has to follow the undo, or resuming would replay a queue the
        // user has already taken back.
        await persistSession()
        await loadCardContext()
    }

    // MARK: - Queue plumbing

    private func cardIDs(for target: ActionTarget) -> [UUID] {
        guard let card = current else { return [] }
        switch target {
        case .card: return [card.id]
        case .note: return siblingIDs.isEmpty ? [card.id] : siblingIDs
        }
    }

    /// Removes cards from the part of the queue still to come, reporting where each one was.
    ///
    /// Only from `index` onwards: a sibling answered earlier in this session stays answered,
    /// because burying a card is a statement about the future, not a retraction of the past.
    private func removeFromQueue(_ ids: Set<UUID>) -> [QueueRemoval] {
        let removals = queue.indices
            .filter { $0 >= index && ids.contains(queue[$0].id) }
            .map { QueueRemoval(card: queue[$0], index: $0) }

        queue = queue.enumerated()
            .filter { offset, card in offset < index || !ids.contains(card.id) }
            .map(\.element)

        return removals
    }

    /// Puts removed cards back exactly where they were. Ascending order matters: each
    /// insertion shifts everything after it.
    private func restore(_ removals: [QueueRemoval]) {
        for removal in removals.sorted(by: { $0.index < $1.index }) {
            queue.insert(removal.card, at: min(removal.index, queue.count))
        }
    }

    private func afterQueueChange() async {
        isRevealed = false
        shownAt = Date()
        await persistSession()
        await loadCardContext()
    }

    /// Tomorrow's first moment: a buried card is gone for the rest of today, no longer.
    private static func endOfDay(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
    }

    /// Caption for a grade button: how far out that answer would push the card.
    func interval(for grade: Grade) -> TimeInterval? {
        preview?.interval(for: grade, from: Date())
    }

    private func advance() {
        index += 1
        isRevealed = false
        shownAt = Date()
    }

    /// Everything the screen needs about whichever card is now in front: the intervals its
    /// grade buttons caption, and the siblings its note-level actions would reach.
    private func loadCardContext() async {
        guard let card = current else {
            preview = nil
            siblingIDs = []
            return
        }
        let now = Date()
        let state: ReviewState
        do {
            state = try await library.schedule(for: card.id) ?? .unseen(dueAt: now)
        } catch {
            reportStorageFailure()
            return
        }
        preview = try? scheduler.preview(state, at: now)
        do {
            siblingIDs = try await library.cards(for: card.noteID).map(\.id)
        } catch {
            reportStorageFailure()
            siblingIDs = []
        }
    }

    private func reportStorageFailure() {
        errorMessage = String(localized: "study.error.unavailable")
    }

    func clearError() {
        errorMessage = nil
    }
}
