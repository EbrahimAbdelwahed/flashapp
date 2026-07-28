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
        queue = await library.studyQueue(scope: scope, now: Date())
        index = 0
        answeredCount = 0
        canUndo = false
        await loadPreview()
    }

    func reveal() {
        isRevealed = true
    }

    func answer(_ grade: Grade) async {
        guard let card = current else { return }
        let now = Date()
        let state = await library.schedule(for: card.id) ?? .unseen(dueAt: now)
        guard let transition = try? scheduler.next(state, grade: grade, at: now) else { return }

        await library.record(transition, for: card.id)
        answeredCount += 1
        canUndo = true
        advance()
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
