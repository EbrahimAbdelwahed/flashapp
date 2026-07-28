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
    /// Optional explanation shown under the answer, never merged into it.
    public let extra: String?
    /// Present only for cloze cards, so the study screen can fill the blank in place
    /// instead of repeating the sentence.
    public let cloze: ClozeContext?

    public init(
        templateKey: String,
        front: String,
        back: String,
        extra: String? = nil,
        cloze: ClozeContext? = nil
    ) {
        self.templateKey = templateKey
        self.front = front
        self.back = back
        self.extra = extra
        self.cloze = cloze
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
    public let extra: String?
    public let cloze: ClozeContext?

    public init(id: UUID = UUID(), noteID: UUID, deckID: UUID, template: CardTemplate) {
        self.id = id
        self.noteID = noteID
        self.deckID = deckID
        self.templateKey = template.templateKey
        self.front = template.front
        self.back = template.back
        self.extra = template.extra
        self.cloze = template.cloze
    }
}
