import Testing
@testable import FlashUpDomain

@Suite("Anki HTML to Flash Up text")
struct HTMLTextExtractorTests {
    @Test("Plain text passes through unchanged")
    func plainText() {
        #expect(HTMLTextExtractor.text("Roma") == "Roma")
    }

    @Test("Tags that end a line become newlines", arguments: [
        ("uno<br>due", "uno\ndue"),
        ("uno<br/>due", "uno\ndue"),
        ("<div>uno</div><div>due</div>", "uno\ndue"),
        ("<p>uno</p><p>due</p>", "uno\ndue")
    ])
    func lineBreaks(_ html: String, _ expected: String) {
        #expect(HTMLTextExtractor.text(html) == expected)
    }

    @Test("Emphasis survives as Markdown", arguments: [
        ("Cos'è il <b>DNA</b>?", "Cos'è il **DNA**?"),
        ("Cos'è il <strong>DNA</strong>?", "Cos'è il **DNA**?"),
        ("Il <i>corsivo</i>", "Il *corsivo*"),
        ("Il <em>corsivo</em>", "Il *corsivo*")
    ])
    func emphasis(_ html: String, _ expected: String) {
        #expect(HTMLTextExtractor.text(html) == expected)
    }

    @Test("Styling tags we do not keep are dropped, not their content")
    func unknownTagsDropped() {
        #expect(HTMLTextExtractor.text("<span style=\"color:red\">rosso</span>") == "rosso")
        #expect(HTMLTextExtractor.text("<font color=\"#ff0000\">rosso</font>") == "rosso")
    }

    @Test("Entities are decoded", arguments: [
        ("Watson &amp; Crick", "Watson & Crick"),
        ("&lt;tag&gt;", "<tag>"),
        ("a&nbsp;b", "a b"),
        ("&mdash;", "—"),
        ("&#233;", "é"),
        ("&#x00e9;", "é")
    ])
    func entities(_ html: String, _ expected: String) {
        #expect(HTMLTextExtractor.text(html) == expected)
    }

    @Test("An unknown entity is kept verbatim rather than deleted")
    func unknownEntity() {
        #expect(HTMLTextExtractor.text("&fnord;") == "&fnord;")
    }

    /// A stray ampersand must not swallow the rest of the field looking for a semicolon.
    @Test("A bare ampersand stays an ampersand")
    func bareAmpersand() {
        #expect(HTMLTextExtractor.text("Tizio & Caio e poi una frase lunga; con un punto e virgola")
            == "Tizio & Caio e poi una frase lunga; con un punto e virgola")
    }

    @Test("An unterminated tag is treated as literal text, as a browser would")
    func unterminatedTag() {
        #expect(HTMLTextExtractor.text("2 < 3") == "2 < 3")
    }

    /// The rule that must never break: Anki cloze syntax is already what `ClozeParser` wants.
    @Test("Cloze syntax is left completely alone")
    func clozeUntouched() {
        let source = "La {{c1::glicolisi}} avviene nel {{c2::citoplasma}}"
        #expect(HTMLTextExtractor.text(source) == source)
        #expect(ClozeParser.hasValidDeletion(HTMLTextExtractor.text(source)))
    }

    @Test("Cloze survives alongside HTML")
    func clozeWithHTML() {
        let extracted = HTMLTextExtractor.text("<div>La {{c1::<b>glicolisi</b>}} avviene</div>")
        #expect(extracted == "La {{c1::**glicolisi**}} avviene")
        #expect(ClozeParser.hasValidDeletion(extracted))
    }

    @Test("Whitespace runs collapse and the result is trimmed")
    func whitespace() {
        #expect(HTMLTextExtractor.text("  troppi     spazi  ") == "troppi spazi")
        #expect(HTMLTextExtractor.text("<div>uno</div><div></div><div></div><div>due</div>") == "uno\ndue")
    }

    // MARK: - Media references

    @Test("An image reference is captured and removed from the text")
    func image() {
        let extraction = HTMLTextExtractor.extract("Che colore? <img src=\"rossa.png\">")
        #expect(extraction.text == "Che colore?")
        #expect(extraction.imageFilenames == ["rossa.png"])
        #expect(extraction.hasMedia)
    }

    @Test("Image src is read with single quotes and unquoted too", arguments: [
        "<img src='a.png'>", "<img src=a.png>", "<img class=\"x\" src=\"a.png\">"
    ])
    func imageQuoting(_ html: String) {
        #expect(HTMLTextExtractor.extract(html).imageFilenames == ["a.png"])
    }

    @Test("A sound reference is captured and removed from the text")
    func audio() {
        let extraction = HTMLTextExtractor.extract("Rosso [sound:suono.wav]")
        #expect(extraction.text == "Rosso")
        #expect(extraction.audioFilenames == ["suono.wav"])
    }

    @Test("Square brackets that are not a sound reference stay in the text")
    func bracketsAreNotAlwaysSound() {
        let extraction = HTMLTextExtractor.extract("Vedi [nota 3] a pagina 7")
        #expect(extraction.text == "Vedi [nota 3] a pagina 7")
        #expect(!extraction.hasMedia)
    }

    @Test("Several attachments in one field are all captured, in order")
    func multipleMedia() {
        let extraction = HTMLTextExtractor.extract("<img src=\"a.png\"> e <img src=\"b.png\"> [sound:c.mp3]")
        #expect(extraction.imageFilenames == ["a.png", "b.png"])
        #expect(extraction.audioFilenames == ["c.mp3"])
        #expect(extraction.text == "e")
    }

    @Test("An empty field yields empty text and no media")
    func empty() {
        let extraction = HTMLTextExtractor.extract("")
        #expect(extraction.text.isEmpty)
        #expect(!extraction.hasMedia)
    }
}
