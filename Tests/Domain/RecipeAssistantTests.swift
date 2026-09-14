import Foundation
import Testing
@testable import SupperCore

private let naanSource = RecipeAssistantSource(title: "Naan", url: URL(string: "https://www.recipetineats.com/naan-recipe/")!)

@Test func assistantBuildsOneComponentWithoutReplacingTheRecipe() throws {
    let pizza = Ingredient(name: "Mozzarella", quantity: "100", unit: "g", group: "Pizza toppings", categoryOverride: .dairyAndEggs)
    let bake = RecipeStep(text: "Add toppings and bake.", group: "Pizza")
    var draft = RecipeDraft(title: "Naan bread pizza", imageData: Data([1, 2]), tags: ["Dinner"], notes: "Our favourite", ingredients: [pizza], steps: [bake])
    draft.collectionIDs = [UUID()]
    let patch = RecipeAssistantPatch(ingredients: [.init(operation: .add, name: "Flour", quantity: "300", unit: "g", group: "Naan bread")],
                                     steps: [.init(operation: .add, text: "Mix the dough.", group: "Naan bread")])
    let result = try patch.applying(to: draft)
    #expect(result.title == draft.title)
    #expect(result.ingredients.first == pizza)
    #expect(result.steps.first == bake)
    #expect(result.imageData == draft.imageData)
    #expect(result.collectionIDs == draft.collectionIDs)
    #expect(result.notes == draft.notes)
    #expect(result.tags == draft.tags)
    #expect(result.ingredients.last?.group == "Naan bread")
    #expect(result.steps.last?.group == "Naan bread")
    #expect(draft.ingredients.count == 1)
}

@Test func assistantUsesOriginalIndicesForMixedRemovalsUpdatesAndAdditions() throws {
    let first = Ingredient(name: "Flour", quantity: "300", unit: "g")
    let second = Ingredient(name: "Yeast", quantity: "1", unit: "tsp")
    let third = Ingredient(name: "Yoghurt", quantity: "100", unit: "g")
    let draft = RecipeDraft(title: "Naan", ingredients: [first, second, third])
    let patch = RecipeAssistantPatch(ingredients: [
        .init(operation: .remove, index: 1),
        .init(operation: .update, index: 2, name: "Yoghurt", quantity: "200", unit: "g"),
        .init(operation: .add, name: "Baking powder", quantity: "1", unit: "tsp")
    ])
    let result = try patch.applying(to: draft)
    #expect(result.ingredients.map(\.name) == ["Flour", "Yoghurt", "Baking powder"])
    #expect(result.ingredients[1].id == third.id)
    #expect(result.ingredients[1].quantity == "200")
    #expect(result.ingredients.map(\.order) == [0, 1, 2])
}

@Test func assistantRejectsInvalidOrDuplicateEditsAtomically() throws {
    let draft = RecipeDraft(title: "Naan", ingredients: [Ingredient(name: "Flour")])
    let badIndex = RecipeAssistantPatch(ingredients: [.init(operation: .add, name: "Salt"), .init(operation: .remove, index: 4)])
    #expect(throws: (any Error).self) { try badIndex.applying(to: draft) }
    let duplicate = RecipeAssistantPatch(ingredients: [.init(operation: .remove, index: 0), .init(operation: .update, index: 0, name: "Flour")])
    #expect(throws: (any Error).self) { try duplicate.applying(to: draft) }
    #expect(throws: (any Error).self) { try RecipeAssistantPatch(steps: [.init(operation: .add, text: " ")]).applying(to: draft) }
    #expect(throws: (any Error).self) { try RecipeAssistantPatch(servings: 0).applying(to: draft) }
    #expect(draft.ingredients.count == 1)
}

@Test func pendingAssistantChangesCanBeRefinedThenAppliedAndUndone() throws {
    let draft = RecipeDraft(title: "Naan bread pizza")
    let first = try RecipeAssistantPatch(ingredients: [.init(operation: .add, name: "Yoghurt", quantity: "100", unit: "g", group: "Naan bread")]).applying(to: draft)
    let refined = try RecipeAssistantPatch(ingredients: [.init(operation: .update, index: 0, name: "Yoghurt", quantity: "200", unit: "g", group: "Naan bread")]).applying(to: first)
    let proposal = RecipeAssistantProposal(base: draft, suggested: refined, sources: [naanSource, naanSource])
    #expect(proposal.sources.count == 1)
    #expect(proposal.changes.count == 1)
    #expect(proposal.changes[0].before == nil)
    #expect(proposal.changes[0].after?.contains("200 g") == true)
    let applied = try proposal.applying(to: draft)
    #expect(applied.notes.contains(naanSource.url.absoluteString))
    let undo = RecipeAssistantUndo(before: draft, after: applied)
    #expect(try undo.restoring(applied) == draft)
    var manuallyEdited = applied; manuallyEdited.title = "My pizza"
    #expect(throws: (any Error).self) { try undo.restoring(manuallyEdited) }
}

@Test func assistantRejectsStaleOrUnsourcedProposals() throws {
    let draft = RecipeDraft(title: "Naan")
    let changed = try RecipeAssistantPatch(servings: 4).applying(to: draft)
    let unsourced = RecipeAssistantProposal(base: draft, suggested: changed, sources: [])
    #expect(throws: (any Error).self) { try unsourced.applying(to: draft) }
    let proposal = RecipeAssistantProposal(base: draft, suggested: changed, sources: [naanSource])
    var newer = draft; newer.ingredients = [Ingredient(name: "Salt")]
    #expect(throws: (any Error).self) { try proposal.applying(to: newer) }
}

@Test func methodGroupsRoundTripAndPlainLegacyStepsRemainReadable() {
    let step = RecipeStep(text: "Mix.\n\nRest for 10 minutes.", order: 2, group: "Naan bread")
    #expect(RecipeStep(id: step.id, storedText: step.storedText, order: step.order) == step)
    let plain = RecipeStep(text: "Mix.\nRest.")
    #expect(plain.storedText == plain.text)
    #expect(RecipeStep(storedText: plain.text).group.isEmpty)
    #expect(RecipeStep(storedText: plain.text).text == plain.text)
}

@Test func onlineMethodSectionsPreserveComponentAndVariantContext() throws {
    let html = #"<script type="application/ld+json">{"@type":"Recipe","name":"Naan","recipeInstructions":[{"@type":"HowToSection","name":"Plain naan","itemListElement":[{"@type":"HowToStep","text":"Mix the dough."},{"@type":"HowToStep","text":"Cook in a pan."}]},{"@type":"HowToSection","name":"Cheese variation","itemListElement":[{"@type":"HowToStep","text":"Fill with cheese before rolling."}]}]}</script>"#
    let draft = try RecipeDocumentParser().parse(html: html, sourceURL: naanSource.url)
    #expect(draft.steps.map(\.group) == ["Plain naan", "Plain naan", "Cheese variation"])
    #expect(draft.steps.map(\.order) == [0, 1, 2])
    #expect(draft.steps.last?.text == "Fill with cheese before rolling.")
}
