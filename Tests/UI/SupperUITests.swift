import XCTest

@MainActor final class SupperUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["recipe-test-chicken"].waitForExistence(timeout: 15))
        return app
    }
    private func openRecipe(_ app: XCUIApplication) {
        app.buttons["recipe-test-chicken"].tap()
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testNativeBackAndInteractiveTransitionsPreserveSearch() {
        let app = launch()
        let search = app.searchFields.firstMatch
        if !search.exists {
            let button = app.buttons["Search"].firstMatch
            if button.exists { button.tap() }
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Chicken\n")
        openRecipe(app); capture(app, "Immersive recipe detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["recipe-test-chicken"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Chicken")
        capture(app, "Search after normal back")
        openRecipe(app)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["recipe-test-chicken"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Chicken")
        capture(app, "Search after swipe back")
        openRecipe(app)
        // A short slow edge drag held below the completion threshold must cancel the pop.
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.45)), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
        capture(app, "Cancelled swipe back")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Chicken")
    }
    func testEditorCancelKeepsRecipeAndSingleReactionControl() {
        let app = launch(); openRecipe(app)
        XCTAssertEqual(app.buttons["Household reactions"].count, 1)
        XCTAssertFalse(app.staticTexts["Your reaction"].exists)
        app.buttons["editRecipe"].tap()
        let title = app.textFields["Recipe name"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(" edited")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Chicken with rice"].exists)
        XCTAssertFalse(app.staticTexts["Chicken with rice edited"].exists)
    }
}
