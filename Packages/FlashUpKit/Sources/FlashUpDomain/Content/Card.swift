import Foundation

/// What `CardGenerator` derives from a note, before any identity is assigned.
///
/// `templateKey` is the stable generation identity (spec §A3.2): `"forward"`, `"reverse"`
/// or `"cloze:<n>"`. A card's `uuid` is created once per (note, templateKey) and never
/// regenerated, which is what preserves private FSRS progress across content edits.
public struct CardTemplate: Equatable, Sendable {
    public let templateKey: String
    /// Study-ready prompt, with the cloze group already masked where applicable.
    public let front: String
    public let back: String

    public init(templateKey: String, front: String, back: String) {
        self.templateKey = templateKey
        self.front = front
        self.back = back
    }
}

/// A generated card with its persisted identity attached.
public struct Card: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let deckID: UUID
    public let templateKey: String
    public let front: String
    public let back: String

    public init(id: UUID = UUID(), noteID: UUID, deckID: UUID, template: CardTemplate) {
        self.id = id
        self.noteID = noteID
        self.deckID = deckID
        self.templateKey = template.templateKey
        self.front = template.front
        self.back = template.back
    }
}
