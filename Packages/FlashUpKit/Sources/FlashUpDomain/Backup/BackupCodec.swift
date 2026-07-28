import Foundation

/// The versioned backup document (spec §A10).
///
/// Pure `Codable` structs living in Domain: the format is a contract with the user's own
/// files, so it must be describable and testable without any storage layer.
public struct BackupDocument: Equatable, Codable, Sendable {
    public static let formatName = "flashup-backup"
    public static let currentVersion = 1

    public var format: String
    public var formatVersion: Int
    public var appVersion: String
    public var exportedAt: Date
    public var settings: StudySettings
    public var decks: [BackupDeck]
    public var schedules: [BackupSchedule]
    public var reviewLogs: [BackupReviewLog]

    public init(
        format: String = BackupDocument.formatName,
        formatVersion: Int = BackupDocument.currentVersion,
        appVersion: String,
        exportedAt: Date,
        settings: StudySettings,
        decks: [BackupDeck],
        schedules: [BackupSchedule],
        reviewLogs: [BackupReviewLog]
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.decks = decks
        self.schedules = schedules
        self.reviewLogs = reviewLogs
    }
}

public struct BackupDeck: Equatable, Codable, Sendable {
    /// `sharedSnapshot` decks restore as personal ones: a backup never recreates a group.
    public enum Origin: String, Codable, Sendable {
        case personal
        case sharedSnapshot
    }

    public var uuid: UUID
    public var name: String
    public var origin: Origin
    public var createdAt: Date
    public var notes: [BackupNote]

    public init(uuid: UUID, name: String, origin: Origin, createdAt: Date, notes: [BackupNote]) {
        self.uuid = uuid
        self.name = name
        self.origin = origin
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

    public init(
        uuid: UUID,
        type: NoteType,
        front: String,
        back: String?,
        tags: [String],
        createdAt: Date,
        updatedAt: Date,
        cards: [BackupCard]
    ) {
        self.uuid = uuid
        self.type = type
        self.front = front
        self.back = back
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cards = cards
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
            suspendedAt: suspendedAt
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
                lastReviewedAt: nil,
                reps: 0,
                lapses: 0
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
