import FlashUpDomain
import Foundation
import Observation

/// Drives one study session (spec §A11.3).
@Observable
@MainActor
final class StudySessionModel {
    private let library: any LibraryRepository
    private let scheduler: FSRSService
    private let scope: StudyScope

    private(set) var queue: [Card] = []
    private(set) var index = 0
    private(set) var isRevealed = false
    private(set) var preview: SchedulePreview?
    private(set) var answeredCount = 0
    private(set) var canUndo = false
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

    func start() async {
        // A stored session for this scope wins: the user asked to carry on, not to be
        // handed a freshly built queue.
        if let stored = await library.storedSession(),
           stored.scope.scope == scope,
           stored.isResumable(at: Date()) {
            queue = await library.cards(withIDs: stored.remainingCardIDs)
            answeredCount = stored.answeredCount
            startedAt = stored.startedAt
        } else {
            queue = await library.studyQueue(scope: scope, now: Date())
            answeredCount = 0
            startedAt = Date()
        }
        index = 0
        canUndo = false
        await persistSession()
        await loadPreview()
    }

    private func persistSession() async {
        guard !isFinished else {
            await library.storeSession(nil)
            return
        }
        await library.storeSession(
            SessionState(
                scope: scope,
                remainingCardIDs: queue[index...].map(\.id),
                answeredCount: answeredCount,
                startedAt: startedAt
            )
        )
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
        let state = await library.schedule(for: card.id) ?? .unseen(dueAt: now)
        guard let transition = try? scheduler.next(state, grade: grade, at: now) else { return }

        await library.record(transition, for: card.id, durationMs: durationMs(since: shownAt))
        answeredCount += 1
        canUndo = true
        advance()
        await persistSession()
        await loadPreview()
    }

    /// Undo applies to the most recent answer only (brief). The card returns to the front
    /// of the queue so it is answered again immediately.
    func undo() async {
        guard canUndo, index > 0 else { return }
        await library.revokeLastAnswer(in: scope)
        index -= 1
        answeredCount = max(answeredCount - 1, 0)
        canUndo = false
        isRevealed = false
        await loadPreview()
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

    private func loadPreview() async {
        guard let card = current else {
            preview = nil
            return
        }
        let now = Date()
        let state = await library.schedule(for: card.id) ?? .unseen(dueAt: now)
        preview = try? scheduler.preview(state, at: now)
    }
}
