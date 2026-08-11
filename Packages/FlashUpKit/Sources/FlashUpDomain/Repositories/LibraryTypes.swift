import Foundation

/// What the editor submits. Identity is optional: absent means "create".
public struct NoteDraft: Equatable, Sendable {
    public var id: UUID?
    public var deckID: UUID
    public var type: NoteType
    public var front: String
    public var back: String?
    public var tags: [String]

    public init(
        id: UUID? = nil,
        deckID: UUID,
        type: NoteType,
        front: String,
        back: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.deckID = deckID
        self.type = type
        self.front = front
        self.back = back
        self.tags = tags
    }

    public init(note: Note) {
        self.init(
            id: note.id,
            deckID: note.deckID,
            type: note.type,
            front: note.front,
            back: note.back,
            tags: note.tags
        )
    }

    /// A note needs a front, and a cloze note needs at least one deletion, or it would
    /// generate no cards at all.
    public var isValid: Bool {
        guard !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch type {
        case .basic, .reversed:
            return !(back ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .cloze:
            return ClozeParser.hasValidDeletion(front)
        }
    }
}

/// Library filters (spec §A11.5).
public struct SearchFilters: Equatable, Sendable {
    public enum State: String, CaseIterable, Sendable {
        case any, new, due, suspended, buried
    }

    public enum Sorting: String, CaseIterable, Sendable {
        case updated, name, created
    }

    public var text: String
    public var type: NoteType?
    public var state: State
    public var sorting: Sorting

    public static let none = SearchFilters(text: "", type: nil, state: .any, sorting: .updated)

    public init(text: String = "", type: NoteType? = nil, state: State = .any, sorting: Sorting = .updated) {
        self.text = text
        self.type = type
        self.state = state
        self.sorting = sorting
    }

    public var isActive: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || type != nil || state != .any
    }
}

/// A note plus the state the list rows display.
public struct NoteSummary: Identifiable, Equatable, Sendable {
    public let note: Note
    public let cardCount: Int
    public let dueCount: Int
    public let isNew: Bool
    /// True when *any* of the note's cards is suspended, which is deliberately the same
    /// question the `.suspended` filter asks. A note with one card hidden and one not still
    /// has something to resume, and a badge that appeared only once every card was hidden
    /// would leave rows in the filtered list wearing no badge at all.
    public let isSuspended: Bool
    /// True when any of the note's cards is buried right now.
    public let isBuried: Bool

    public var id: UUID { note.id }

    /// Whether the row has anything for the resume action to lift.
    public var isHidden: Bool { isSuspended || isBuried }

    public init(
        note: Note,
        cardCount: Int,
        dueCount: Int,
        isNew: Bool,
        isSuspended: Bool,
        isBuried: Bool = false
    ) {
        self.note = note
        self.cardCount = cardCount
        self.dueCount = dueCount
        self.isNew = isNew
        self.isSuspended = isSuspended
        self.isBuried = isBuried
    }
}

/// Everything the card info sheet shows, in one read.
///
/// Deliberately carries the raw `ReviewState` rather than pre-formatted strings: what a card
/// info screen chooses to show is an interface decision, and the FSRS internals
/// (stability, difficulty) are in here without any obligation to display them.
public struct CardInfo: Identifiable, Equatable, Sendable {
    public var id: UUID { card.id }
    public let card: Card
    public let schedule: ReviewState?
    /// The card's surviving answers, newest first. Revoked logs are already filtered out.
    public let logs: [ReviewLog]

    public init(card: Card, schedule: ReviewState?, logs: [ReviewLog]) {
        self.card = card
        self.schedule = schedule
        self.logs = logs
    }

    public var isNew: Bool { schedule?.isUnseen ?? true }
    public var isSuspended: Bool { schedule?.isSuspended ?? false }
    public func isBuried(at now: Date) -> Bool { schedule?.isBuried(at: now) ?? false }
}

/// One import, kept so it can be undone (spec §A9.2 step 5).
public struct ImportBatch: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceName: String
    public let importedAt: Date
    public let destinationDeckID: UUID
    public let destinationWasNewDeck: Bool
    public let createdNoteIDs: [UUID]
    public var undoneAt: Date?

    public init(
        id: UUID = UUID(),
        sourceName: String,
        importedAt: Date,
        destinationDeckID: UUID,
        destinationWasNewDeck: Bool,
        createdNoteIDs: [UUID],
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.sourceName = sourceName
        self.importedAt = importedAt
        self.destinationDeckID = destinationDeckID
        self.destinationWasNewDeck = destinationWasNewDeck
        self.createdNoteIDs = createdNoteIDs
        self.undoneAt = undoneAt
    }
}

/// What a restore actually did — shown to the user instead of a silent "done".
public struct RestoreSummary: Equatable, Sendable {
    public let decksAdded: Int
    public let notesAdded: Int
    public let notesSkipped: Int
    public let logsAdded: Int

    public init(decksAdded: Int, notesAdded: Int, notesSkipped: Int, logsAdded: Int) {
        self.decksAdded = decksAdded
        self.notesAdded = notesAdded
        self.notesSkipped = notesSkipped
        self.logsAdded = logsAdded
    }
}

/// iCloud availability as the interface needs to show it.
///
/// Sync is not wired yet: `fu-01-store-spike` and `fu-04-data-core` supply the real values.
/// The interface is built against the full set of states so none of them is an afterthought.
public enum SyncStatus: Equatable, Sendable {
    case syncing
    case upToDate(lastSyncedAt: Date?)
    case offline
    case accountUnavailable
    case failed(reason: String)
}
