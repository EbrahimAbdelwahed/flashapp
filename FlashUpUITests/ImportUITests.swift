import UIKit
import XCTest

/// The three ways cards get into the app, end to end.
final class ImportUITests: UITestCase {
    func testImportFlowFromTheBuiltInExample() {
        skipOnboarding()
        openTab("tab.library")

        app.buttons["library.import"].tap()
        let sample = app.buttons["import.sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5), "the import flow did not open")
        sample.tap()

        let confirm = app.buttons["import.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the import preview did not appear")
        confirm.tap()

        // The example deliberately contains one bad row, so the result is 3 of 4.
        XCTAssertTrue(
            app.buttons["import.undo"].waitForExistence(timeout: 10),
            "the import did not complete"
        )
    }

    /// The journey the prompt card sets up: the assistant answers with a code block, the user
    /// copies it, and the cards are in the app without a file ever existing.
    func testImportFromTheClipboard() {
        UIPasteboard.general.string = """
        ```csv
        type,front,back,tags
        basic,Che cos'è la glicolisi?,La via che scinde il glucosio,biochimica
        reversed,Liver,Fegato,inglese
        ```
        """

        skipOnboarding()
        openTab("tab.library")
        app.buttons["library.import"].tap()

        let paste = pasteButton()
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "the import flow offers no way to paste")
        paste.tap()

        let confirm = app.buttons["import.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the pasted CSV produced no preview")
        confirm.tap()

        XCTAssertTrue(
            app.buttons["import.undo"].waitForExistence(timeout: 10),
            "the clipboard import did not complete"
        )
    }

    func testImportOffersACopyablePromptForChatGPT() {
        skipOnboarding()
        openTab("tab.library")

        app.buttons["library.import"].tap()

        let prompt = app.staticTexts["import.prompt.text"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "the CSV prompt is not shown")
        XCTAssertTrue(prompt.label.contains("type,front,back,tags"), "the prompt does not state the format")
        XCTAssertTrue(
            prompt.label.localizedCaseInsensitiveContains("organizational")
                || prompt.label.localizedCaseInsensitiveContains("organizzative"),
            "the prompt does not exclude course-organizational information"
        )
        XCTAssertTrue(
            prompt.label.localizedCaseInsensitiveContains("code block")
                || prompt.label.localizedCaseInsensitiveContains("blocco di codice"),
            "the prompt no longer requests CSV as text in one code block"
        )
        XCTAssertTrue(
            prompt.label.localizedCaseInsensitiveContains("no attached file")
                || prompt.label.localizedCaseInsensitiveContains("nessun file allegato"),
            "the prompt no longer rejects an attached file"
        )

        let copy = app.buttons["import.prompt.copy"]
        XCTAssertTrue(copy.exists, "the prompt cannot be copied")
        copy.tap()
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Copiato", "Copied")
            ).firstMatch.waitForExistence(timeout: 5),
            "copying the prompt gives no feedback"
        )
    }

    /// `PasteButton` is a system control: it carries our identifier on most builds, but falls
    /// back to its own localized label, so the test looks for both rather than for one.
    private func pasteButton() -> XCUIElement {
        let identified = app.buttons["import.paste"]
        if identified.waitForExistence(timeout: 5) { return identified }
        return app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Incolla", "Paste")
        ).firstMatch
    }
}
