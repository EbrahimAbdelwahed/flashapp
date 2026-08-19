import CoreData
import Foundation
import Testing
@testable import FlashUpData
import FlashUpDomain

@Suite("Persistent duplicate fixtures", .serialized)
struct CoreDataDuplicatePersistenceTests {
    @Test("Equal-timestamp divergent duplicates fail deterministically for every persisted entity")
    func equalTimestampDuplicatesAreTypedFailures() async throws {
        for entity in DuplicateEntity.allCases {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("flashup-duplicate-\(entity.rawValue)", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let controller = try PersistenceController(
                configuration: .onDisk(storeURL: root.appendingPathComponent("Private.sqlite"))
            )
            let library = CoreDataLibraryRepository(persistenceController: controller)
            let deck = try await library.createDeck(named: "Fixture deck")
            let note = try #require(try await library.saveNote(NoteDraft(
                deckID: deck.id,
                type: .basic,
                front: "Fixture front",
                back: "Fixture back",
                tags: ["alpha"]
            )))
            let card = try #require((try await library.cards(for: note.id)).first)
            try controller.performBackgroundTask { context in
                try insertDuplicate(entity, deck: deck, note: note, card: card, in: context)
            }

            await #expect(throws: LibraryRepositoryError.malformedPersistedData) {
                _ = try await library.decks()
            }
            try controller.close()
        }
    }
}

private enum DuplicateEntity: String, CaseIterable {
    case deck, note, card, schedule, log, batch, settings, tag
}

// swiftlint:disable cyclomatic_complexity function_body_length
private func insertDuplicate(
    _ entity: DuplicateEntity,
    deck: Deck,
    note: Note,
    card: Card,
    in context: NSManagedObjectContext
) throws {
    let duplicateID = UUID()
    let tieDate = Date(timeIntervalSince1970: 1_650_000_000)

    func prepare(_ object: CDManagedObject) {
        object.setValue(duplicateID, forKey: "uuid")
        object.setValue(tieDate, forKey: "createdAt")
        object.setValue(tieDate, forKey: "updatedAt")
    }

    switch entity {
    case .deck:
        let first = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDDeck", into: context) as? CDDeck
        )
        let second = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDDeck", into: context) as? CDDeck
        )
        prepare(first); prepare(second)
        first.name = "first"; second.name = "second"
    case .note:
        let deckObject = try #require(
            try context.fetch(CDDeck.fetchRequest()).first { $0.uuid == deck.id }
        )
        let first = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDNote", into: context) as? CDNote
        )
        let second = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDNote", into: context) as? CDNote
        )
        prepare(first); prepare(second)
        for object in [first, second] {
            object.deck = deckObject
            object.type = NoteType.basic.rawValue
            object.back = "back"
            object.tagsJSON = "[]"
            object.mediaIDsJSON = "[]"
            object.contentHash = "hash"
        }
        first.front = "first"; second.front = "second"
    case .card:
        let noteObject = try #require(
            try context.fetch(CDNote.fetchRequest()).first { $0.uuid == note.id }
        )
        let templateKey = try #require(
            try context.fetch(CDCard.fetchRequest()).first { $0.uuid == card.id }
        ).templateKey
        let first = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDCard", into: context) as? CDCard
        )
        let second = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDCard", into: context) as? CDCard
        )
        prepare(first); prepare(second)
        first.note = noteObject; second.note = noteObject
        first.templateKey = templateKey; second.templateKey = "\(templateKey)-divergent"
    case .schedule:
        let first = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDSchedule", into: context) as? CDSchedule
        )
        let second = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDSchedule", into: context) as? CDSchedule
        )
        prepare(first); prepare(second)
        for object in [first, second] {
            object.cardUUID = card.id
            object.deckUUID = deck.id
            object.dueAt = tieDate
        }
        first.stateRaw = ScheduleState.new.rawValue; second.stateRaw = ScheduleState.review.rawValue
    case .log:
        let first = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDReviewLog", into: context) as? CDReviewLog
        )
        let second = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDReviewLog", into: context) as? CDReviewLog
        )
        prepare(first); prepare(second)
        for object in [first, second] {
            object.cardUUID = card.id
            object.deckUUID = deck.id
            object.reviewedAt = tieDate
            object.gradeRaw = Grade.good.rawValue
            object.prevStateRaw = ScheduleState.review.rawValue
            object.prevDueAt = tieDate
        }
        first.durationMs = 1; second.durationMs = 2
    case .batch:
        let first = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDImportBatch", into: context) as? CDImportBatch
        )
        let second = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDImportBatch", into: context) as? CDImportBatch
        )
        prepare(first); prepare(second)
        for object in [first, second] {
            object.destinationDeckUUID = deck.id
            object.importedAt = tieDate
            object.createdNoteUUIDsJSON = "[]"
            object.duplicateRowsJSON = "[]"
            object.rejectedRowsJSON = "[]"
            object.destinationWasNewDeck = false
        }
        first.sourceName = "first"; second.sourceName = "second"
    case .settings:
        let first = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDStudySettings", into: context) as? CDStudySettings
        )
        let second = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDStudySettings", into: context) as? CDStudySettings
        )
        prepare(first); prepare(second)
        first.singletonKey = "primary"; second.singletonKey = "primary"
        first.appearanceRaw = StudySettings.Appearance.system.rawValue
        second.appearanceRaw = StudySettings.Appearance.dark.rawValue
    case .tag:
        let first = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDTag", into: context) as? CDTag
        )
        let second = try #require(
            NSEntityDescription.insertNewObject(forEntityName: "CDTag", into: context) as? CDTag
        )
        prepare(first); prepare(second)
        first.name = "first"; first.normalizedName = "first"
        second.name = "second"; second.normalizedName = "second"
    }
}
// swiftlint:enable cyclomatic_complexity function_body_length
