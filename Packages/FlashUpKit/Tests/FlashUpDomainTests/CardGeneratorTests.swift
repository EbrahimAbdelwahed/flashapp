import Foundation
import Testing
@testable import FlashUpDomain

/// Bead fu-04b (source B2.2, domain half): the generation table of spec §A3.1.
@Suite("Card generator")
struct CardGeneratorTests {
    private let deckID = UUID()

    private func note(_ type: NoteType, front: String, back: String? = nil) -> Note {
        Note(deckID: deckID, type: type, front: front, back: back)
    }

    @Test("A basic note produces one forward card")
    func basicProducesOneCard() {
        let cards = CardGenerator.generate(note(.basic, front: "Ciao", back: "Hello"))

        #expect(cards.map(\.templateKey) == ["forward"])
        #expect(cards.first?.front == "Ciao")
        #expect(cards.first?.back == "Hello")
    }

    @Test("A reversed note produces both directions")
    func reversedProducesTwoCards() {
        let cards = CardGenerator.generate(note(.reversed, front: "Ciao", back: "Hello"))

        #expect(cards.map(\.templateKey) == ["forward", "reverse"])
        #expect(cards.last?.front == "Hello")
        #expect(cards.last?.back == "Ciao")
    }

    @Test("A cloze note produces one card per distinct group, in ascending order")
    func clozeProducesOneCardPerGroup() {
        let cards = CardGenerator.generate(
            note(.cloze, front: "{{c3::Italia}} ha {{c1::venti}} regioni")
        )

        #expect(cards.map(\.templateKey) == ["cloze:1", "cloze:3"])
    }

    @Test("A cloze card masks only its own group")
    func clozeMasksOnlyItsGroup() {
        let cards = CardGenerator.generate(
            note(.cloze, front: "{{c1::Roma}} è la capitale d'{{c2::Italia}}")
        )

        #expect(cards.first?.front == "[...] è la capitale d'Italia")
        #expect(cards.last?.front == "Roma è la capitale d'[...]")
    }

    @Test("A repeated group stays a single card with both places masked")
    func repeatedGroupStaysOneCard() {
        let cards = CardGenerator.generate(note(.cloze, front: "{{c1::ATP}} e {{c1::ATP}}"))

        #expect(cards.count == 1)
        #expect(cards.first?.front == "[...] e [...]")
    }

    @Test("The cloze answer reveals everything and appends the note's back")
    func clozeBackRevealsAndExplains() {
        let cards = CardGenerator.generate(
            note(.cloze, front: "{{c1::Roma}} è la capitale", back: "Dal 1871")
        )

        #expect(cards.first?.back == "Roma è la capitale\n\nDal 1871")
    }

    @Test("A cloze answer with no extra explanation is just the revealed sentence")
    func clozeBackWithoutExplanation() {
        let cards = CardGenerator.generate(note(.cloze, front: "{{c1::Roma}} è la capitale"))

        #expect(cards.first?.back == "Roma è la capitale")
    }

    @Test("A note whose cloze deletions are all malformed produces no cards")
    func malformedClozeProducesNothing() {
        #expect(CardGenerator.generate(note(.cloze, front: "{{c0::x}}")).isEmpty)
    }

    @Test("Template keys survive an edit that keeps the same groups")
    func editingTextKeepsTemplateKeys() {
        let before = CardGenerator.generate(note(.cloze, front: "{{c1::Roma}} è la capitale"))
        let after = CardGenerator.generate(note(.cloze, front: "{{c1::Roma}} è ancora la capitale"))

        #expect(before.map(\.templateKey) == after.map(\.templateKey))
    }
}
