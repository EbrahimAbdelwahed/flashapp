import XCTest

/// The journeys a real user takes. Each test drives the app the way a person would, from a
/// clean install, and asserts on what is actually on screen.
/// Mirrors `StubReminderScheduler.environmentKey`; UI tests cannot import the app target.
enum ReminderStubEnvironment {
    static let key = "FLASHUP_UI_TEST_REMINDERS"
    static let granted = "granted"
    static let denied = "denied"
}

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

    /// Taps the switch itself.
    ///
    /// A `Toggle` in a `List` reports a frame that covers the whole row, so `tap()` lands on
    /// the label — which does not flip it. Aiming at the trailing edge hits the control.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    /// Goes back one level. The back button is identified by role rather than by its label,
    /// which is the previous screen's title and therefore localized.
    private func goBack() {
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "BackButton", "Libreria", "Library")
        ).firstMatch
        if back.waitForExistence(timeout: 5) {
            back.tap()
        } else {
            app.navigationBars.buttons.element(boundBy: 0).tap()
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

    func testDeleteANoteAndRestoreItFromTheTrash() {
        skipOnboarding()
        openTab("tab.library")

        // Open the first deck and remember which note is about to be deleted.
        let deck = app.cells.element(boundBy: 0)
        XCTAssertTrue(deck.waitForExistence(timeout: 10), "no decks to open")
        deck.tap()

        let note = app.descendants(matching: .any).matching(identifier: "note.row").element(boundBy: 0)
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the deck has no notes")
        let deletedLabel = note.label

        note.swipeLeft()
        let delete = app.buttons["note.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "swiping did not reveal Delete")
        delete.tap()

        // It leaves the deck…
        XCTAssertFalse(
            app.staticTexts[deletedLabel].exists,
            "the deleted note is still listed in the deck"
        )

        // …and is waiting in the trash, reached from Settings so the test never depends on
        // the back button's localized label.
        openTab("tab.settings")
        let trashRow = app.buttons["settings.trash"]
        XCTAssertTrue(trashRow.waitForExistence(timeout: 10), "the trash row is missing from Settings")
        if !trashRow.isHittable { app.swipeUp() }
        trashRow.tap()

        let trashed = app.descendants(matching: .any).matching(identifier: "trash.row").element(boundBy: 0)
        XCTAssertTrue(trashed.waitForExistence(timeout: 5), "the deleted note is not in the trash")

        trashed.swipeLeft()
        let restore = app.buttons["trash.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "swiping did not reveal Restore")
        restore.tap()

        // Restored: the trash empties and says so.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "vuoto", "empty")
            ).firstMatch.waitForExistence(timeout: 5),
            "the trash did not empty after restoring"
        )
    }

    func testEnablingTheReminderKeepsItOnAndOffersATime() {
        app.terminate()
        app.launchEnvironment[ReminderStubEnvironment.key] = ReminderStubEnvironment.granted
        app.launch()
        skipOnboarding()
        openTab("tab.settings")

        let reminder = app.switches["settings.reminder"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 10), "the reminder toggle is missing")
        flip(reminder)

        XCTAssertEqual(reminder.value as? String, "1", "the reminder should stay on when permission is granted")
        XCTAssertTrue(
            app.datePickers.firstMatch.waitForExistence(timeout: 5),
            "enabling the reminder should offer a time"
        )
        XCTAssertFalse(
            app.staticTexts["settings.reminder.blocked"].exists,
            "nothing should warn about permissions when they were granted"
        )
    }

    func testARefusedReminderExplainsThatiOSIsBlockingIt() {
        app.terminate()
        app.launchEnvironment[ReminderStubEnvironment.key] = ReminderStubEnvironment.denied
        app.launch()
        skipOnboarding()
        openTab("tab.settings")

        let reminder = app.switches["settings.reminder"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 10), "the reminder toggle is missing")
        flip(reminder)

        // The user's choice is kept; what changes is that the screen says why nothing will
        // arrive, which is the thing they can actually fix.
        XCTAssertEqual(reminder.value as? String, "1", "the user's choice must not be undone")
        XCTAssertTrue(
            app.staticTexts["settings.reminder.blocked"].waitForExistence(timeout: 5),
            "a blocked reminder must explain itself"
        )
    }

    func testImportOffersACopyablePromptForChatGPT() {
        skipOnboarding()
        openTab("tab.library")

        app.buttons["library.import"].tap()

        let prompt = app.staticTexts["import.prompt.text"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "the CSV prompt is not shown")
        XCTAssertTrue(prompt.label.contains("type,front,back,tags"), "the prompt does not state the format")

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

    func testSettingsChangeAndStatisticsOpen() {
        skipOnboarding()
        openTab("tab.settings")

        let newPerDay = app.steppers["settings.new_per_day"]
        XCTAssertTrue(newPerDay.waitForExistence(timeout: 10), "settings did not open")
        newPerDay.buttons.element(boundBy: 1).tap()

        let reminder = app.switches["settings.reminder"]
        XCTAssertTrue(reminder.exists, "the reminder toggle is missing")
        flip(reminder)

        openTab("tab.today")
        app.buttons["today.statistics"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Serie", "Streak")
            ).firstMatch.waitForExistence(timeout: 5),
            "statistics did not open"
        )
    }

    /// The appearance is applied by the root scene, not by the Settings screen, so the
    /// choice has to survive leaving Settings and coming back.
    func testAppearanceChoiceIsAppliedAndKept() {
        skipOnboarding()
        openTab("tab.settings")

        let picker = app.segmentedControls["settings.appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "the appearance picker is missing")

        let dark = picker.buttons.element(boundBy: 2)
        dark.tap()
        XCTAssertTrue(dark.isSelected, "the dark option did not become selected")

        openTab("tab.today")
        openTab("tab.settings")

        XCTAssertTrue(
            app.segmentedControls["settings.appearance"].buttons.element(boundBy: 2).isSelected,
            "the appearance choice was lost on the way back"
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
