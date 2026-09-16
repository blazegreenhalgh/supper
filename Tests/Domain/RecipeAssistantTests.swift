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

private func sauceFixture() -> (RecipeDraft, RecipeDraft, GroundedRecipeEdit) {
    let draft = RecipeDraft(title: "Our creamy beef sauce", servings: 4)
    let source = RecipeDraft(title: "Cream and stock sauce", servings: 4,
        sourceURL: URL(string: "https://recipes.example/cream-sauce")!,
        ingredients: [Ingredient(name: "Beef stock", quantity: "250", unit: "ml"),
                      Ingredient(name: "Cream", quantity: "100", unit: "ml"),
                      Ingredient(name: "Plain flour", quantity: "1", unit: "tbsp"),
                      Ingredient(name: "Pepper", quantity: "1/4", unit: "tsp")],
        steps: [RecipeStep(text: "Whisk the flour into the cold stock. Simmer for 3 minutes, stirring."),
                RecipeStep(text: "Stir in the cream and pepper over low heat. Do not boil.")])
    let edit = GroundedRecipeEdit(outcome: .adapted, sourceIndex: 0, message: "Review this sauce adaptation.",
        baseRationale: "The base uses flour-thickened beef stock and cream; its core amounts and low-heat method are retained.",
        assumptions: ["Sauce yield: four servings, matching the base."],
        ingredientAdaptations: [
            .init(patchIndex: 1, sourceIndex: 1, kind: .substitution, requestedName: "Heavy cream", reason: "Use the requested cream at the source amount."),
            .init(patchIndex: 3, sourceIndex: -1, kind: .seasoning, requestedName: "Soy sauce", reason: "A small suggested amount adds seasoning; taste before adding salt."),
            .init(patchIndex: 4, sourceIndex: -1, kind: .seasoning, requestedName: "Rosemary", reason: "A small suggested amount adds the requested herb.")],
        methodAdaptations: [.init(patchIndex: 1, sourceIndices: [1], reason: "Add soy sauce and rosemary while retaining low heat and the instruction not to boil.")],
        patch: RecipeAssistantPatch(ingredients: [
            .init(operation: .add, name: "Beef stock", quantity: "250", unit: "ml"),
            .init(operation: .add, name: "Heavy cream", quantity: "100", unit: "ml"),
            .init(operation: .add, name: "Plain flour", quantity: "1", unit: "tbsp"),
            .init(operation: .add, name: "Soy sauce", quantity: "1", unit: "tsp"),
            .init(operation: .add, name: "Rosemary", quantity: "1/4", unit: "tsp"),
            .init(operation: .add, name: "Pepper", quantity: "1/4", unit: "tsp")],
            steps: [.init(operation: .add, text: source.steps[0].text),
                    .init(operation: .add, text: "Stir in the heavy cream, soy sauce, rosemary and pepper over low heat. Do not boil.")]))
    return (draft, source, edit)
}

private let sauceRequest = "Find a sauce for four with beef stock, heavy cream, plain flour, soy sauce, pepper and rosemary."

@Test func sauceCanUsePublishedFoundationWithoutExactSeasoningMatch() throws {
    let (draft, source, edit) = sauceFixture()
    let changed = try #require(try edit.validatedDraft(draft, sources: [source], userInput: sauceRequest))
    #expect(changed.ingredients.map(\.quantity) == ["250", "100", "1", "1", "1/4", "1/4"])
    #expect(changed.steps[0].text == source.steps[0].text)
    let notes = edit.adaptationNotes(source: source)
    #expect(notes.contains { $0.contains("estimate") && $0.contains("Soy sauce") })
    #expect(notes.contains { $0.contains("100 ml Cream") && $0.contains("100 ml Heavy cream") })
    let proposal = RecipeAssistantProposal(base: draft, suggested: changed,
        sources: [.init(title: source.title, url: source.sourceURL!)], adaptations: notes, assumptions: edit.assumptions)
    let applied = try proposal.applying(to: draft)
    #expect(applied.notes.contains("not been kitchen-tested"))
    #expect(applied.notes.contains(source.sourceURL!.absoluteString))
    #expect(applied.notes.contains("Sauce yield: four servings"))
    #expect(try RecipeAssistantUndo(before: draft, after: applied).restoring(applied) == draft)
}

