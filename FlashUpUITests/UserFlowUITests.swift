import XCTest

/// The journeys a real user takes. Each test drives the app the way a person would, from a
/// clean install, and asserts on what is actually on screen.
/// Mirrors `StubReminderScheduler.environmentKey`; UI tests cannot import the app target.
enum ReminderStubEnvironment {
    static let key = "FLASHUP_UI_TEST_REMINDERS"
    static let granted = "granted"
    static let denied = "denied"
}

final class UserFlowUITests: UITestCase {

    /// Opens a study session from Today. Matched on the label in both shipped languages,
    /// because the button's identifier changes with the deck it offers.
    private func startStudying(file: StaticString = #filePath, line: UInt = #line) {
        let start = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Studia", "Study")
        ).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10), "no study action on Today", file: file, line: line)
        start.tap()
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

        startStudying()

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

    /// Suspending is the one card action that removes a card without a confirmation, so it
    /// has to be the one the generalized undo can take back.
    func testSuspendingACardRemovesItAndUndoBringsItBack() {
        skipOnboarding()
        startStudying()

        XCTAssertTrue(app.buttons["study.reveal"].waitForExistence(timeout: 10), "the session did not open")
        let card = app.descendants(matching: .any).matching(identifier: "study.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the card is not on screen")
        let firstPrompt = card.staticTexts.firstMatch.label

        app.buttons["study.actions"].tap()
        let suspend = app.buttons["study.action.suspend_card"]
        XCTAssertTrue(suspend.waitForExistence(timeout: 5), "the card actions menu did not open")
        suspend.tap()

        // The card is gone and undo has picked the action up.
        let undo = app.buttons["study.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "undo is missing from the toolbar")
        XCTAssertTrue(undo.isEnabled, "suspending should be undoable")
        XCTAssertNotEqual(card.staticTexts.firstMatch.label, firstPrompt, "the suspended card is still showing")

        undo.tap()

        XCTAssertEqual(
            card.staticTexts.firstMatch.label,
            firstPrompt,
            "undo did not put the suspended card back"
        )
        XCTAssertFalse(undo.isEnabled, "undo is a single step and should be spent")
    }

    /// The round trip the reviewer's Suspend depends on: hide a card mid-session, then find
    /// it in the Library and put it back. Without the second half, suspending is a one-way
    /// door.
    func testASuspendedNoteIsFoundInTheLibraryAndResumed() {
        skipOnboarding()
        openTab("tab.library")

        // Study *this* deck rather than everything: the all-decks queue breaks ties between
        // equal due dates unstably, so which deck the first card belongs to varies between
        // launches — and this test has to filter the deck that actually holds it.
        let deck = app.descendants(matching: .any).matching(identifier: "library.deck_row").element(boundBy: 0)
        XCTAssertTrue(deck.waitForExistence(timeout: 10), "no decks to open")
        deck.tap()

        app.buttons["deck.menu"].tap()
        let study = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Studia", "Study")
        ).firstMatch
        XCTAssertTrue(study.waitForExistence(timeout: 5), "the deck menu has no study action")
        study.tap()

        XCTAssertTrue(app.buttons["study.reveal"].waitForExistence(timeout: 10), "the session did not open")
        app.buttons["study.actions"].tap()
        let suspend = app.buttons["study.action.suspend_card"]
        XCTAssertTrue(suspend.waitForExistence(timeout: 5), "the card actions menu did not open")
        suspend.tap()
        app.buttons["study.close"].tap()

        // Filter to Suspended through the state picker.
        let filter = app.buttons["deck.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "the state filter is missing")
        filter.tap()
        let suspendedOption = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Sospese", "Suspended")
        ).firstMatch
        XCTAssertTrue(suspendedOption.waitForExistence(timeout: 5), "the filter menu did not open")
        suspendedOption.tap()

        // The suspended note is listed, and a leading swipe offers the way back.
        let note = app.descendants(matching: .any).matching(identifier: "note.row").element(boundBy: 0)
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the suspended note is not listed under the filter")
        note.swipeRight()

        let resume = app.buttons["note.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "swiping did not reveal Resume")
        resume.tap()

        XCTAssertFalse(
            note.waitForExistence(timeout: 3),
            "the resumed note should have left the Suspended filter"
        )
    }

    func testCardInfoOpensFromTheActionsMenu() {
        skipOnboarding()
        startStudying()

        XCTAssertTrue(app.buttons["study.reveal"].waitForExistence(timeout: 10), "the session did not open")

        app.buttons["study.actions"].tap()
        let info = app.buttons["study.action.info"]
        XCTAssertTrue(info.waitForExistence(timeout: 5), "the card actions menu did not open")
        info.tap()

        XCTAssertTrue(
            app.otherElements["study.info"].waitForExistence(timeout: 5),
            "the card info sheet did not open"
        )
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

    func testDeleteANoteAndRestoreItFromTheTrash() {
        skipOnboarding()
        openTab("tab.library")

        // Open the first deck and remember which note is about to be deleted. By identifier,
        // not by index: the Library's first row is its wordmark header, not a deck.
        let deck = app.descendants(matching: .any).matching(identifier: "library.deck_row").element(boundBy: 0)
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
