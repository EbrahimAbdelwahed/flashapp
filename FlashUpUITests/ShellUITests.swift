import XCTest

/// Scaffold stop condition (B0.1): the app boots into a four-tab shell on iPhone and iPad.
final class ShellUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAppBootsIntoFourTabShell() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "The app did not present a tab bar")
        XCTAssertEqual(tabBar.buttons.count, 4, "Expected exactly four tabs in the shell")
    }

    func testEveryTabOpensItsPlaceholder() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "The app did not present a tab bar")

        for index in 0..<tabBar.buttons.count {
            let tab = tabBar.buttons.element(boundBy: index)
            tab.tap()
            XCTAssertTrue(tab.isSelected, "Tab at index \(index) did not become selected")
        }
    }
}
