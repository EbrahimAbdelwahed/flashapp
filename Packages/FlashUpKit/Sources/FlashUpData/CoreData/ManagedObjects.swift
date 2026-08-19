import CoreData
import Foundation

/// Shared lifecycle hooks for the V1 Core Data entities.
///
/// The model deliberately keeps `uuid` optional at the Core Data level so it remains
/// CloudKit-compatible. Every inserted object receives an app-level UUID immediately;
/// repositories use that UUID for identity and never use an `NSManagedObjectID`.
@objc(CDManagedObject)
open class CDManagedObject: NSManagedObject {
    open override func awakeFromInsert() {
        super.awakeFromInsert()
        let now = Date()
        setValue(UUID(), forKey: "uuid")
        setValue(now, forKey: "createdAt")
        setValue(now, forKey: "updatedAt")
    }

    open override func willSave() {
        super.willSave()
        guard !isDeleted else { return }

        let changedKeys = changedValues().keys
        // Core Data can call `willSave` repeatedly while preparing one save. Once this
        // callback has dirtied `updatedAt`, leave it alone or the context never becomes clean.
        guard !changedKeys.contains("updatedAt") else { return }
        guard changedKeys.contains(where: { $0 != "updatedAt" }) else { return }
        setValue(Date(), forKey: "updatedAt")
    }
}

@objc(CDDeck)
public class CDDeck: CDManagedObject {
    @NSManaged public var createdAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var demoSeedID: String?
    @NSManaged public var demoVersion: Int16
    @NSManaged public var isDemo: Bool
    @NSManaged public var name: String
    @NSManaged public var notes: NSSet?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var uuid: UUID?
}

@objc(CDNote)
public class CDNote: CDManagedObject {
    @NSManaged public var back: String
    @NSManaged public var cards: NSSet?
    @NSManaged public var contentHash: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var deck: CDDeck?
    @NSManaged public var front: String
    @NSManaged public var mediaIDsJSON: String
    @NSManaged public var tags: NSSet?
    @NSManaged public var tagsJSON: String
    @NSManaged public var type: String
    @NSManaged public var updatedAt: Date?
    @NSManaged public var uuid: UUID?
}

@objc(CDCard)
public class CDCard: CDManagedObject {
    @NSManaged public var createdAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var note: CDNote?
    @NSManaged public var templateKey: String
    @NSManaged public var updatedAt: Date?
    @NSManaged public var uuid: UUID?
}

@objc(CDTag)
public class CDTag: CDManagedObject {
    @NSManaged public var createdAt: Date?
    @NSManaged public var deletedAt: Date?
    @NSManaged public var name: String
    @NSManaged public var normalizedName: String
    @NSManaged public var notes: NSSet?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var uuid: UUID?
}

@objc(CDSchedule)
public class CDSchedule: CDManagedObject {
    @NSManaged public var cardUUID: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var deckUUID: UUID?
    @NSManaged public var difficulty: Double
    @NSManaged public var buriedUntil: Date?
    @NSManaged public var dueAt: Date?
    @NSManaged public var lastReviewedAt: Date?
    @NSManaged public var lapses: Int32
    @NSManaged public var reps: Int32
    @NSManaged public var stability: Double
    @NSManaged public var stateRaw: Int16
    @NSManaged public var suspendedAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var uuid: UUID?
}

@objc(CDReviewLog)
public class CDReviewLog: CDManagedObject {
    @NSManaged public var cardUUID: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var deckUUID: UUID?
    @NSManaged public var durationMs: Int32
    @NSManaged public var elapsedDays: Int32
    @NSManaged public var gradeRaw: Int16
    @NSManaged public var prevDifficulty: Double
    @NSManaged public var prevDueAt: Date?
    @NSManaged public var prevLapses: Int32
    @NSManaged public var prevLastReviewedAt: Date?
    @NSManaged public var prevReps: Int32
    @NSManaged public var prevStability: Double
    @NSManaged public var prevStateRaw: Int16
    @NSManaged public var revokedAt: Date?
    @NSManaged public var reviewedAt: Date?
    @NSManaged public var scheduledDays: Int32
    @NSManaged public var updatedAt: Date?
    @NSManaged public var uuid: UUID?
}

@objc(CDImportBatch)
public class CDImportBatch: CDManagedObject {
    @NSManaged public var createdAt: Date?
    @NSManaged public var createdNoteUUIDsJSON: String
    @NSManaged public var destinationDeckUUID: UUID?
    @NSManaged public var destinationWasNewDeck: Bool
    @NSManaged public var duplicateRowsJSON: String
    @NSManaged public var importedAt: Date?
    @NSManaged public var rejectedRowsJSON: String
    @NSManaged public var sourceName: String
    @NSManaged public var undoneAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var uuid: UUID?
}

@objc(CDStudySettings)
public class CDStudySettings: CDManagedObject {
    @NSManaged public var appearanceRaw: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var newPerDay: Int32
    @NSManaged public var reminderEnabled: Bool
    @NSManaged public var reminderHour: Int16
    @NSManaged public var reminderMinute: Int16
    @NSManaged public var reviewsPerDay: Int32
    @NSManaged public var singletonKey: String
    @NSManaged public var updatedAt: Date?
    @NSManaged public var uuid: UUID?
}

extension CDDeck {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDDeck> {
        NSFetchRequest<CDDeck>(entityName: "CDDeck")
    }
}

extension CDNote {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDNote> {
        NSFetchRequest<CDNote>(entityName: "CDNote")
    }
}

extension CDCard {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDCard> {
        NSFetchRequest<CDCard>(entityName: "CDCard")
    }
}

extension CDTag {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTag> {
        NSFetchRequest<CDTag>(entityName: "CDTag")
    }
}

extension CDSchedule {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDSchedule> {
        NSFetchRequest<CDSchedule>(entityName: "CDSchedule")
    }
}

extension CDReviewLog {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDReviewLog> {
        NSFetchRequest<CDReviewLog>(entityName: "CDReviewLog")
    }
}

extension CDImportBatch {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDImportBatch> {
        NSFetchRequest<CDImportBatch>(entityName: "CDImportBatch")
    }
}

extension CDStudySettings {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDStudySettings> {
        NSFetchRequest<CDStudySettings>(entityName: "CDStudySettings")
    }
}
