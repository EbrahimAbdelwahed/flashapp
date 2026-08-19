import XCTest

/// Launch and navigation shared by the UI suites.
///
/// Every test starts from a first launch with onboarding still to be skipped, so they all
/// exercise the state a new user actually reaches rather than a state left behind by
/// whichever test ran before.
class UITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-didFinishOnboarding", "NO"]
        app.launchEnvironment["FLASHUP_UI_TEST_LOCAL"] = "1"
        app.launchEnvironment["FLASHUP_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()
    }

    func skipOnboarding() {
        let skip = app.buttons["onboarding.skip"]
        if skip.waitForExistence(timeout: 5) {
            skip.tap()
        }
    }

    /// Taps the switch itself.
    ///
    /// A `Toggle` in a `List` reports a frame that covers the whole row, so `tap()` lands on
    /// the label — which does not flip it. Aiming at the trailing edge hits the control.
    func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    /// Goes back one level. The back button is identified by role rather than by its label,
    /// which is the previous screen's title and therefore localized.
    func goBack() {
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

    func openTab(_ identifier: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "no tab bar")
        let index = ["tab.today": 0, "tab.library": 1, "tab.groups": 2, "tab.settings": 3][identifier] ?? 0
        tabBar.buttons.element(boundBy: index).tap()
    }
}
