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
