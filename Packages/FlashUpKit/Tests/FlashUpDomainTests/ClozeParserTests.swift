import Foundation
import Testing
@testable import FlashUpDomain

/// Bead fu-04a (source B2.1): exhaustive coverage of the A3.4 grammar.
@Suite("Cloze parser")
struct ClozeParserTests {
    // MARK: - Well-formed input

    @Test("A single deletion yields one group")
    func singleDeletion() {
        let result = ClozeParser.parse("Il cuore ha {{c1::quattro}} camere.")

        #expect(result.issues.isEmpty)
        #expect(result.deletions.count == 1)
        #expect(result.deletions.first?.group == 1)
        #expect(result.deletions.first?.text == "quattro")
        #expect(result.deletions.first?.hint == nil)
        #expect(result.groups == [1])
    }

    @Test("Multiple distinct groups each generate a card")
    func multipleGroups() {
        let result = ClozeParser.parse("{{c1::Roma}} è la capitale d'{{c3::Italia}}.")

        #expect(result.deletions.count == 2)
        #expect(result.groups == [1, 3])
    }

    @Test("A repeated group is masked in both places on the same card")
    func repeatedGroup() {
        let source = "{{c1::ATP}} si forma e {{c1::ATP}} si consuma."
        let result = ClozeParser.parse(source)

        #expect(result.deletions.count == 2)
        #expect(result.groups == [1])
        #expect(ClozeParser.render(source, maskGroup: 1) == "[...] si forma e [...] si consuma.")
    }

    @Test("A hint is parsed and rendered in place of the mask")
    func hintIsParsed() {
        let source = "La mitosi ha {{c1::quattro::numero}} fasi."
        let result = ClozeParser.parse(source)

        #expect(result.deletions.first?.text == "quattro")
        #expect(result.deletions.first?.hint == "numero")
        #expect(ClozeParser.render(source, maskGroup: 1) == "La mitosi ha [numero] fasi.")
    }

    @Test("Only the first :: splits text from hint; the rest belongs to the hint")
    func hintKeepsLaterSeparators() {
        let result = ClozeParser.parse("{{c1::testo::a::b}}")

        #expect(result.deletions.first?.text == "testo")
        #expect(result.deletions.first?.hint == "a::b")
    }

    @Test("Multi-digit group numbers are supported")
    func multiDigitGroups() {
        #expect(ClozeParser.groups(in: "{{c12::x}} {{c7::y}}") == [12, 7])
    }

    @Test("Unicode text and hints survive intact")
    func unicodeIsPreserved() {
        let source = "Il simbolo è {{c1::α-elica::lettera greca}} 😀"
        let result = ClozeParser.parse(source)

        #expect(result.deletions.first?.text == "α-elica")
        #expect(result.deletions.first?.hint == "lettera greca")
        #expect(ClozeParser.render(source, maskGroup: nil) == "Il simbolo è α-elica 😀")
    }

    @Test("Nested braces inside the text are taken literally up to the first }}")
    func nestedBracesAreLiteral() {
        let result = ClozeParser.parse("{{c1::f{x}}}")

        #expect(result.issues.isEmpty)
        #expect(result.deletions.first?.text == "f{x")
    }

    // MARK: - Rendering

    @Test("Masking one group reveals every other group")
    func maskingRevealsOtherGroups() {
        let source = "{{c1::Roma}} è la capitale d'{{c2::Italia}}."

        #expect(ClozeParser.render(source, maskGroup: 1) == "[...] è la capitale d'Italia.")
        #expect(ClozeParser.render(source, maskGroup: 2) == "Roma è la capitale d'[...].")
    }

    @Test("Passing no group reveals the whole sentence")
    func renderingWithoutMaskRevealsEverything() {
        let source = "{{c1::Roma}} è la capitale d'{{c2::Italia}}."

        #expect(ClozeParser.render(source, maskGroup: nil) == "Roma è la capitale d'Italia.")
    }

    @Test("Masking a group that does not exist changes nothing but still unwraps")
    func maskingAnAbsentGroup() {
        #expect(ClozeParser.render("{{c1::Roma}}", maskGroup: 9) == "Roma")
    }

    @Test("Text with no deletion is returned unchanged")
    func plainTextIsUnchanged() {
        let source = "Nessuna cancellazione qui."

        #expect(ClozeParser.render(source, maskGroup: 1) == source)
        #expect(ClozeParser.groups(in: source).isEmpty)
        #expect(ClozeParser.hasValidDeletion(source) == false)
    }

    // MARK: - Malformed input

    @Test("An unclosed deletion is reported and left as literal text")
    func unclosedDeletion() {
        let source = "Testo {{c1::senza chiusura"
        let result = ClozeParser.parse(source)

        #expect(result.deletions.isEmpty)
        #expect(result.issues.map(\.kind) == [.unclosedDeletion])
        #expect(ClozeParser.render(source, maskGroup: 1) == source)
    }

    @Test("Group zero is rejected")
    func groupZeroIsRejected() {
        let result = ClozeParser.parse("{{c0::x}}")

        #expect(result.deletions.isEmpty)
        #expect(result.issues.map(\.kind) == [.invalidGroupNumber(0)])
    }

    @Test("An empty text is rejected")
    func emptyTextIsRejected() {
        let result = ClozeParser.parse("{{c1::}}")

        #expect(result.deletions.isEmpty)
        #expect(result.issues.map(\.kind) == [.emptyText])
    }

    @Test("A missing group number is rejected")
    func missingGroupNumberIsRejected() {
        let result = ClozeParser.parse("{{c::x}}")

        #expect(result.deletions.isEmpty)
        #expect(result.issues.map(\.kind) == [.missingGroupNumber])
    }

    @Test("A non-ASCII digit is not accepted as a group number")
    func nonASCIIDigitIsRejected() {
        let result = ClozeParser.parse("{{c١::x}}")

        #expect(result.deletions.isEmpty)
        #expect(result.issues.map(\.kind) == [.missingGroupNumber])
    }

    @Test("A missing :: separator is rejected")
    func missingSeparatorIsRejected() {
        let result = ClozeParser.parse("{{c1 testo}}")

        #expect(result.deletions.isEmpty)
        #expect(result.issues.map(\.kind) == [.missingSeparator])
    }

    @Test("A malformed deletion does not stop the valid ones after it")
    func parsingContinuesAfterAnIssue() {
        let result = ClozeParser.parse("{{c0::x}} e {{c1::valido}}")

        #expect(result.deletions.count == 1)
        #expect(result.deletions.first?.text == "valido")
        #expect(result.issues.count == 1)
        #expect(result.groups == [1])
    }

    @Test("A note is valid for cloze only when at least one deletion parses")
    func validityMirrorsTheParsedDeletions() {
        #expect(ClozeParser.hasValidDeletion("{{c1::x}}"))
        #expect(ClozeParser.hasValidDeletion("{{c0::x}}") == false)
        #expect(ClozeParser.hasValidDeletion("{{c1::senza chiusura") == false)
    }
}
