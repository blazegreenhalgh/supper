import XCTest

@MainActor final class SupperUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOpenAIKeyCanBeSavedReplacedAndRemovedWithoutSendingRequests() {
        let app = launch()
        app.buttons["Library options"].tap()
        app.buttons["Household"].tap()
        app.buttons["openAISettings"].tap()
        let field = app.secureTextFields["openAIKeyInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("sk-ui-test-not-a-real-key-1234567890")
        app.buttons["saveOpenAIKey"].tap()
        guard app.staticTexts["API key saved on this device"].waitForExistence(timeout: 5) else {
            XCTFail("Key save failed: \(app.alerts.debugDescription)"); return
        }
        XCTAssertTrue(app.buttons["Test connection"].exists)
        capture(app, "OpenAI key settings")
        // Never test a live connection with a fixture key.
        app.terminate(); app.launch()
        app.buttons["Library options"].tap(); app.buttons["Household"].tap(); app.buttons["openAISettings"].tap()
        XCTAssertTrue(app.staticTexts["API key saved on this device"].waitForExistence(timeout: 5))
        let replacement = app.secureTextFields["openAIKeyInput"]
        replacement.tap(); replacement.typeText("sk-ui-test-replacement-key-1234567890")
        app.buttons["saveOpenAIKey"].tap()
        app.buttons["Remove key"].tap()
        app.buttons["confirmRemoveOpenAIKey"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Connect your OpenAI account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Test connection"].exists)
    }
    func testRecipeChatKeepsInputWhenReopenedAndCancelDoesNotSave() {
        let app = launch(); openRecipe(app)
        app.buttons["editRecipe"].tap()
        let launcher = app.buttons["openRecipeChat"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["closeRecipeChat"].exists)
        XCTAssertLessThan(launcher.frame.height, 65)
        XCTAssertGreaterThanOrEqual(launcher.frame.minX, 24)
        capture(app, "Compact recipe chat input")
        app.swipeUp()
        let source = app.textFields["Website URL (optional)"]
        if source.frame.maxY >= launcher.frame.minY { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(source.isHittable)
        XCTAssertLessThan(source.frame.maxY, launcher.frame.minY)

        expandRecipeChat(app)
        let input = chatInput(app)
        input.tap()
        // Fresh simulators may show Apple's slide-to-type introduction.
        if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
        input.typeText("F")
        // A native TextField exposes the text bounds to accessibility, excluding
        // the pill's padding. Check its alignment and the native control's target
        // size, then capture the visible surfaces for comparison.
        XCTAssertGreaterThanOrEqual(app.buttons["sendRecipeChat"].frame.height, 44)
        XCTAssertEqual(app.buttons["sendRecipeChat"].frame.midY, input.frame.midY, accuracy: 1)
        capture(app, "Single-line composer with matching native control heights")
        XCTAssertLessThanOrEqual(input.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        XCTAssertGreaterThan(app.scrollViews["recipeChatMessages"].frame.height, 200)
        input.typeText("ind ingredients and a method for naan bread")
        capture(app, "Native chat sheet with keyboard")

        // Dismiss the keyboard without closing the conversation, then exercise
        // both native detents from a known large state. iOS may settle at medium
        // when an interactive keyboard dismissal finishes.
        app.scrollViews["recipeChatMessages"].swipeDown()
        XCTAssertTrue(app.buttons["closeRecipeChat"].exists)
        if app.keyboards.firstMatch.exists { app.buttons["hideRecipeChatKeyboard"].tap() }
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        dragChatGrabber(app, to: 0.08)
        let largeHeight = app.scrollViews["recipeChatMessages"].frame.height
        dragChatGrabber(app, to: 0.52)
        XCTAssertTrue(app.buttons["closeRecipeChat"].exists)
        XCTAssertLessThan(app.scrollViews["recipeChatMessages"].frame.height, largeHeight - 60)
        capture(app, "Native chat sheet at medium height")
        dragChatGrabber(app, to: 0.08)
        XCTAssertGreaterThan(app.scrollViews["recipeChatMessages"].frame.height, largeHeight - 30)
        dragChatGrabber(app, to: 0.98)
        XCTAssertTrue(launcher.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["closeRecipeChat"].exists)
        expandRecipeChat(app)
        XCTAssertEqual(chatInput(app).value as? String, "Find ingredients and a method for naan bread")
        collapseRecipeChat(app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Naan bread"].exists)
    }

    func testRecipeChatRetainsSessionAcrossEditorsAndProtectsManualChanges() {
        let app = launchRecipeChatFixture()
        collapseRecipeChat(app)
        app.buttons["editIngredients"].tap()
        XCTAssertTrue(app.buttons["addIngredient"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["openRecipeChat"].isHittable)
        app.buttons["addIngredient"].tap()
        XCTAssertTrue(app.navigationBars["Add Ingredient"].waitForExistence(timeout: 5))
        expandRecipeChat(app)
        XCTAssertTrue(app.buttons["reviewRecipeAIEdit"].isHittable)
        capture(app, "Chat preserves unfinished ingredient edits")
        app.buttons["reviewRecipeAIEdit"].tap()
        XCTAssertTrue(app.buttons["applyRecipeAIPreview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["applyRecipeAIPreview"].isEnabled)
        XCTAssertTrue(app.staticTexts["recipeAIPreviewBlocker"].label.contains("Finish your ingredient edit"))
        app.buttons["closeRecipeAIPreview"].tap()
        collapseRecipeChat(app)
        let name = app.textFields["ingredientName"]
        let field = name.exists ? name : app.textViews["ingredientName"]
        field.tap(); field.typeText("Manual garnish")
        app.buttons["saveIngredient"].tap()
        XCTAssertTrue(app.buttons["addIngredient"].waitForExistence(timeout: 5))
        expandRecipeChat(app)
        app.buttons["reviewRecipeAIEdit"].tap()
        XCTAssertTrue(app.buttons["applyRecipeAIPreview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["applyRecipeAIPreview"].isEnabled)
        XCTAssertTrue(app.staticTexts["recipeAIPreviewBlocker"].label.contains("Your recipe has changed"))
        capture(app, "Preview protects newer manual edits")
        app.buttons["closeRecipeAIPreview"].tap()
        collapseRecipeChat(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["editMethod"].tap()
        XCTAssertTrue(app.buttons["addMethodStep"].waitForExistence(timeout: 5))
        app.buttons["addMethodStep"].tap()
        XCTAssertTrue(app.navigationBars["Add Step"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["openRecipeChat"].isHittable)
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        collapseRecipeChat(app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Manual garnish"].exists)
    }

    func testRecipeChatPreviewShowsRemovalsAndAppliesAndUndoesInPlace() {
        let app = launchRecipeChatFixture()
        collapseRecipeChat(app)
        app.buttons["editIngredients"].tap()
        XCTAssertTrue(app.buttons["addIngredient"].waitForExistence(timeout: 5))
        expandRecipeChat(app)
        app.buttons["reviewRecipeAIEdit"].tap()
        XCTAssertTrue(app.segmentedControls["recipeAIPreviewMode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Removed ingredients"].exists)
        XCTAssertTrue(app.staticTexts["Removed steps"].exists)
        XCTAssertTrue(app.staticTexts["Removed: Serve with rice."].exists)
        XCTAssertTrue(app.staticTexts["Previously: 500 g chicken breast"].exists)
        capture(app, "Recipe preview with change counts")
        app.scrollViews["recipeAIPreview"].swipeUp()
        capture(app, "Recipe preview with removed ingredients and steps")
        app.scrollViews["recipeAIPreview"].swipeDown()
        app.segmentedControls["recipeAIPreviewMode"].buttons["Recipe"].tap()
        XCTAssertFalse(app.staticTexts["Removed ingredients"].exists)
        XCTAssertFalse(app.staticTexts["Removed steps"].exists)
        XCTAssertTrue(app.staticTexts["Serve with lime wedges."].exists)
        capture(app, "Clean proposed recipe preview")
        app.buttons["applyRecipeAIPreview"].tap()
        XCTAssertTrue(app.buttons["undoRecipeAIEdit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reviewRecipeAIEdit"].exists)
        collapseRecipeChat(app)
        XCTAssertTrue(app.staticTexts["750 g chicken breast"].exists)
        expandRecipeChat(app)
        app.buttons["undoRecipeAIEdit"].tap()
        collapseRecipeChat(app)
        XCTAssertTrue(app.staticTexts["500 g chicken breast"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["2 Lime wedges"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        collapseRecipeChat(app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
    }

    private func launchRecipeChatFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--recipe-chat-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["recipe-test-chicken"].waitForExistence(timeout: 15))
        openRecipe(app)
        app.buttons["editRecipe"].tap()
        expandRecipeChat(app)
        XCTAssertTrue(app.buttons["reviewRecipeAIEdit"].waitForExistence(timeout: 5))
        return app
    }

    private func collapseRecipeChat(_ app: XCUIApplication) {
        let close = app.buttons["closeRecipeChat"]
        if close.exists {
            close.tap()
            XCTAssertTrue(app.buttons["openRecipeChat"].waitForExistence(timeout: 5))
        }
    }

    private func chatInput(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["recipeChatInput"]
        return field.exists ? field : app.textViews["recipeChatInput"]
    }

    private func expandRecipeChat(_ app: XCUIApplication) {
        if !app.buttons["closeRecipeChat"].exists {
            let launcher = app.buttons["openRecipeChat"]
            XCTAssertTrue(launcher.waitForExistence(timeout: 5))
            launcher.tap()
        }
        XCTAssertTrue(app.buttons["closeRecipeChat"].waitForExistence(timeout: 5))
        XCTAssertTrue(chatInput(app).isHittable, app.debugDescription)
    }

    private func dragChatGrabber(_ app: XCUIApplication, to screenFraction: CGFloat) {
        let grabber = app.descendants(matching: .any).matching(identifier: "Grabber").firstMatch
        let start = grabber.exists
            ? grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            : app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: app.frame.midX, dy: app.buttons["closeRecipeChat"].frame.minY - 14))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: screenFraction)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    func testDiscoveryLoadingCanBeCancelledAndKeepsThePrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--discovery-ui-testing", "--discovery-loading-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["openRecipeDiscovery"].waitForExistence(timeout: 15))
        app.buttons["openRecipeDiscovery"].tap()
        capture(app, "Native craving form")
        app.buttons["A cosy one-pot dinner"].tap()
        app.buttons["findDiscoveryRecipes"].tap()
        // Native progress keeps cancellation available throughout the search.
        XCTAssertTrue(app.buttons["cancelDiscoverySearch"].waitForExistence(timeout: 5))
        capture(app, "Native recipe search progress")
        app.buttons["cancelDiscoverySearch"].tap()
        XCTAssertTrue(app.buttons["findDiscoveryRecipes"].waitForExistence(timeout: 5))
        let field = app.textFields["discoveryPrompt"]
        let input = field.exists ? field : app.textViews["discoveryPrompt"]
        XCTAssertEqual(input.value as? String, "A cosy one-pot dinner")
        XCTAssertFalse(app.buttons["discoveryTopCard"].exists)
    }

    func testChatCollectionChangesApplyToDraftAndOnlyPersistOnSave() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--collection-chat-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["recipe-test-chicken"].waitForExistence(timeout: 15))
        openRecipe(app); app.buttons["editRecipe"].tap(); expandRecipeChat(app)
        app.scrollViews["recipeChatMessages"].swipeUp()
        XCTAssertTrue(app.buttons["applyChatCollections"].waitForExistence(timeout: 5))
        capture(app, "Collection changes ready to apply")
        app.buttons["applyChatCollections"].tap()
        XCTAssertTrue(app.buttons["undoRecipeAIEdit"].waitForExistence(timeout: 5))
        collapseRecipeChat(app); app.buttons["Cancel"].tap()
        app.buttons["Recipe options"].tap(); app.buttons["Collections"].tap()
        XCTAssertTrue(app.switches["Weeknight"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["Weeknight"].value as? String, "0")
        app.buttons["Cancel"].tap()
        app.buttons["editRecipe"].tap(); expandRecipeChat(app)
        app.scrollViews["recipeChatMessages"].swipeUp()
        app.buttons["applyChatCollections"].tap()
        collapseRecipeChat(app); app.buttons["Save"].tap()
        app.buttons["Recipe options"].tap(); app.buttons["Collections"].tap()
        XCTAssertTrue(app.switches["Weeknight"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["Weeknight"].value as? String, "1")
    }

    func testRecipeCardPreviewActionsAndCollectionSubmenu() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--collection-library-ui-testing", "--ui-testing-disable-animations"]
        app.launch()
        let card = app.buttons["recipe-test-chicken"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.press(forDuration: 1)
        XCTAssertTrue(app.buttons["cardEditRecipe"].waitForExistence(timeout: 5))
        capture(app, "Recipe long press preview and actions")
        XCTAssertTrue(app.buttons["cardAddToGroceries"].exists)
        XCTAssertTrue(app.buttons["cardDeleteRecipe"].exists)
        app.buttons["Collection"].tap(); app.buttons["cardCollection-Weekend"].tap()
        let weekend = app.otherElements["collectionDrop-Weekend"]
        XCTAssertTrue(weekend.buttons["recipe-test-chicken"].waitForExistence(timeout: 5))
        card.press(forDuration: 1); app.buttons["cardDeleteRecipe"].tap()
        XCTAssertTrue(app.alerts["Delete recipe?"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(card.exists)
    }

    func testRecipeDragMovesBetweenHomeCollections() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--collection-library-ui-testing", "--ui-testing-disable-animations"]
        app.launch()
        let source = app.otherElements["collectionDrop-Weeknight"]
        let target = app.otherElements["collectionDrop-Weekend"]
        let card = source.buttons["recipe-test-chicken"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertFalse(target.buttons["recipe-test-chicken"].exists)
        // Keep both sections away from the bottom auto-scroll region. A drag to
        // a screen-edge coordinate becomes stale as the library scrolls beneath it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.7)).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(card.isHittable)
        XCTAssertLessThan(target.frame.maxY, app.tabBars.firstMatch.frame.minY - 20)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).press(forDuration: 1.1,
            thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(target.buttons["recipe-test-chicken"].waitForExistence(timeout: 5))
        XCTAssertFalse(source.buttons["recipe-test-chicken"].exists)
        capture(app, "Recipe moved to another collection")
    }

    func testRecipePhotosPreviewOriginalAndApplyWithUndoAndUploadOption() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--recipe-photo-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["recipe-test-chicken"].waitForExistence(timeout: 15))
        openRecipe(app); app.buttons["editRecipe"].tap(); expandRecipeChat(app)
        XCTAssertTrue(app.buttons["reviewChatPhoto"].waitForExistence(timeout: 5))
        capture(app, "Liquid Glass chat with photo options")
        app.scrollViews["chatPhotoCarousel"].swipeLeft()
        app.buttons["previewChatPhoto-2"].tap()
        XCTAssertTrue(app.segmentedControls["photoComparison"].waitForExistence(timeout: 5))
        app.segmentedControls["photoComparison"].buttons["Original"].tap()
        app.segmentedControls["photoComparison"].buttons["Edited"].tap()
        XCTAssertTrue(app.staticTexts["recipePhotoCaption"].label.contains("AI-edited"))
        capture(app, "Uploaded food photo comparison")
        app.buttons["closePhotoPreview"].tap()
        app.buttons["reviewChatPhoto"].tap()
        XCTAssertTrue(app.staticTexts["recipePhotoCaption"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recipePhotoCaption"].label.contains("UI test photo source"))
        capture(app, "Online photo preview with source credit")
        app.buttons["applyRecipePhoto"].tap()
        XCTAssertTrue(app.buttons["undoRecipeAIEdit"].waitForExistence(timeout: 5))
        app.buttons["undoRecipeAIEdit"].tap()
        XCTAssertFalse(app.buttons["undoRecipeAIEdit"].exists)
        app.buttons["chatPhotoOptions"].tap()
        app.buttons["Polish my food photo"].tap()
        XCTAssertTrue(app.buttons["uploadFoodPhoto"].waitForExistence(timeout: 5))
        capture(app, "Editorial food photo upload option")
        app.buttons["Done"].tap(); collapseRecipeChat(app); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
    }

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
        let tagField = app.textFields["recipeTagsText"]
        let tagInput = tagField.exists ? tagField : app.textViews["recipeTagsText"]
        XCTAssertTrue(tagInput.waitForExistence(timeout: 5))
        tagInput.tap(); tagInput.typeText("Weeknight")
        app.buttons["addSingleRecipeTag"].tap()
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
        let restingFrame = card.frame
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // A small diagonal drag should settle back without opening or deciding a recipe.
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 35, dy: 8)), withVelocity: .slow, thenHoldForDuration: 0.3)
        expectDiscoveryCard(app, title: "Lemon chicken bowls")
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(card.frame.midX - restingFrame.midX) < 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
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

    func testIngredientAndSectionDragsPersistOnSave() {
        let app = launch(); openRecipe(app)
        app.buttons["editRecipe"].tap(); app.buttons["editIngredients"].tap()
        XCTAssertTrue(app.buttons["addRecipeSection"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["addRecipeSection"].tap()
        let alert = app.alerts["New Section"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.tap(); alert.textFields.firstMatch.typeText("Garnish")
        alert.buttons["Save"].tap()
        let plus = app.buttons["addIngredient-Garnish"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), app.debugDescription)
        let chicken = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "chicken breast")).firstMatch
        XCTAssertTrue(chicken.isHittable)
        let garnish = app.staticTexts["recipeSection-Garnish"].firstMatch
        XCTAssertTrue(garnish.isHittable)
        chicken.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.1,
            thenDragTo: garnish.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            withVelocity: .slow, thenHoldForDuration: 1)
        capture(app, "Ingredient dropped on section heading")
        let movedIngredient = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            chicken.frame.minY > garnish.frame.maxY
        }, object: chicken)
        XCTAssertEqual(XCTWaiter.wait(for: [movedIngredient], timeout: 5), .completed, app.debugDescription)
        let mainHeading = app.staticTexts["recipeSection-Ingredients"].firstMatch
        garnish.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.1,
            thenDragTo: mainHeading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            withVelocity: .slow, thenHoldForDuration: 1)
        let spice = app.staticTexts["recipeSection-Spice mix"].firstMatch
        capture(app, "Section dragged with all its ingredients")
        let movedSection = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            garnish.frame.minY < spice.frame.minY
        }, object: garnish)
        XCTAssertEqual(XCTWaiter.wait(for: [movedSection], timeout: 5), .completed, app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["editRecipe"].waitForExistence(timeout: 5))
        app.buttons["editRecipe"].tap(); app.buttons["editIngredients"].tap()
        XCTAssertTrue(app.staticTexts["Garnish"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThan(garnish.frame.minY, chicken.frame.minY)
        XCTAssertLessThan(chicken.frame.maxY, spice.frame.minY)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["editMethod"].tap()
        XCTAssertTrue(app.buttons["addMethodStep"].waitForExistence(timeout: 5))
        capture(app, "Open method sections with glass controls")
    }

    func testFocusedIngredientEditorAndFullScreenMethod() {
        let app = launch(); openRecipe(app)
        app.buttons["editRecipe"].tap()
        XCTAssertTrue(app.buttons["editIngredients"].waitForExistence(timeout: 5))
        capture(app, "Recipe editor overview")
        app.buttons["editIngredients"].tap()
        // Retry navigation only if the animated sheet is still on the recipe editor.
        if !app.buttons["addIngredient"].waitForExistence(timeout: 3), app.buttons["editIngredients"].exists {
            app.buttons["editIngredients"].tap()
        }
        XCTAssertTrue(app.buttons["addIngredient"].waitForExistence(timeout: 5))
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
        let formattedMatch = NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "formattedName-", "Beef mince (fresh)")
        let nameField = app.textFields.matching(formattedMatch).firstMatch
        let nameView = app.textViews.matching(formattedMatch).firstMatch
        for _ in 0..<3 where !nameField.exists && !nameView.exists { app.swipeUp() }
        let editableName = nameField.exists ? nameField : nameView
        XCTAssertTrue(editableName.waitForExistence(timeout: 5))
        editableName.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        editableName.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Beef mince (fresh)".count) + "Lean beef mince")
        capture(app, "Crossed-out original with editable formatted name")
        app.buttons["applyIngredientFormatting"].tap()
        XCTAssertTrue(app.staticTexts["500 g Lean beef mince"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Cancel"].tap()
        app.swipeUp()
        XCTAssertFalse(app.staticTexts["500 g Lean beef mince"].exists)
    }

    func testMainTagsCreateRenameDeleteAndIndividualEntry() {
        let app = launch()
        app.buttons["Library options"].tap(); app.buttons["manageTags"].tap()
        XCTAssertTrue(app.buttons["newLibraryTag"].waitForExistence(timeout: 5))
        app.buttons["newLibraryTag"].tap()
        let newTag = app.alerts["New Tag"]
        newTag.textFields.firstMatch.typeText("Comfort")
        newTag.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["manageTag-Comfort"].waitForExistence(timeout: 5))
        app.buttons["manageTag-Easy"].tap()
        let rename = app.alerts["Rename Tag"]
        let field = rename.textFields.firstMatch
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Weeknight")
        rename.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["manageTag-Weeknight"].waitForExistence(timeout: 5))
        capture(app, "Main tags screen")
        app.buttons["manageTag-Comfort"].press(forDuration: 1)
        app.buttons["Delete tag"].tap()
        app.alerts["Delete tag?"].buttons["Delete tag"].tap()
        XCTAssertFalse(app.buttons["manageTag-Comfort"].exists)
        app.buttons["Done"].tap()
        openRecipe(app); app.buttons["recipeTags"].tap()
        XCTAssertTrue(app.staticTexts["Weeknight"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Easy"].exists)
        let tagField = app.textFields["recipeTagsText"]
        tagField.tap(); tagField.typeText("Warm, cozy")
        app.buttons["addSingleRecipeTag"].tap()
        XCTAssertTrue(app.staticTexts["Warm, cozy"].waitForExistence(timeout: 5))
        capture(app, "Individual tag entry")
        app.buttons["Save"].tap()
        app.buttons["recipeTags"].tap()
        XCTAssertTrue(app.staticTexts["Warm, cozy"].waitForExistence(timeout: 5))
    }

    func testGroceriesCanClearCheckedAndUncheckedItems() {
        let app = launch()
        app.tabBars.buttons["Groceries"].tap()
        let entry = app.textFields["New grocery item"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap(); entry.typeText("Milk"); app.buttons["Add grocery item"].tap()
        entry.typeText("Eggs"); app.buttons["Add grocery item"].tap()
        let milk = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Milk")).firstMatch
        milk.tap()
        app.buttons["Grocery options"].tap(); app.buttons["clearAllGroceries"].tap()
        XCTAssertTrue(app.alerts["Clear all groceries?"].waitForExistence(timeout: 5))
        capture(app, "Clear every grocery item confirmation")
        app.alerts["Clear all groceries?"].buttons["Cancel"].tap()
        XCTAssertTrue(milk.exists)
        app.buttons["Grocery options"].tap(); app.buttons["clearAllGroceries"].tap()
        app.alerts["Clear all groceries?"].buttons["Clear all items"].tap()
        XCTAssertTrue(app.staticTexts["Your grocery list is empty"].waitForExistence(timeout: 5))
    }

    func testTagsSheetAndSimpleGrocerySelection() {
        let app = launch(dark: true); openRecipe(app)
        XCTAssertFalse(app.staticTexts["Easy"].exists)
        app.buttons["recipeTags"].tap()
        XCTAssertTrue(app.staticTexts["Easy"].waitForExistence(timeout: 5))
        capture(app, "Recipe tags sheet")
        let tagField = app.textFields["recipeTagsText"]
        let tagInput = tagField.exists ? tagField : app.textViews["recipeTagsText"]
        XCTAssertTrue(tagInput.waitForExistence(timeout: 5))
        tagInput.tap(); tagInput.typeText("Weeknight")
        XCTAssertEqual(tagInput.value as? String, "Weeknight")
        app.buttons["addSingleRecipeTag"].tap()
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
