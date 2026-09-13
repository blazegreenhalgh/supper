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