@Test func adaptationCannotChangeCoreAmountOrHideAnUndisclosedIngredient() throws {
    let (draft, source, initial) = sauceFixture()
    var edit = initial
    edit.patch.ingredients[1].quantity = "500"
    #expect(throws: (any Error).self) { try edit.validatedDraft(draft, sources: [source], userInput: sauceRequest) }
    edit = initial
    edit.patch.ingredients.append(.init(operation: .add, name: "Cornflour", quantity: "10", unit: "g"))
    #expect(throws: (any Error).self) { try edit.validatedDraft(draft, sources: [source], userInput: sauceRequest) }
    edit = initial
    edit.ingredientAdaptations[2].requestedName = "Thyme"
    edit.patch.ingredients[4].name = "Thyme"
    #expect(throws: (any Error).self) { try edit.validatedDraft(draft, sources: [source], userInput: sauceRequest) }
}

@Test func adaptationRequiresRealSourceAndValidUniqueEvidenceReferences() throws {
    let (draft, source, initial) = sauceFixture()
    #expect(throws: (any Error).self) { try initial.validatedDraft(draft, sources: [], userInput: sauceRequest) }
    var noLink = source; noLink.sourceURL = nil
    #expect(throws: (any Error).self) { try initial.validatedDraft(draft, sources: [noLink], userInput: sauceRequest) }
    var edit = initial; edit.methodAdaptations[0].sourceIndices = [20]
    #expect(throws: (any Error).self) { try edit.validatedDraft(draft, sources: [source], userInput: sauceRequest) }
    edit = initial; edit.methodAdaptations = []
    #expect(throws: (any Error).self) { try edit.validatedDraft(draft, sources: [source], userInput: sauceRequest) }
    edit = initial; edit.ingredientAdaptations.append(edit.ingredientAdaptations[0])
    #expect(throws: (any Error).self) { try edit.validatedDraft(draft, sources: [source], userInput: sauceRequest) }
    edit = initial; edit.outcome = .sourced
    #expect(throws: (any Error).self) { try edit.validatedDraft(draft, sources: [source], userInput: sauceRequest) }
}

@Test func clarificationDoesNotRequireASourceAndCannotSmuggleChanges() throws {
    let draft = RecipeDraft(title: "Our dinner")
    var edit = GroundedRecipeEdit(outcome: .clarification, sourceIndex: -1, message: "How many people is this for?",
        baseRationale: "", assumptions: [], ingredientAdaptations: [], methodAdaptations: [], patch: .init())
    #expect(try edit.validatedDraft(draft, sources: [], userInput: "Find ingredients and a method") == nil)
    edit.patch.servings = 4
    #expect(throws: (any Error).self) { try edit.validatedDraft(draft, sources: [], userInput: "Find ingredients and a method") }
    #expect(draft.servings == nil)
}

@Test func followupRetainsEarlierUserIngredientsButAssistantTextCannotAuthorizeThem() throws {
    let (draft, source, edit) = sauceFixture()
    #expect(throws: (any Error).self) { try edit.validatedDraft(draft, sources: [source], userInput: "Four people") }
    #expect(try edit.validatedDraft(draft, sources: [source], userInput: sauceRequest + "\nFour people") != nil)
}

@Test func reviewCannotApproveIfAnyCheckFailsOrAQuestionRemains() throws {
    let keys = ["baseFits", "coreRatiosPreserved", "techniquePreserved", "changesExplained", "ingredientsConsistent", "yieldMatches"]
    var json: [String: Any] = Dictionary(uniqueKeysWithValues: keys.map { ($0, true as Any) })
    json["question"] = ""; json["concern"] = ""
    func decode(_ json: [String: Any]) throws -> RecipeAdaptationReview {
        try JSONDecoder().decode(RecipeAdaptationReview.self, from: JSONSerialization.data(withJSONObject: json))
    }
    #expect(try decode(json).approved)
    for key in keys {
        var rejected = json; rejected[key] = false; rejected["concern"] = "This change is not supported by the base."
        let review = try decode(rejected)
        try review.validate()
        #expect(!review.approved)
    }
    json["question"] = "The base serves six. Would you like to use that yield?"
    #expect(try !decode(json).approved)
}
