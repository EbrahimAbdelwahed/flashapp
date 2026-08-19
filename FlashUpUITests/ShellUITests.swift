import XCTest

/// Scaffold stop condition (B0.1): the app boots into a four-tab shell on iPhone and iPad.
final class ShellUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Onboarding is mandatory on a first launch, so the shell is only reachable past it.
    private func launchPastOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FLASHUP_UI_TEST_LOCAL"] = "1"
        app.launchEnvironment["FLASHUP_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()
        let skip = app.buttons["onboarding.skip"]
        if skip.waitForExistence(timeout: 5) { skip.tap() }
        return app
    }

    func testAppBootsIntoFourTabShell() {
        let app = launchPastOnboarding()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "The app did not present a tab bar")
        XCTAssertEqual(tabBar.buttons.count, 4, "Expected exactly four tabs in the shell")
    }

    func testEveryTabBecomesSelected() {
        let app = launchPastOnboarding()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "The app did not present a tab bar")

        for index in 0..<tabBar.buttons.count {
            let tab = tabBar.buttons.element(boundBy: index)
            tab.tap()
            XCTAssertTrue(tab.isSelected, "Tab at index \(index) did not become selected")
        }
    }

    func testBrandHeaderAppearsOnEveryTab() {
        let app = launchPastOnboarding()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "The app did not present a tab bar")

        for index in 0..<tabBar.buttons.count {
            tabBar.buttons.element(boundBy: index).tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["app.brand"].waitForExistence(timeout: 5),
                "The FlashApp brand header is missing from tab \(index)"
            )
        }
    }

    func testStorageFailureLaunchOffersRecoveryActions() {
        let app = XCUIApplication()
        app.launchEnvironment["FLASHUP_UI_TEST_FAILURE"] = "1"
        app.launchEnvironment["FLASHUP_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.otherElements["storage.recovery"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["storage.recovery.export"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["storage.recovery.support"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["storage.recovery.retry"].waitForExistence(timeout: 5))
    }

    func testConcurrentStorageRetryOpensOneOwner() {
        let app = XCUIApplication()
        app.launchEnvironment["FLASHUP_UI_TEST_FAILURE"] = "1"
        app.launchEnvironment["FLASHUP_UI_TEST_RETRY_PROBE"] = "1"
        app.launchEnvironment["FLASHUP_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()

        let retry = app.buttons["storage.recovery.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.tap()

        let openCount = app.staticTexts["storage.recovery.open-count"]
        XCTAssertTrue(openCount.waitForExistence(timeout: 5))
        XCTAssertEqual(openCount.label, "1")
        XCTAssertFalse(retry.isEnabled)
    }

    func testMediaInitFailureDoesNotOpenRepositoryAcrossRetryAttempts() {
        let app = XCUIApplication()
        app.launchEnvironment["FLASHUP_UI_TEST_FAILURE"] = "1"
        app.launchEnvironment["FLASHUP_UI_TEST_RETRY_PROBE"] = "1"
        app.launchEnvironment["FLASHUP_UI_TEST_MEDIA_FAILURE"] = "1"
        app.launchEnvironment["FLASHUP_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()

        let retry = app.buttons["storage.recovery.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        let repositoryOpenCount = app.staticTexts["storage.recovery.repository-open-count"]
        XCTAssertTrue(repositoryOpenCount.waitForExistence(timeout: 5))

        for _ in 0..<2 {
            retry.tap()
            let enabled = NSPredicate(format: "isEnabled == true")
            expectation(for: enabled, evaluatedWith: retry)
            waitForExpectations(timeout: 5)
        }

        XCTAssertEqual(repositoryOpenCount.label, "0")
    }
}
