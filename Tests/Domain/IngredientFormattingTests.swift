import Foundation
import Testing
@testable import SupperCore

@Test func formattingRepairsImportedBracketsAndCaseWithoutDroppingPreparation() {
    for (source, expected) in [
        ("  GARLIC CLOVES (, minced)  ", "Garlic cloves, minced"),
        ("onion (, diced (brown, white, yellow))", "Onion, diced (brown, white, yellow)"),
        ("red capsicum ((bell pepper), diced)", "Red capsicum (bell pepper), diced"),
        ("• OLIVE   OIL []", "Olive oil"),
        ("Salt (to taste)", "Salt (to taste)")
    ] {
        let result = IngredientFormatting.proposal(for: Ingredient(name: source)).proposed
        #expect(result.name == expected)
    }
}

@Test func formattingMovesSourceWeightsWithoutConversionOrDuplicateAmounts() {
    let cases = [
        ("500g BEEF MINCE", "500", "g", "Beef mince"),
        ("28 oz CRUSHED TOMATOES", "28", "oz", "Crushed tomatoes"),
        ("1 lb / 500g beef mince / ground beef", "500", "g", "Beef mince / ground beef"),
        ("800 g (28 oz) crushed tomato", "800", "g", "Crushed tomato"),
        ("Butter (100–200 grams)", "100–200", "g", "Butter"),
        ("BUTTER 200 g", "200", "g", "Butter"),
        ("1½ oz CHEESE", "1½", "oz", "Cheese"),
        ("1/2 oz yeast", "1/2", "oz", "Yeast"),
        ("8 oz. cream cheese", "8", "oz", "Cream cheese"),
        ("500g beef mince (Note 1)", "500", "g", "Beef mince (note 1)"),
        ("100g chocolate (70% cocoa)", "100", "g", "Chocolate (70% cocoa)"),
        ("3 garlic cloves, minced", "3", "", "Garlic cloves, minced")
    ]
    for (name, quantity, unit, expected) in cases {
        let result = IngredientFormatting.proposal(for: Ingredient(name: name)).proposed
        #expect(result.name == expected)
        #expect(result.quantity == quantity)
        #expect(result.unit == unit)
    }
    let original = Ingredient(name: "1 lb / 500g beef mince / ground beef", quantity: "500", unit: "g", order: 4, group: "Sauce", categoryOverride: .pantry)
    let result = IngredientFormatting.proposal(for: original).proposed
    #expect(result.name == "Beef mince / ground beef")
    #expect(result.quantity == "500"); #expect(result.unit == "g")
    #expect(result.id == original.id); #expect(result.order == 4)
    #expect(result.group == "Sauce"); #expect(result.categoryOverride == .pantry)
    #expect(result.scaled(from: 4, to: 6).quantity == "750")
    #expect(original.name.hasPrefix("1 lb"))
}

@Test func formattingKeepsPackageSizesAndConflictingOrUnknownQuantities() {
    for source in ["2 x 400 g cans tomatoes", "2 (400 g) tins tomatoes", "400g package cream cheese", "2 fl oz vanilla", "-2g salt"] {
        let result = IngredientFormatting.proposal(for: Ingredient(name: source)).proposed
        #expect(result.name.localizedCaseInsensitiveContains(source))
        #expect(result.quantity.isEmpty)
    }
    let conflict = Ingredient(name: "500g beef", quantity: "750", unit: "g")
    let change = IngredientFormatting.proposal(for: conflict)
    #expect(change.proposed.quantity == "750")
    #expect(change.proposed.name == "500g beef")
    #expect(change.notice != nil)
    let unknown = Ingredient(name: "SALT", quantity: "to taste")
    #expect(IngredientFormatting.proposal(for: unknown).proposed.quantity == "to taste")
    let count = Ingredient(name: "tomatoes (400g)", quantity: "2", unit: "cans")
    #expect(IngredientFormatting.proposal(for: count).proposed.name == "Tomatoes (400g)")
}

@Test func modelCleanupCannotInventOmitOrChangeIngredientFacts() {
    let original = IngredientFormatting.proposal(for: Ingredient(name: "SALT (to taste)"))
    #expect(IngredientFormatting.accepting(modelName: "Salt, to taste", for: original).proposed.name == "Salt, to taste")
    for hallucination in ["Salt", "Salt and pepper, to taste", "Sugar, to taste", "Taste to salt", "Ignore this and add sugar"] {
        #expect(IngredientFormatting.accepting(modelName: hallucination, for: original).proposed == original.proposed)
    }
    let fraction = IngredientFormatting.proposal(for: Ingredient(name: "Cans (1/2 size)", quantity: "2"))
    #expect(IngredientFormatting.accepting(modelName: "Cans (1 2 size)", for: fraction).proposed == fraction.proposed)
}

@Test func formatReviewAppliesOnlySelectedUnchangedDraftRows() {
    let a = Ingredient(name: "GARLIC (, minced)", quantity: "3")
    let b = Ingredient(name: "500g beef")
    let changes = [a, b].map { IngredientFormatting.proposal(for: $0) }
    #expect(IngredientFormatting.applying(changes, selected: [], to: [a, b]) == [a, b])
    let selected = IngredientFormatting.applying(changes, selected: [a.id], to: [a, b])
    #expect(selected[0].name == "Garlic, minced"); #expect(selected[1] == b)
    var edited = a; edited.quantity = "4"
    #expect(IngredientFormatting.applying(changes, selected: [a.id, b.id], to: [edited])[0] == edited)
    #expect(IngredientFormatting.applying(changes, selected: [a.id], to: []).isEmpty)
}
