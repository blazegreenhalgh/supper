import Foundation
import Testing
@testable import SupperCore

@Test func stepMatchingExpandsExplicitGroupsAndKeepsIngredientIdentity() {
    let beef = Ingredient(name: "Beef mince", quantity: "500", unit: "g")
    let cumin = Ingredient(name: "Cumin", quantity: "1", unit: "tsp", group: "Spice mix")
    let paprika = Ingredient(name: "Paprika", quantity: "½", unit: "tsp", group: "Spice mix")
    let steps = [RecipeStep(text: "Brown the beef mince."), RecipeStep(text: "Add the spice mix."), RecipeStep(text: "Rest for five minutes.")]
    let input = StepIngredientInput(ingredients: [beef, cumin, paprika], steps: steps)
    let result = StepIngredientMatching.explicitMatches(input)
    #expect(result.ingredientIDs[steps[0].id] == [beef.id])
    #expect(result.ingredientIDs[steps[1].id] == [cumin.id, paprika.id])
    #expect(result.ingredients(for: steps[2].id, baseServings: 4, selectedServings: 6).isEmpty)
}

@Test func stepMatchingDoesNotGuessAmbiguousIngredientForms() {
    let ingredients = [Ingredient(name: "Chicken breast"), Ingredient(name: "Chicken thighs"), Ingredient(name: "Tomato paste")]
    let step = RecipeStep(text: "Cook the chicken and tomatoes.")
    let input = StepIngredientInput(ingredients: ingredients, steps: [step])
    #expect(StepIngredientMatching.explicitMatches(input).ingredientIDs.isEmpty)
    #expect(StepIngredientMatching.validatedIDs([-1, 0, 0, 2, 3, 999], input: input) == [ingredients[0].id, ingredients[2].id])
}

@Test func matchedAmountsScaleOriginalQuantitiesAndKeepDistinctGroupIDs() {
    let onion = Ingredient(name: "Onion", quantity: "½", group: "Sauce")
    let topping = Ingredient(name: "Onion", quantity: "1", group: "Topping")
    let salt = Ingredient(name: "Salt", quantity: "to taste")
    let step = RecipeStep(text: "Add sauce ingredients.")
    let input = StepIngredientInput(ingredients: [onion, topping, salt], steps: [step])
    let matches = StepIngredientMatches(input: input, ingredientIDs: [step.id: [onion.id, salt.id]])
    let scaled = matches.ingredients(for: step.id, baseServings: 4, selectedServings: 8)
    #expect(scaled.map(\.id) == [onion.id, salt.id])
    #expect(scaled.map(\.quantity) == ["1", "to taste"])
    #expect(matches.ingredients(for: step.id, baseServings: 4, selectedServings: 4).first?.quantity == "½")
    #expect(matches.ingredients(for: step.id, baseServings: nil, selectedServings: 8).first?.quantity == "½")
    #expect(input.ingredients[0].quantity == "½")
    #expect(input != StepIngredientInput(ingredients: [topping], steps: [step]))
}
