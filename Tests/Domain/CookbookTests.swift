import Foundation
import Testing
@testable import SupperCore

@Test func fractionsDecimalsRangesAndUnknowns() throws {
    for (text, expected) in [("0.5", 0.5), ("1/2", 0.5), ("1 1/2", 1.5), ("1½", 1.5), ("⅔", 2.0/3), ("1⁄4", 0.25)] {
        #expect(abs(try #require(RecipeQuantity.parse(text)).lower - expected) < 0.00001)
    }
    #expect(RecipeQuantity.parse("1–2")?.scaled(by: 1.5).formatted == "1 ½–3")
    #expect(RecipeQuantity.parse("1 to 2")?.upper == 2)
    for text in ["to taste", "a handful", "1/0", "1 potato", "-2", "2 3", "", "NaN"] { #expect(RecipeQuantity.parse(text) == nil) }
    #expect(Ingredient(name: "salt", quantity: "to taste").scaled(from: 4, to: 6).quantity == "to taste")
    #expect(Ingredient(name: "flour", quantity: "1/2", unit: "cup").scaled(from: 4, to: 6).quantity == "¾")
}
@Test func scalingUsesOriginalAndRequiresBase() {
    let original = Ingredient(name: "flour", quantity: "500", unit: "g")
    #expect(original.scaled(from: 4, to: 6).quantity == "750")
    #expect(original.scaled(from: 4, to: 4) == original)
    #expect(original.scaled(from: nil, to: 6) == original)
    #expect(original.scaled(from: 0, to: 6) == original)
    #expect(original.quantity == "500")
}
@Test func parsesIngredientLineWithoutLosingForms() {
    let parsed = IngredientLineParser.parse("1 1/2 tbsp olive oil")
    #expect(parsed.name == "olive oil"); #expect(parsed.quantity == "1 1/2"); #expect(parsed.unit == "tbsp")
    #expect(IngredientLineParser.parse("500g chicken breast").name == "chicken breast")
    #expect(IngredientLineParser.parse("½ tsp cumin").quantity == "½")
    #expect(IngredientLineParser.parse("1 lb / 500 g mince").quantity.isEmpty)
    #expect(IngredientLineParser.parse("2 x 400 g tins tomatoes").quantity.isEmpty)
    #expect(IngredientLineParser.parse("3 garlic cloves, minced").name == "garlic cloves, minced")
}
@Test func groceryMergingIsUnitAwareAndConservative() {
    let a = UUID(), b = UUID()
    let rows = GroceryMerging.merge([
        GroceryItem(name: "Chicken breast", quantity: "500", unit: "g", sourceRecipeIDs: [a]),
        GroceryItem(name: " chicken   breasts ", quantity: "750", unit: "grams", sourceRecipeIDs: [b])
    ])
    #expect(rows.count == 1); #expect(rows[0].quantity == "1.25"); #expect(rows[0].unit == "kg")
    #expect(Set(rows[0].sourceRecipeIDs) == [a, b]); #expect(rows[0].contributionIDs.count == 2)
    let milk = GroceryMerging.merge([GroceryItem(name: "milk", quantity: "500", unit: "ml"), GroceryItem(name: "milk", quantity: "1", unit: "litre")])
    #expect(milk[0].quantity == "1.5"); #expect(milk[0].unit == "l")
    let eggs = GroceryMerging.merge([GroceryItem(name: "eggs", quantity: "2"), GroceryItem(name: "egg", quantity: "3", unit: "each")])
    #expect(eggs.count == 1); #expect(eggs[0].quantity == "5")
    let distinct = GroceryMerging.merge([
        GroceryItem(name: "chicken breast", quantity: "500", unit: "g"), GroceryItem(name: "chicken thighs", quantity: "500", unit: "g"),
        GroceryItem(name: "fresh tomatoes", quantity: "2"), GroceryItem(name: "tomato paste", quantity: "2"),
        GroceryItem(name: "flour", quantity: "1", unit: "cup"), GroceryItem(name: "flour", quantity: "1", unit: "cup"),
        GroceryItem(name: "milk", quantity: "500", unit: "g"), GroceryItem(name: "milk", quantity: "500", unit: "ml"),
        GroceryItem(name: "salt", quantity: "to taste"), GroceryItem(name: "salt", quantity: "a pinch")
    ])
    #expect(distinct.count == 10)
    #expect(GroceryMerging.merge([GroceryItem(name: "apple", quantity: "1", categoryOverride: .pantry), GroceryItem(name: "apple", quantity: "1")]).count == 2)
}
@Test func groupsFromMetadataAndSourceHeadingsArePreserved() throws {
    let parser = RecipeDocumentParser(); let url = URL(string: "https://example.com/chilli")!
    let html = #"<script type="application/ld+json">{"@type":"Recipe","name":"Chilli","recipeIngredient":["1 tsp cumin","500 g beef mince"],"recipeInstructions":[{"@type":"HowToStep","text":"Cook."}]}</script><h2>Ingredients</h2><h3>Spice mix</h3><ul><li>1 tsp cumin</li></ul><h3>Chilli</h3><ul><li>500 g beef mince</li></ul><h2>Method</h2><ol><li>Cook</li></ol>"#
    let draft = try parser.parse(html: html, sourceURL: url)
    #expect(draft.ingredients.map(\.group) == ["Spice mix", "Chilli"])
    #expect(draft.ingredients[0].quantity == "1"); #expect(draft.sourceURL == url)
    let nested = #"<script type="application/ld+json">{"@type":"Recipe","name":"Chilli","recipeIngredient":[{"name":"Spice mix","itemListElement":["1 tsp cumin"]},"1 onion"]}</script>"#
    #expect(try parser.parse(html: nested, sourceURL: url).ingredients.map(\.group) == ["Spice mix", ""])
    let plain = IngredientSection.sections([Ingredient(name: "cumin"), Ingredient(name: "beef")])
    #expect(plain.count == 1); #expect(plain[0].title == "Ingredients")
}
@Test func groupRecoveryNeverChangesEditedAmountsOrAmbiguousNames() {
    let edited = Ingredient(name: "cumin", quantity: "3", unit: "tsp", group: "My mix")
    let imported = Ingredient(name: "cumin", quantity: "1", unit: "tsp", group: "Spice mix")
    #expect(GroupRecovery.suggestions(for: [edited], recovered: [imported])[edited.id] == "Spice mix")
    #expect(GroupRecovery.applyUnambiguous(to: [edited], recovered: [imported])[0] == edited)
    #expect(GroupRecovery.suggestions(for: [edited], recovered: [imported, imported]).isEmpty)
}
@Test func draftsPreserveRecipeIdentityReactionsAndChildIDs() {
    let original = Recipe(title: "Before", ingredients: [Ingredient(name: "onion")], steps: [RecipeStep(text: "Cut")], reactions: [RecipeReaction(personID: "Alice", emoji: "❤️")])
    var draft = RecipeDraft(recipe: original); draft.title = "After"; draft.ingredients[0].quantity = "2"
    let saved = draft.applying(to: original)
    #expect(saved.id == original.id); #expect(saved.createdAt == original.createdAt); #expect(saved.reactions == original.reactions)
    #expect(saved.ingredients[0].id == original.ingredients[0].id); #expect(saved.steps[0].id == original.steps[0].id)
    #expect(original.ingredients[0].quantity.isEmpty)
}
@Test func collectionsAndCombinedFiltersUseSamePredicate() {
    let a = RecipeCollection(name: "Weeknights"), b = RecipeCollection(name: "Family")
    let recipe = Recipe(title: "Chicken", durationMinutes: 25, tags: ["Easy"], notes: "A favourite", ingredients: [Ingredient(name: "lemon")], reactions: [RecipeReaction(personID: "alice", emoji: "❤️")], collectionIDs: [a.id, b.id])
    var filter = RecipeFilter(); filter.query = "lemon weeknights favourite"; filter.maximumMinutes = 30; filter.tags = ["easy"]; filter.collectionIDs = [a.id, b.id]; filter.reaction = .mine
    #expect(filter.matches(recipe, collections: [a, b], memberID: "alice"))
    #expect(!filter.matches(recipe, collections: [a, b], memberID: "bob"))
    filter.maximumMinutes = 20; #expect(!filter.matches(recipe, collections: [a, b], memberID: "alice"))
    #expect(RecipeDraft(recipe: recipe).makeRecipe().collectionIDs.count == 2)
    let natural = RecipeFilter.naturalLanguage("easy chicken under 30 minutes")
    #expect(natural.query == "chicken"); #expect(natural.maximumMinutes == 29); #expect(natural.tags == ["Easy"])
}
@Test func reactionsUseMembersNotEmojiAndRespectRemoval() {
    let members = [HouseholdMember(id: "a", name: "Alice", accountID: "appleA"), HouseholdMember(id: "b", name: "Alice's iPad", accountID: "appleA"), HouseholdMember(id: "c", name: "Bob", accountID: "appleB")]
    let reactions = [RecipeReaction(personID: "a", emoji: "👍"), RecipeReaction(personID: "b", emoji: "❤️", updatedAt: Date()), RecipeReaction(personID: "c", emoji: "❤️")]
    let deduped = ReactionIdentity.deduplicated(reactions, members: members)
    #expect(deduped.count == 2); #expect(deduped.allSatisfy { $0.emoji == "❤️" })
    let removed = RecipeReaction(personID: "a", emoji: "", updatedAt: Date().addingTimeInterval(10))
    #expect(ReactionIdentity.deduplicated(reactions + [removed], members: members).count == 1)
    #expect(ReactionIdentity.canonical("me", members: members) == "me")
}
@Test func randomPickerAvoidsImmediateRepeatAndHandlesEmpty() {
    let a = Recipe(title: "A"), b = Recipe(title: "B")
    #expect(RecipePicker.pick(from: [], excluding: nil) == nil)
    #expect(RecipePicker.pick(from: [a], excluding: a.id)?.id == a.id)
    for _ in 0..<20 { #expect(RecipePicker.pick(from: [a, b], excluding: a.id)?.id == b.id) }
}
