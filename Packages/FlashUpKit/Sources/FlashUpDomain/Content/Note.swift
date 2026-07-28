import Foundation

/// One authored item. A note produces one or more cards (spec §A3.1).
public struct Note: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var deckID: UUID
    public var type: NoteType
    public var front: String
    /// Optional for cloze notes, where it holds an extra explanation.
    public var back: String?
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        deckID: UUID,
        type: NoteType,
        front: String,
        back: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.deckID = deckID
        self.type = type
        self.front = front
        self.back = back
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
