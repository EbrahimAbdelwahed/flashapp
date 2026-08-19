import Foundation

/// The versioned backup document (spec §A10).
///
/// Pure `Codable` structs living in Domain: the format is a contract with the user's own
/// files, so it must be describable and testable without any storage layer.
public struct BackupDocument: Equatable, Codable, Sendable {
    public static let formatName = "flashup-backup"
    /// Version 2 adds attachment references and the `MediaAsset` records describing them
    /// (ADR-004 §7). Version 1 documents still decode: the new fields default to empty.
    public static let currentVersion = 2

    public var format: String
    public var formatVersion: Int
    public var appVersion: String
    public var exportedAt: Date
    public var settings: StudySettings
    public var decks: [BackupDeck]
    public var schedules: [BackupSchedule]
    public var reviewLogs: [BackupReviewLog]
    /// Attachment records. **The bytes are deliberately not here**: a media-heavy collection
    /// would produce hundreds of megabytes of base64 in one JSON file, slow to write and
    /// prone to failing on the devices that need a backup most. A restore whose blob is
    /// missing renders a placeholder rather than losing the note (ADR-004 §7).
    public var media: [MediaAsset]

    public init(
        format: String = BackupDocument.formatName,
        formatVersion: Int = BackupDocument.currentVersion,
        appVersion: String,
        exportedAt: Date,
        settings: StudySettings,
        decks: [BackupDeck],
        schedules: [BackupSchedule],
        reviewLogs: [BackupReviewLog],
        media: [MediaAsset] = []
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.decks = decks
        self.schedules = schedules
        self.reviewLogs = reviewLogs
        self.media = media
    }

    /// Every attachment the exported notes point at.
    ///
    /// The library does not know about the media store — it holds ids, not blobs — so the
    /// composition root fills `media` in from this set. That keeps the two subsystems
    /// independent instead of making the repository depend on storage it does not own.
    public var referencedMediaIDs: Set<UUID> {
        Set(decks.flatMap { $0.notes.flatMap(\.mediaIDs) })
    }

    public func addingMedia(_ assets: [MediaAsset]) -> BackupDocument {
        var copy = self
        copy.media = assets
        return copy
    }

    /// Hand-rolled so a version 1 document, which has no `media` key, still decodes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        settings = try container.decode(StudySettings.self, forKey: .settings)
        decks = try container.decode([BackupDeck].self, forKey: .decks)
        schedules = try container.decode([BackupSchedule].self, forKey: .schedules)
        reviewLogs = try container.decode([BackupReviewLog].self, forKey: .reviewLogs)
        media = try container.decodeIfPresent([MediaAsset].self, forKey: .media) ?? []
    }
}

public struct BackupDeck: Equatable, Codable, Sendable {
    public var uuid: UUID
    public var name: String
    public var createdAt: Date
    public var notes: [BackupNote]

    public init(uuid: UUID, name: String, createdAt: Date, notes: [BackupNote]) {
        self.uuid = uuid
        self.name = name
        self.createdAt = createdAt
        self.notes = notes
    }
}

public struct BackupNote: Equatable, Codable, Sendable {
    public var uuid: UUID
    public var type: NoteType
    public var front: String
    public var back: String?
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var cards: [BackupCard]
    /// Attachments referenced from `front`/`back`. Absent in version 1 documents.
    public var mediaIDs: [UUID]

    public init(
        uuid: UUID,
        type: NoteType,
        front: String,
        back: String?,
        tags: [String],
        createdAt: Date,
        updatedAt: Date,
        cards: [BackupCard],
        mediaIDs: [UUID] = []
    ) {
        self.uuid = uuid
        self.type = type
        self.front = front
        self.back = back
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cards = cards
        self.mediaIDs = mediaIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(UUID.self, forKey: .uuid)
        type = try container.decode(NoteType.self, forKey: .type)
        front = try container.decode(String.self, forKey: .front)
        back = try container.decodeIfPresent(String.self, forKey: .back)
        tags = try container.decode([String].self, forKey: .tags)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        cards = try container.decode([BackupCard].self, forKey: .cards)
        mediaIDs = try container.decodeIfPresent([UUID].self, forKey: .mediaIDs) ?? []
    }
}

public struct BackupCard: Equatable, Codable, Sendable {
    public var uuid: UUID
    public var templateKey: String

    public init(uuid: UUID, templateKey: String) {
        self.uuid = uuid
        self.templateKey = templateKey
    }
}

