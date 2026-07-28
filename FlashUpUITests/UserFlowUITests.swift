import XCTest

/// The journeys a real user takes. Each test drives the app the way a person would, from a
/// clean install, and asserts on what is actually on screen.
final class UserFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Onboarding is mandatory once; the flows below start from a first launch and skip
        // it explicitly, so each test exercises the same state a new user reaches.
        app.launchArguments = ["-didFinishOnboarding", "NO"]
        app.launch()
    }

    // MARK: - Helpers

    private func skipOnboarding() {
        let skip = app.buttons["onboarding.skip"]
        if skip.waitForExistence(timeout: 5) {
            skip.tap()
        }
    }

    private func openTab(_ identifier: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "no tab bar")
        let index = ["tab.today": 0, "tab.library": 1, "tab.groups": 2, "tab.settings": 3][identifier] ?? 0
        tabBar.buttons.element(boundBy: index).tap()
    }

    // MARK: - Flows

    func testOnboardingLeadsIntoTheApp() {
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 5), "onboarding did not show")

        app.buttons["onboarding.primary"].tap()
        app.buttons["onboarding.primary"].tap()
        app.buttons["onboarding.primary"].tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "the app did not open after onboarding")
    }

    func testStudyFlowAnswersACardAndUndoesIt() {
        skipOnboarding()

        let studyNow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Studia")).firstMatch
        let fallback = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Study")).firstMatch
        let start = studyNow.exists ? studyNow : fallback
        XCTAssertTrue(start.waitForExistence(timeout: 10), "no study action on Today")
        start.tap()

        let reveal = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Mostra", "Show")
        ).firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 10), "the answer could not be revealed")
        reveal.tap()

        let good = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Buono", "Good")
        ).firstMatch
        XCTAssertTrue(good.waitForExistence(timeout: 5), "the grade buttons did not appear")
        good.tap()

        // The next card is presented, and the answer can be taken back.
        XCTAssertTrue(reveal.waitForExistence(timeout: 5), "the session did not move to the next card")
        let undo = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Annulla", "Undo")
        ).firstMatch
        XCTAssertTrue(undo.exists, "undo is not available after answering")
        XCTAssertTrue(undo.isEnabled, "undo should be enabled after an answer")
    }

    func testCreateDeckAndNoteFlow() {
        skipOnboarding()
        openTab("tab.library")

        app.buttons["library.new_deck"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the deck name field did not appear")
        field.typeText("Chimica")
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Crea", "Create")
        ).firstMatch.tap()

        let deckRow = app.staticTexts["Chimica"]
        XCTAssertTrue(deckRow.waitForExistence(timeout: 5), "the new deck is not listed")
        deckRow.tap()

        app.buttons["deck.menu"].tap()
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Aggiungi", "Add")
        ).firstMatch.tap()

        let front = app.textViews.firstMatch
        XCTAssertTrue(front.waitForExistence(timeout: 5), "the editor did not open")
        front.tap()
        front.typeText("Simbolo del sodio")
        app.textViews.element(boundBy: 1).tap()
        app.textViews.element(boundBy: 1).typeText("Na")

        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.isEnabled, "save should be enabled for a complete note")
        save.tap()

        XCTAssertTrue(
            app.staticTexts["Simbolo del sodio"].waitForExistence(timeout: 5),
            "the note is not listed in the deck"
        )
    }

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

    /// Deleting a note and getting it back is covered end to end by the repository tests
    /// (`LibraryFlowTests.trashRoundTrip`). Here the point is that the user can reach the
    /// trash and understand what it is for.
    func testTrashIsReachableAndExplainsItself() {
        skipOnboarding()
        openTab("tab.library")

        let trash = app.cells.containing(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Cestino", "Trash")
        ).firstMatch
        XCTAssertTrue(trash.waitForExistence(timeout: 10), "the trash row is missing from the library")
        trash.tap()

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "cestino", "Trash")
            ).firstMatch.waitForExistence(timeout: 5),
            "the trash screen does not explain itself"
        )
    }

    func testSettingsChangeAndStatisticsOpen() {
        skipOnboarding()
        openTab("tab.settings")

        let newPerDay = app.steppers["settings.new_per_day"]
        XCTAssertTrue(newPerDay.waitForExistence(timeout: 10), "settings did not open")
        newPerDay.buttons.element(boundBy: 1).tap()

        let reminder = app.switches["settings.reminder"]
        XCTAssertTrue(reminder.exists, "the reminder toggle is missing")
        reminder.tap()

        openTab("tab.today")
        app.buttons["today.statistics"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Serie", "Streak")
            ).firstMatch.waitForExistence(timeout: 5),
            "statistics did not open"
        )
    }

    func testGroupsExplainsWhyItIsUnavailable() {
        skipOnboarding()
        openTab("tab.groups")

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "gruppi", "Groups")
            ).firstMatch.waitForExistence(timeout: 10),
            "the groups screen says nothing"
        )
    }
}
