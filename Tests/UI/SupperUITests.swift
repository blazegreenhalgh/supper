import XCTest

@MainActor final class SupperUITests: XCTestCase {
    func testDiscoveryEditsStayDraftUntilKeptAndGridSharesDecisions() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--discovery-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["openRecipeDiscovery"].waitForExistence(timeout: 15))
        app.buttons["openRecipeDiscovery"].tap()
        app.buttons["A cosy one-pot dinner"].tap()
        app.buttons["findDiscoveryRecipes"].tap()
        let card = app.buttons["discoveryTopCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        capture(app, "Discovery recipe stack")
        card.tap()
        app.buttons["recipeTags"].tap()
        app.buttons["addMoreTags"].tap()
        let tagField = app.textFields["recipeTagsText"]
        let tagInput = tagField.exists ? tagField : app.textViews["recipeTagsText"]
        XCTAssertTrue(tagInput.waitForExistence(timeout: 5))
        tagInput.tap(); tagInput.typeText("Weeknight")
        app.buttons["confirmNewTags"].tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["recipeTags"].waitForExistence(timeout: 5))
        app.buttons["recipeTags"].tap()
        XCTAssertTrue(app.staticTexts["Weeknight"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["editRecipe"].tap()
        let name = app.textFields["Recipe name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(" edited")
        app.buttons["Done"].firstMatch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        expectDiscoveryCard(app, title: "Lemon chicken bowls edited")
        app.buttons["closeDiscovery"].tap()
        XCTAssertFalse(app.staticTexts["Lemon chicken bowls edited"].exists)
        app.buttons["openRecipeDiscovery"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["keepDiscoveryRecipe"].tap()
        expectDiscoveryCard(app, title: "Creamy mushroom pasta")
        app.buttons["discoveryLayout"].tap()
        XCTAssertTrue(app.buttons["Discard Creamy mushroom pasta"].waitForExistence(timeout: 5))
        capture(app, "Discovery grid")
        app.buttons["Discard Creamy mushroom pasta"].tap()
        XCTAssertFalse(app.staticTexts["Creamy mushroom pasta"].exists)
        app.buttons["discoveryLayout"].tap()
        app.buttons["undoDiscoveryDiscard"].tap()
        expectDiscoveryCard(app, title: "Creamy mushroom pasta")
        app.buttons["closeDiscovery"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Lemon chicken bowls edited"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Creamy mushroom pasta"].exists)
    }

    func testDiscoverySwipeDiscardsAndKeeps() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--discovery-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["openRecipeDiscovery"].waitForExistence(timeout: 15))
        app.buttons["openRecipeDiscovery"].tap()
        app.buttons["A cosy one-pot dinner"].tap()
        app.buttons["findDiscoveryRecipes"].tap()
        let card = app.buttons["discoveryTopCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.swipeLeft()
        expectDiscoveryCard(app, title: "Creamy mushroom pasta")
        card.swipeRight()
        expectDiscoveryCard(app, title: "Crispy chickpea wraps")
        app.buttons["closeDiscovery"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Creamy mushroom pasta"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Lemon chicken bowls"].exists)
    }

    private func expectDiscoveryCard(_ app: XCUIApplication, title: String) {
        let card = app.buttons["discoveryTopCard"]
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", title), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 5), .completed)
    }

    private func launch(dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        if dark { app.launchArguments.append("--ui-testing-dark") }
        app.launch()
        XCTAssertTrue(app.buttons["recipe-test-chicken"].waitForExistence(timeout: 15))
        return app
    }
    private func openRecipe(_ app: XCUIApplication) {
        app.buttons["recipe-test-chicken"].tap()
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recipeTags"].waitForExistence(timeout: 5))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testLibraryDeletionRequiresConfirmationAndCloudCheckResponds() {
        let app = launch()
        app.buttons["Library options"].tap()
        app.buttons["Household"].tap()
        XCTAssertTrue(app.navigationBars["Household"].waitForExistence(timeout: 5))
        app.buttons["Check iCloud"].tap()
        XCTAssertTrue(app.staticTexts["iCloud account result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["iCloud account result"].label.contains("disabled in this build"))
        app.swipeUp()
        let options = app.buttons["Library options for Our Supper"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap(); app.buttons["Delete library"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["recipe-test-chicken"].waitForExistence(timeout: 5))
        app.buttons["Library options"].tap(); app.buttons["Household"].tap()
        app.swipeUp()
        options.tap(); app.buttons["Delete library"].tap()
        app.buttons["Delete library"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["Done"])
        waitForExpectations(timeout: 5)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["No recipes yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recipe-test-chicken"].exists)
        capture(app, "Empty cookbook after confirmed library deletion")
    }

    func testNativeBackAndInteractiveTransitionsPreserveSearch() {
        let app = launch()
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        app.buttons["Search"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Chicken\n")
        app.buttons["durationFilter"].tap()
        app.buttons["Up to 30 min"].tap()
        XCTAssertEqual(app.buttons["durationFilter"].value as? String, "Active")
        app.buttons["Library options"].tap()
        app.buttons["Pick something"].tap()
        XCTAssertTrue(app.buttons["Open recipe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Chicken with rice"].exists)
        app.buttons["Done"].tap()
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Chicken")
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
        XCTAssertEqual(app.buttons["durationFilter"].value as? String, "Active")
        XCTAssertTrue(app.buttons["clearFilters"].isHittable)
        app.buttons["clearFilters"].tap()
        XCTAssertEqual(app.buttons["durationFilter"].value as? String, "Not active")
    }
    func testEditorCancelKeepsRecipeAndSingleReactionControl() {
        let app = launch(); openRecipe(app)
        XCTAssertEqual(app.buttons.matching(identifier: "Household reactions").count, 1)
        XCTAssertFalse(app.staticTexts["Your reaction"].exists)
        app.buttons["editRecipe"].tap()
        let title = app.textFields["Recipe name"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(" edited")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Chicken with rice"].exists)
        XCTAssertFalse(app.staticTexts["Chicken with rice edited"].exists)
    }

    func testFocusedIngredientEditorAndFullScreenMethod() {
        let app = launch(); openRecipe(app)
        app.buttons["editRecipe"].tap()
        XCTAssertTrue(app.buttons["editIngredients"].waitForExistence(timeout: 5))
        capture(app, "Recipe editor overview")
        app.buttons["editIngredients"].tap()
        app.buttons["addIngredient"].tap()
        let name = app.textFields["ingredientName"]
        // A vertical TextField is exposed as a text view on some iOS versions.
        let field = name.exists ? name : app.textViews["ingredientName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Lime wedges")
        let quantity = app.textFields["ingredientQuantity"]
        quantity.tap(); quantity.typeText("2")
        capture(app, "Labeled ingredient editor")
        app.buttons["saveIngredient"].tap()
        XCTAssertTrue(app.staticTexts["2 Lime wedges"].waitForExistence(timeout: 5))
        capture(app, "Ingredient editing list")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["2 Lime wedges"].waitForExistence(timeout: 5))
        capture(app, "Inline bold ingredient amounts")
        app.segmentedControls.buttons["Method"].tap()
        XCTAssertTrue(app.staticTexts["Cook the chicken breast."].exists)
        XCTAssertTrue(app.staticTexts["Serve with rice."].exists)
        XCTAssertFalse(app.buttons["Previous"].exists)
        capture(app, "Expanded method steps")
        app.buttons["fullScreenMethod"].tap()
        XCTAssertTrue(app.buttons["closeFullScreenMethod"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["500 g chicken breast"].waitForExistence(timeout: 5))
        capture(app, "Step ingredients with recipe amounts")
        XCTAssertFalse(app.buttons["previousFullScreenStep"].isEnabled)
        app.buttons["nextFullScreenStep"].tap()
        XCTAssertTrue(app.staticTexts["Serve with rice."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No ingredients identified for this step."].exists)
        XCTAssertFalse(app.staticTexts["500 g chicken breast"].exists)
        XCTAssertFalse(app.buttons["nextFullScreenStep"].isEnabled)
        capture(app, "Full screen method")
        app.buttons["previousFullScreenStep"].tap()
        app.buttons["closeFullScreenMethod"].tap()
        XCTAssertTrue(app.buttons["fullScreenMethod"].waitForExistence(timeout: 5))
    }


    func testFormattingReviewCancelAndDraftOnlyApply() {
        let app = launch(); openRecipe(app)
        app.buttons["editRecipe"].tap()
        app.buttons["editIngredients"].tap()
        app.buttons["addIngredient"].tap()
        let name = app.textFields["ingredientName"]
        let field = name.exists ? name : app.textViews["ingredientName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("1 lb / 500g BEEF MINCE ((fresh))")
        app.buttons["saveIngredient"].tap()
        app.buttons["autoFormatIngredients"].tap()
        XCTAssertTrue(app.buttons["applyIngredientFormatting"].waitForExistence(timeout: 10))
        let apply = app.buttons["applyIngredientFormatting"]
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: apply)
        waitForExpectations(timeout: 20)
        capture(app, "Ingredient formatting review")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["1 lb / 500g BEEF MINCE ((fresh))"].exists)
        app.buttons["autoFormatIngredients"].tap()
        expectation(for: ready, evaluatedWith: app.buttons["applyIngredientFormatting"])
        waitForExpectations(timeout: 20)
        app.buttons["applyIngredientFormatting"].tap()
        XCTAssertTrue(app.staticTexts["500 g Beef mince (fresh)"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Cancel"].tap()
        app.swipeUp()
        XCTAssertFalse(app.staticTexts["500 g Beef mince (fresh)"].exists)
    }

    func testTagsSheetAndSimpleGrocerySelection() {
        let app = launch(dark: true); openRecipe(app)
        XCTAssertFalse(app.staticTexts["Easy"].exists)
        app.buttons["recipeTags"].tap()
        XCTAssertTrue(app.staticTexts["Easy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addMoreTags"].exists)
        capture(app, "Recipe tags sheet")
        app.buttons["addMoreTags"].tap()
        let tagField = app.textFields["recipeTagsText"]
        let tagInput = tagField.exists ? tagField : app.textViews["recipeTagsText"]
        XCTAssertTrue(tagInput.waitForExistence(timeout: 5))
        tagInput.tap(); tagInput.typeText("Weeknight")
        XCTAssertEqual(tagInput.value as? String, "Weeknight")
        app.buttons["confirmNewTags"].tap()
        XCTAssertTrue(app.staticTexts["Weeknight"].waitForExistence(timeout: 5), app.debugDescription)
        capture(app, "Tags ready to save")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["recipeTags"].waitForExistence(timeout: 5))
        app.buttons["recipeTags"].tap()
        XCTAssertTrue(app.staticTexts["Weeknight"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].tap()
        app.buttons["Recipe options"].tap()
        app.buttons["recipeMenuAddToGroceries"].tap()
        XCTAssertTrue(app.navigationBars["Add to Groceries"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ingredients selected'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Quantities for'")).firstMatch.exists)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'groceryIngredient-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "Selected")
        row.tap(); XCTAssertEqual(row.value as? String, "Not selected")
        capture(app, "Simple grocery checkboxes")
    }

    func testHomepageActionsAndActiveFilters() {
        let app = launch()
        let filterScroll = app.scrollViews["filterScrollView"]
        XCTAssertEqual(filterScroll.frame.minX, app.windows.firstMatch.frame.minX, accuracy: 1)
        XCTAssertEqual(filterScroll.frame.maxX, app.windows.firstMatch.frame.maxX, accuracy: 1)
        app.buttons["durationFilter"].tap(); app.buttons["Up to 15 min"].tap()
        XCTAssertTrue(app.staticTexts["No matching recipes"].waitForExistence(timeout: 5))
        app.buttons["clearFilters"].tap()
        XCTAssertTrue(app.buttons["recipe-test-chicken"].waitForExistence(timeout: 5))
        app.buttons["durationFilter"].tap(); app.buttons["Up to 30 min"].tap()
        XCTAssertEqual(app.buttons["durationFilter"].value as? String, "Active")
        XCTAssertTrue(app.buttons["clearFilters"].isHittable)
        XCTAssertEqual(app.buttons["clearFilters"].frame.height, app.buttons["durationFilter"].frame.height, accuracy: 1)
        XCTAssertEqual(filterScroll.frame.maxX, app.windows.firstMatch.frame.maxX, accuracy: 1)
        filterScroll.swipeLeft()
        XCTAssertTrue(app.buttons["clearFilters"].isHittable)
        capture(app, "Homepage active filter")
        app.buttons["Library options"].tap()
        XCTAssertFalse(app.buttons["Search with words"].exists)
        app.buttons["Pick something"].tap()
        XCTAssertTrue(app.buttons["Open recipe"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["clearFilters"].tap()
        app.buttons["editCollections"].tap()
        XCTAssertTrue(app.navigationBars["Collections"].waitForExistence(timeout: 5))
        app.buttons["New collection"].tap()
        let name = app.textFields["Collection name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Weeknight")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Weeknight"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["addRecipe"].tap()
        XCTAssertTrue(app.textFields["Recipe name"].waitForExistence(timeout: 5))
        capture(app, "Clean new recipe form")
    }
}
