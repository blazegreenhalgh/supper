import Foundation
import Testing
@testable import SupperCore

@Test func ingredientDisplayTextSkipsEmptyParts() {
    let ingredient = Ingredient(name: "chicken thighs", quantity: "500", unit: "g")
    #expect(ingredient.displayText == "500 g chicken thighs")
}

@Test func quickDraftCanBecomeRecipe() {
    let draft = RecipeDraft(title: "  Pasta  ")
    #expect(draft.makeRecipe().title == "Pasta")
}

@Test func ingredientPresentationRecognizesImportedLines() {
    #expect(IngredientPresentation.matching("3 GARLIC cloves, minced").icon == "🧄")
    #expect(IngredientPresentation.matching("1 red capsicum (bell pepper), diced").icon == "🫑")
    #expect(IngredientPresentation.matching("1 lb / 500 g beef mince").aisle == .meatAndSeafood)
}

@Test func ingredientPresentationPrefersPreparedIngredientsAndWholeWords() {
    #expect(IngredientPresentation.matching("2 beef stock cubes").aisle == .pantry)
    #expect(IngredientPresentation.matching("400 ml coconut milk").aisle == .pantry)
    #expect(IngredientPresentation.matching("1 tsp chilli powder").aisle == .pantry)
    #expect(IngredientPresentation.matching("1 eggplant").aisle == .produce)
    #expect(IngredientPresentation.matching("sweet potato").icon == "🍠")
    #expect(IngredientPresentation.matching("dishwashing liquid").aisle == .other)
}

@Test func sectionMovesKeepRowsAmountsAndIdentityTogether() {
    let flour = Ingredient(name: "Flour", quantity: "300", unit: "g", group: "Dough")
    let salt = Ingredient(name: "Salt", quantity: "1", unit: "tsp", group: "Dough")
    let tomato = Ingredient(name: "Tomato", quantity: "2", group: "Sauce")
    var draft = RecipeDraft(ingredients: [flour, salt, tomato])
    let operation1 = draft.ingredientSections.moveSection("Sauce", before: "Dough")
    #expect(operation1)
    #expect(draft.ingredients.map(\.id) == [tomato.id, flour.id, salt.id])
    let operation2 = draft.ingredientSections.moveItem(salt.id, to: "Sauce", before: tomato.id)
    #expect(operation2)
    #expect(draft.ingredients.map(\.id) == [salt.id, tomato.id, flour.id])
    #expect(draft.ingredients.map(\.group) == ["Sauce", "Sauce", "Dough"])
    #expect(draft.ingredients.map(\.order) == [0, 1, 2])
    #expect(draft.ingredients[0].quantity == "1" && draft.ingredients[0].unit == "tsp")
    let saved = RecipeDraft(recipe: draft.makeRecipe())
    #expect(saved.ingredients == draft.ingredients)
}

@Test func emptySectionsAcceptMovesAndSurviveFormattingInTheDraft() {
    let ingredient = Ingredient(name: "GARLIC", group: "Sauce")
    var content = RecipeSectionedContent(items: [ingredient])
    let operation3 = content.addSection("  Garnish  ") == "Garnish"
    #expect(operation3)
    let operation4 = content.addSection("garnish") == "Garnish"
    #expect(operation4)
    #expect(content.sections.count == 2)
    content.replaceItems(content.flattened.map { IngredientFormatting.proposal(for: $0).proposed })
    #expect(content.sections.last?.title == "Garnish")
    let operation5 = content.moveItem(ingredient.id, to: "Garnish")
    #expect(operation5)
    #expect(content.sections.first?.items.isEmpty == true)
    #expect(content.flattened.first?.group == "Garnish")
    let operation6 = content.renameSection("Garnish", to: "To serve")
    #expect(operation6)
    #expect(content.flattened.first?.group == "To serve")
    let operation7 = !content.renameSection("To serve", to: "sauce")
    #expect(operation7)
    let operation8 = !content.moveItem(UUID(), to: "Sauce")
    #expect(operation8)
    let operation9 = !content.moveItem(ingredient.id, to: "Missing")
    #expect(operation9)
    #expect(content.flattened.count == 1)
}

@Test func methodSectionsMoveAndRenumberWithoutLosingInstructions() {
    let mix = RecipeStep(text: "Mix the dough.", group: "Dough")
    let cook = RecipeStep(text: "Cook the sauce.", group: "Sauce")
    let serve = RecipeStep(text: "Serve warm.", group: "Sauce")
    var draft = RecipeDraft(steps: [mix, cook, serve])
    let operation10 = draft.methodSections.moveItem(serve.id, to: "Dough")
    #expect(operation10)
    let operation11 = draft.methodSections.moveSection("Dough", before: nil)
    #expect(operation11)
    #expect(draft.steps.map(\.id) == [cook.id, mix.id, serve.id])
    #expect(draft.steps.map(\.order) == [0, 1, 2])
    #expect(draft.steps.map { RecipeStep(id: $0.id, storedText: $0.storedText, order: $0.order) } == draft.steps)
}

@Test func aiSectionChangesUseOriginalIndicesUntilAllEditsAreApplied() throws {
    let a = Ingredient(name: "Flour", group: "Dough")
    let b = Ingredient(name: "Oil", group: "Sauce")
    let c = Ingredient(name: "Tomatoes", group: "Sauce")
    let original = RecipeDraft(ingredients: [a, b, c])
    let result = try RecipeAssistantPatch(ingredients: [
        .init(operation: .update, index: 1, name: "Olive oil", quantity: "2", unit: "tbsp", group: "Dough"),
        .init(operation: .update, index: 0, name: "Bread flour", quantity: "300", unit: "g", group: "Sauce"),
        .init(operation: .remove, index: 2)
    ]).applying(to: original)
    #expect(result.ingredients.first { $0.id == a.id }?.name == "Bread flour")
    #expect(result.ingredients.first { $0.id == b.id }?.name == "Olive oil")
    #expect(!result.ingredients.contains { $0.id == c.id })
}
