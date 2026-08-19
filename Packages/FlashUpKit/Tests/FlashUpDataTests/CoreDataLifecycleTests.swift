import Foundation
import Testing
@testable import FlashUpData
import FlashUpDomain

@Suite("Persistent lifecycle", .serialized)
struct CoreDataLifecycleTests {
    @Test("Review log previous state survives a close and reopen exactly")
    // swiftlint:disable:next function_body_length
    func reviewLogPreviousStateSurvivesRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-review-log-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = root.appendingPathComponent("Private.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let cardID: UUID
        let expectedLogs: [ReviewLog]
        do {
            let controller = try PersistenceController(configuration: .onDisk(storeURL: storeURL))
            let library = CoreDataLibraryRepository(persistenceController: controller)
            let deck = try await library.createDeck(named: "Review log deck")
            let note = try #require(try await library.saveNote(NoteDraft(
                deckID: deck.id, type: .basic, front: "question", back: "answer"
            )))
            cardID = try #require((try await library.cards(for: note.id)).first?.id)
            let previous = ReviewState(
                state: .review,
                stability: 4.5,
                difficulty: 6.2,
                dueAt: Date(timeIntervalSince1970: 1_700_000_500),
                lastReviewedAt: Date(timeIntervalSince1970: 1_700_000_000),
                reps: 7,
                lapses: 2
            )
            let updated = ReviewState(
                state: .review,
                stability: 6.5,
                difficulty: 5.9,
                dueAt: Date(timeIntervalSince1970: 1_700_001_500),
                lastReviewedAt: Date(timeIntervalSince1970: 1_700_000_600),
                reps: 8,
                lapses: 2
            )
            try await library.record(
                ScheduleTransition(
                    previous: previous,
                    updated: updated,
                    grade: .good,
                    reviewedAt: Date(timeIntervalSince1970: 1_700_000_600),
                    elapsedDays: 3,
                    scheduledDays: 17
                ),
                for: cardID,
                durationMs: 1234
            )
            expectedLogs = try #require(try await library.cardInfo(cardID)?.logs)
            try controller.close()
        }

        let reopenedController = try PersistenceController(configuration: .onDisk(storeURL: storeURL))
        let reopened = CoreDataLibraryRepository(persistenceController: reopenedController)
        #expect(try await reopened.cardInfo(cardID)?.logs == expectedLogs)
        try reopenedController.close()
    }

    @Test("Closing a repository quiesces its owned coordinator before replacement")
    func repositoryCloseQuiescesCoordinator() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-repository-close", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try PersistenceController(
            configuration: .onDisk(storeURL: root.appendingPathComponent("Private.sqlite"))
        )
        let library = CoreDataLibraryRepository(persistenceController: controller)
        _ = try await library.createDeck(named: "Before replacement")
        try await library.close()

        #expect(controller.isClosed)
        await #expect(throws: LibraryRepositoryError.readFailed) {
            _ = try await library.decks()
        }
    }
}