public struct BackupSchedule: Equatable, Codable, Sendable {
    public var cardUUID: UUID
    public var state: Int
    public var stability: Double
    public var difficulty: Double
    public var dueAt: Date
    public var reps: Int
    public var lapses: Int
    public var suspendedAt: Date?
    /// Optional, so backups written before burying existed still decode.
    public var buriedUntil: Date?
    public var lastReviewedAt: Date?

    public init(cardUUID: UUID, state: ReviewState) {
        self.cardUUID = cardUUID
        self.state = Int(state.state.rawValue)
        self.stability = state.stability
        self.difficulty = state.difficulty
        self.dueAt = state.dueAt
        self.reps = state.reps
        self.lapses = state.lapses
        self.suspendedAt = state.suspendedAt
        self.buriedUntil = state.buriedUntil
        self.lastReviewedAt = state.lastReviewedAt
    }

    public var reviewState: ReviewState? {
        guard let scheduleState = ScheduleState(rawValue: Int16(state)) else { return nil }
        return ReviewState(
            state: scheduleState,
            stability: stability,
            difficulty: difficulty,
            dueAt: dueAt,
            lastReviewedAt: lastReviewedAt,
            reps: reps,
            lapses: lapses,
            suspendedAt: suspendedAt,
            buriedUntil: buriedUntil
        )
    }
}

public struct BackupReviewLog: Equatable, Codable, Sendable {
    public var uuid: UUID
    public var cardUUID: UUID
    public var deckUUID: UUID
    public var reviewedAt: Date
    public var grade: Int
    public var durationMs: Int
    public var prevState: Int
    public var prevStability: Double
    public var prevDifficulty: Double
    public var prevDueAt: Date?
    /// Optional for backward-compatible decoding of backups written before complete
    /// previous-state persistence was added.
    public var prevLastReviewedAt: Date?
    public var prevReps: Int?
    public var prevLapses: Int?
    public var scheduledDays: Int
    public var elapsedDays: Int
    public var revokedAt: Date?

    public init(log: ReviewLog) {
        self.uuid = log.id
        self.cardUUID = log.cardID
        self.deckUUID = log.deckID
        self.reviewedAt = log.reviewedAt
        self.grade = Int(log.grade.rawValue)
        self.durationMs = log.durationMs
        self.prevState = Int(log.previous.state.rawValue)
        self.prevStability = log.previous.stability
        self.prevDifficulty = log.previous.difficulty
        self.prevDueAt = log.previous.dueAt
        self.prevLastReviewedAt = log.previous.lastReviewedAt
        self.prevReps = log.previous.reps
        self.prevLapses = log.previous.lapses
        self.scheduledDays = log.scheduledDays
        self.elapsedDays = log.elapsedDays
        self.revokedAt = log.revokedAt
    }

    public var reviewLog: ReviewLog? {
        guard let grade = Grade(rawValue: Int16(grade)),
              let state = ScheduleState(rawValue: Int16(prevState)),
              let dueAt = prevDueAt
        else { return nil }

        return ReviewLog(
            id: uuid,
            cardID: cardUUID,
            deckID: deckUUID,
            reviewedAt: reviewedAt,
            durationMs: durationMs,
            grade: grade,
            previous: ReviewState(
                state: state,
                    stability: prevStability,
                    difficulty: prevDifficulty,
                    dueAt: dueAt,
                    lastReviewedAt: prevLastReviewedAt,
                    reps: prevReps ?? 0,
                    lapses: prevLapses ?? 0
            ),
            scheduledDays: scheduledDays,
            elapsedDays: elapsedDays,
            revokedAt: revokedAt
        )
    }
}

public enum BackupError: Error, Equatable, Sendable {
    case notAFlashUpBackup
    /// Written by a newer app: refusing beats silently dropping fields the user can see.
    case unsupportedVersion(found: Int, supported: Int)
    case corrupted
}

/// Encodes and decodes the backup document.
public enum BackupCodec {
    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let document: BackupDocument
        do {
            document = try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw BackupError.corrupted
        }

        guard document.format == BackupDocument.formatName else {
            throw BackupError.notAFlashUpBackup
        }
        guard document.formatVersion <= BackupDocument.currentVersion else {
            throw BackupError.unsupportedVersion(
                found: document.formatVersion,
                supported: BackupDocument.currentVersion
            )
        }
        return document
    }
}
