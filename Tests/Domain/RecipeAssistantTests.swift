import Foundation
import Testing
@testable import SupperCore

private let naanSource = RecipeAssistantSource(title: "Naan", url: URL(string: "https://www.recipetineats.com/naan-recipe/")!)

@Test func collectionEditsPreserveContentAndUnrelatedMemberships() throws {
    let a = RecipeCollection(name: "Weeknight"), b = RecipeCollection(name: "Weekend"), c = RecipeCollection(name: "Favourites")
    let household = UUID()
    var draft = RecipeDraft(title: "Soup", ingredients: [Ingredient(name: "Carrot")])
    draft.collectionIDs = [a.id, c.id]
    let proposal = RecipeCollectionProposal(base: draft.collectionIDs, edit: .init(add: [b.id], remove: [a.id]), householdID: household)
    draft.notes = "A manual edit made while the assistant was working"
    let result = try proposal.applying(to: draft, collections: [a, b, c], householdID: household)
    #expect(result.collectionIDs == [b.id, c.id])
    #expect(result.notes == draft.notes)
    #expect(result.ingredients == draft.ingredients)
    #expect(try RecipeAssistantUndo(before: draft, after: result).restoring(result) == draft)
    #expect(throws: (any Error).self) { try proposal.applying(to: result, collections: [a, b, c], householdID: household) }
    #expect(throws: (any Error).self) { try proposal.applying(to: draft, collections: [a, c], householdID: household) }
    #expect(throws: (any Error).self) { try proposal.applying(to: draft, collections: [a, b, c], householdID: UUID()) }
}

@Test func collectionEditsRejectFabricatedConflictingOrAmbiguousOperations() throws {
    let a = UUID(), b = UUID()
    #expect(throws: (any Error).self) { try RecipeCollectionEdit(add: [b], remove: []).applying(to: [], available: [a]) }
    #expect(throws: (any Error).self) { try RecipeCollectionEdit(add: [a], remove: [a]).applying(to: [], available: [a]) }
    #expect(throws: (any Error).self) { try RecipeCollectionEdit(add: [a], remove: [], question: "Which one?").applying(to: [], available: [a]) }
    #expect(try RecipeCollectionEdit(add: [], remove: [], question: "Which collection?").applying(to: [a], available: [a]) == [a])
    #expect(try RecipeCollectionEdit(add: [a, a], remove: []).applying(to: [a], available: [a]) == [a])
}

@Test func collectionDraggingMovesOnlyItsSourceAndAllRecipesDraggingAdds() throws {
    let a = UUID(), b = UUID(), c = UUID(), household = UUID()
    let recipe = Recipe(title: "Soup", collectionIDs: [a, c])
    let drag = RecipeDragItem(recipeID: recipe.id, householdID: household, sourceCollectionID: a)
    let decoded = try JSONDecoder().decode(RecipeDragItem.self, from: JSONEncoder().encode(drag))
    #expect(try decoded.memberships(for: recipe, destination: b, householdID: household, available: [a, b, c]) == [b, c])
    #expect(try drag.memberships(for: recipe, destination: a, householdID: household, available: [a, b, c]) == [a, c])
    let fromAll = RecipeDragItem(recipeID: recipe.id, householdID: household, sourceCollectionID: nil)
    #expect(try fromAll.memberships(for: recipe, destination: b, householdID: household, available: [a, b, c]) == [a, b, c])
    #expect(throws: (any Error).self) { try drag.memberships(for: recipe, destination: b, householdID: UUID(), available: [a, b, c]) }
    #expect(throws: (any Error).self) { try drag.memberships(for: recipe, destination: b, householdID: household, available: [a, c]) }
    var changed = recipe; changed.collectionIDs = [c]
    #expect(throws: (any Error).self) { try drag.memberships(for: changed, destination: b, householdID: household, available: [a, b, c]) }
}

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

@Test func recipePreviewDistinguishesDuplicateRowsAndPreservesRemovedContent() throws {
    let first = Ingredient(name: "Flour", quantity: "300", unit: "g", group: "Dough")
    let second = Ingredient(name: "Flour", quantity: "1", unit: "tbsp", order: 1, group: "To dust")
    let removedStep = RecipeStep(text: "Dust the surface.", group: "Shaping")
    let base = RecipeDraft(title: "Naan", servings: 2, ingredients: [first, second], steps: [removedStep])
    let suggested = try RecipeAssistantPatch(servings: 4, ingredients: [
        .init(operation: .update, index: 0, name: "Flour", quantity: "400", unit: "g", group: "Dough"),
        .init(operation: .remove, index: 1),
        .init(operation: .add, name: "Oil", quantity: "1", unit: "tsp")
    ], steps: [.init(operation: .remove, index: 0), .init(operation: .add, text: "Oil the surface.")]).applying(to: base)
    let proposal = RecipeAssistantProposal(base: base, suggested: suggested, sources: [naanSource])
    let changes = proposal.changes
    #expect(changes.filter { $0.kind == .added }.count == 2)
    #expect(changes.filter { $0.kind == .changed }.count == 2)
    #expect(changes.filter { $0.kind == .removed }.count == 2)
    let removed = try #require(changes.first { $0.id == second.id.uuidString })
    #expect(removed.kind == .removed)
    #expect(removed.before == "To dust · 1 tbsp Flour")
    #expect(removed.after == nil)
    #expect(changes.first { $0.id == first.id.uuidString }?.after == "Dough · 400 g Flour")
    #expect(changes.first { $0.id == removedStep.id.uuidString }?.before == "Shaping · Dust the surface.")
    // Preview is read-only; its clean recipe uses the exact apply result, including sources.
    let preview = try proposal.applying(to: proposal.base)
    #expect(base.ingredients == [first, second])
    #expect(preview.ingredients.map(\.name) == ["Flour", "Oil"])
    #expect(preview.notes.contains(naanSource.url.absoluteString))
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
