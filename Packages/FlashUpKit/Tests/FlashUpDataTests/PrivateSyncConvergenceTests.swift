import CoreData
import FlashUpDomain
import Foundation
import Testing
@testable import FlashUpData

@Suite("Private sync convergence", .serialized)
struct PrivateSyncConvergenceTests {
    @Test("Remote tag duplicates keep the lowest UUID and preserve note links")
    func tagDeduplication() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-sync-tags", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = try PersistenceController(
            configuration: .onDisk(storeURL: root.appendingPathComponent("Private.sqlite"))
        )
        let library = CoreDataLibraryRepository(persistenceController: controller)
        let deck = try await library.createDeck(named: "Sync tags")
        let note = try #require(try await library.saveNote(NoteDraft(
            deckID: deck.id,
            type: .basic,
            front: "Front",
            back: "Back",
            tags: ["Anatomy"]
        )))

        try controller.performBackgroundTask { context in
            let noteObject = try #require(
                try context.fetch(CDNote.fetchRequest()).first { $0.uuid == note.id }
            )
            let duplicate = CDTag(context: context)
            duplicate.uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000001")
            duplicate.name = "ANATOMY"
            duplicate.normalizedName = "anatomy"
            let existing = noteObject.tags?.allObjects as? [CDTag] ?? []
            noteObject.tags = NSSet(array: existing + [duplicate])
        }

        _ = try await library.refreshRemoteChanges()
        let matchingTags = try controller.performBackgroundTask { context in
            try context.fetch(CDTag.fetchRequest()).filter { $0.normalizedName == "anatomy" }
        }
        #expect(matchingTags.count == 1)
        #expect(try await library.note(note.id)?.tags == ["ANATOMY"])
        try controller.close()
    }

    @Test("Remote schedule duplicates replay the union of review logs")
    func scheduleReplayAndDeduplication() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashup-sync-schedules", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = try PersistenceController(
            configuration: .onDisk(storeURL: root.appendingPathComponent("Private.sqlite"))
        )
        let scheduler = SwiftFSRSAdapter()
        let library = CoreDataLibraryRepository(persistenceController: controller, scheduler: scheduler)
        let deck = try await library.createDeck(named: "Sync schedules")
        let note = try #require(try await library.saveNote(NoteDraft(
            deckID: deck.id,
            type: .basic,
            front: "Front",
            back: "Back"
        )))
        let card = try #require(try await library.cards(for: note.id).first)
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try scheduler.next(.unseen(dueAt: firstDate), grade: .good, at: firstDate)
        try await library.record(first, for: card.id, durationMs: 1_000)
        let secondDate = firstDate.addingTimeInterval(86_400)
        let second = try scheduler.next(first.updated, grade: .hard, at: secondDate)
        try await library.record(second, for: card.id, durationMs: 1_100)

        try controller.performBackgroundTask { context in
            let duplicate = CDSchedule(context: context)
            duplicate.uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000002")
            duplicate.cardUUID = card.id
            duplicate.deckUUID = deck.id
            duplicate.stateRaw = ScheduleState.new.rawValue
            duplicate.dueAt = firstDate
        }

        _ = try await library.refreshRemoteChanges()
        let schedules = try controller.performBackgroundTask { context in
            try context.fetch(CDSchedule.fetchRequest()).filter { $0.cardUUID == card.id }
        }
        #expect(schedules.count == 1)

        let info = try #require(try await library.cardInfo(card.id))
        let initialDueAt = try #require(info.logs.map(\.reviewedAt).min())
        let replayed = ScheduleReplayer.replay(
            logs: info.logs,
            using: scheduler,
            initialDueAt: initialDueAt
        )
        #expect(info.schedule?.state == replayed?.state)
        #expect(info.schedule?.reps == replayed?.reps)
        try controller.close()
    }
}
