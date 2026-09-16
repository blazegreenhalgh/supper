import Foundation
import CoreData
import CloudKit
import Testing
@testable import SupperCore
@testable import SupperPersistence

@Suite(.serialized) @MainActor struct PersistenceTests {
    func makeStore() async throws -> RecipeStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferences = try #require(UserDefaults(suiteName: "SupperTests-" + UUID().uuidString))
        let store = RecipeStore(persistence: PersistenceStack(cloudEnabled: false, directory: directory), preferences: preferences)
        await store.load()
        #expect(store.errorMessage == nil)
        #expect(store.isReady)
        return store
    }
    @Test func tagCatalogRenamesMergesAndDeletesAcrossRecipes() async throws {
        let store = try await makeStore()
        let collection = RecipeCollection(name: "Favourites", isOnHome: true)
        try store.saveCollection(collection)
        let soup = Recipe(title: "Soup", tags: ["Easy", "Dinner"], ingredients: [Ingredient(name: "Carrot", quantity: "2")], collectionIDs: [collection.id])
        let pasta = Recipe(title: "Pasta", tags: ["easy", "Quick"])
        try store.addRecipe(soup); try store.addRecipe(pasta)
        try store.setReaction("❤️", for: soup)
        try store.saveTag("Comfort")
        try store.saveTag("Sweet, salty")
        try store.saveTag("Easy")
        try store.saveTag("Weeknight", replacing: "Easy")
        store.persistence.container.viewContext.refreshAllObjects()
        try store.refresh()
        #expect(store.tags.contains("Comfort"))
        #expect(store.tags.contains("Sweet, salty"))
        #expect(!store.tags.contains("Sweet"))
        #expect(store.recipes.allSatisfy { $0.tags.contains("Weeknight") })
        #expect(store.collections.map(\.id) == [RecipeCollection.exploreID, collection.id])
        #expect(store.collectionSections.count == 2)
        try store.reorderCollections([RecipeCollection.allRecipesID, collection.id])
        #expect(store.tags.contains("Comfort"))
        try store.saveTag("Dinner", replacing: "Weeknight")
        let saved = try #require(store.recipes.first { $0.id == soup.id })
        #expect(saved.tags == ["Dinner"])
        #expect(saved.ingredients == soup.ingredients)
        #expect(saved.collectionIDs == soup.collectionIDs)
        #expect(saved.reactions.count == 1)
        try store.deleteTag("dinner")
        try store.deleteTag("Comfort")
        try store.refresh()
        #expect(store.recipes.first { $0.id == soup.id }?.tags.isEmpty == true)
        #expect(store.recipes.first { $0.id == pasta.id }?.tags == ["Quick"])
        #expect(store.tags == ["Quick", "Sweet, salty"])
        #expect(throws: (any Error).self) { try store.saveTag("  ") }
    }

    @Test func clearAllGroceriesRemovesCheckedAndUncheckedWithoutRevivingRetries() async throws {
        let store = try await makeStore()
        let recipe = Recipe(title: "Lunch")
        let ingredient = Ingredient(name: "Carrot", quantity: "2")
        let operation = UUID()
        try store.addRecipe(recipe)
        try store.addIngredientsToGroceryList(from: recipe, ingredients: [ingredient], operationID: operation)
        try store.toggleGroceryItem(try #require(store.groceryItems.first))
        try store.addGroceryItem(name: "Milk")
        #expect(store.groceryItems.contains { $0.isChecked })
        #expect(store.groceryItems.contains { !$0.isChecked })
        try store.clearAllGroceryItems()
        try store.refresh()
        #expect(store.groceryItems.isEmpty)
        try store.addIngredientsToGroceryList(from: recipe, ingredients: [ingredient], operationID: operation)
        #expect(store.groceryItems.isEmpty)
        #expect(store.recipes.map(\.id) == [recipe.id])
    }

    @Test func editingUpdatesExistingObjectsAndPreservesReactions() async throws {
        let store = try await makeStore()
        let original = Recipe(title: "Soup", servings: 4, ingredients: [Ingredient(name: "carrot", quantity: "2")], steps: [RecipeStep(text: "Chop")])
        try store.addRecipe(original); try store.setReaction("❤️", for: original)
        let context = store.persistence.container.viewContext
        let ingredientRequest = NSFetchRequest<IngredientMO>(entityName: "Ingredient")
        let originalObjectID = try #require(context.fetch(ingredientRequest).first).objectID
        var draft = RecipeDraft(recipe: original); draft.title = "Carrot soup"; draft.ingredients[0].quantity = "3"
        try store.updateRecipe(draft.applying(to: original))
        #expect(store.recipes.count == 1); #expect(store.recipes[0].id == original.id)
        #expect(store.recipes[0].reactions.count == 1)
        #expect(try context.fetch(ingredientRequest).first?.objectID == originalObjectID)
        draft.title = ""; #expect(throws: (any Error).self) { try store.updateRecipe(draft.applying(to: original)) }
        #expect(store.recipes[0].title == "Carrot soup"); #expect(draft.ingredients[0].quantity == "3")
    }
    @Test func assistantSectionsAndSourcesSurvivePersistence() async throws {
        let store = try await makeStore()
        let original = Recipe(title: "Naan bread pizza")
        try store.addRecipe(original)
        let draft = RecipeDraft(recipe: original)
        let changed = try RecipeAssistantPatch(
            ingredients: [.init(operation: .add, name: "Flour", quantity: "300", unit: "g", group: "Naan bread")],
            steps: [.init(operation: .add, text: "Mix the dough.", group: "Naan bread")]).applying(to: draft)
        let source = RecipeAssistantSource(title: "Naan", url: URL(string: "https://www.recipetineats.com/naan-recipe/")!)
        let applied = try RecipeAssistantProposal(base: draft, suggested: changed, sources: [source]).applying(to: draft)
        try store.updateRecipe(applied.applying(to: original))
        try store.refresh()
        let saved = try #require(store.recipes.first)
        #expect(saved.steps[0].group == "Naan bread")
        #expect(saved.steps[0].text == "Mix the dough.")
        #expect(saved.ingredients[0].group == "Naan bread")
        #expect(saved.notes.contains(source.url.absoluteString))
        #expect(saved.id == original.id)
    }
    @Test func groceryRetriesClearAndMultipleSources() async throws {
        let store = try await makeStore(); let a = Recipe(title: "A"), b = Recipe(title: "B")
        try store.addRecipe(a); try store.addRecipe(b)
        let ingredient = Ingredient(name: "chicken breast", quantity: "500", unit: "g")
        let batch = UUID()
        try store.addIngredientsToGroceryList(from: a, ingredients: [ingredient], operationID: batch)
        try store.addIngredientsToGroceryList(from: a, ingredients: [ingredient], operationID: batch)
        #expect(store.groceryItems.count == 1); #expect(store.groceryItems[0].quantity == "500")
        let second = Ingredient(name: "chicken breasts", quantity: "750", unit: "g")
        try store.addIngredientsToGroceryList(from: b, ingredients: [second], operationID: UUID())
        #expect(store.groceryItems[0].quantity == "1.25"); #expect(store.groceryItems[0].sourceRecipeIDs.count == 2)
        try store.toggleGroceryItem(store.groceryItems[0]); #expect(store.groceryItems.allSatisfy { $0.isChecked })
        try store.deleteGroceryItems(at: IndexSet(integer: 0)); #expect(store.groceryItems.isEmpty)
        try store.addIngredientsToGroceryList(from: a, ingredients: [ingredient], operationID: batch)
        #expect(store.groceryItems.isEmpty)
        try store.addIngredientsToGroceryList(from: a, ingredients: [ingredient], operationID: UUID())
        #expect(store.groceryItems.count == 1)
    }
    @Test func collectionMembershipAndDeletionKeepRecipes() async throws {
        let store = try await makeStore(); let a = RecipeCollection(name: "A", isOnHome: true), b = RecipeCollection(name: "B")
        try store.saveCollection(a); try store.saveCollection(b)
        let recipe = Recipe(title: "Soup", collectionIDs: [a.id, b.id]); try store.addRecipe(recipe)
        #expect(store.recipes[0].collectionIDs.count == 2)
        try store.deleteCollection(a.id)
        #expect(store.recipes.count == 1); #expect(store.recipes[0].collectionIDs == [b.id])
    }
    @Test func allRecipesOrderingPersistsWithoutBecomingAMembership() async throws {
        let store = try await makeStore()
        let a = RecipeCollection(name: "Weeknights", isOnHome: true, order: 0)
        let b = RecipeCollection(name: "Baking", isOnHome: true, order: 1)
        try store.saveCollection(a); try store.saveCollection(b)
        try store.reorderCollections([b.id, RecipeCollection.allRecipesID, a.id])
        try store.refresh()
        #expect(store.collectionSections.map(\.id) == [b.id, RecipeCollection.allRecipesID, a.id])
        #expect(store.collections.map(\.id) == [RecipeCollection.exploreID, b.id, a.id])
        #expect(throws: (any Error).self) { try store.deleteCollection(RecipeCollection.allRecipesID) }
        let recipe = Recipe(title: "Soup")
        try store.addRecipe(recipe)
        #expect(throws: (any Error).self) { try store.setMemberships([RecipeCollection.allRecipesID], recipeID: recipe.id) }
        #expect(store.recipes.first?.collectionIDs.isEmpty == true)
        try store.reorderCollections([RecipeCollection.allRecipesID, a.id, b.id])
        try store.refresh()
        #expect(store.collectionSections.first?.id == RecipeCollection.allRecipesID)
    }

    @Test func editorSectionMovesSurviveSavingAndReloading() async throws {
        let store = try await makeStore()
        let recipe = Recipe(title: "Pizza", ingredients: [
            Ingredient(name: "Flour", quantity: "300", unit: "g", group: "Dough"),
            Ingredient(name: "Tomato", quantity: "2", group: "Sauce")
        ], steps: [RecipeStep(text: "Mix dough.", group: "Dough"), RecipeStep(text: "Cook sauce.", group: "Sauce")])
        try store.addRecipe(recipe)
        var draft = RecipeDraft(recipe: recipe)
        let operation1 = draft.ingredientSections.moveSection("Sauce", before: "Dough")
        #expect(operation1)
        let operation2 = draft.methodSections.moveItem(recipe.steps[0].id, to: "Sauce")
        #expect(operation2)
        try store.updateRecipe(draft.applying(to: recipe)); try store.refresh()
        let saved = try #require(store.recipes.first)
        #expect(saved.ingredients.map(\.id) == recipe.ingredients.reversed().map(\.id))
        #expect(saved.ingredients.last?.quantity == "300")
        #expect(saved.steps.map(\.group) == ["Sauce", "Sauce"])
        #expect(saved.steps.map(\.text) == ["Cook sauce.", "Mix dough."])
    }

    @Test func exploreMovesPreserveRecipeAndOtherMemberships() async throws {
        let store = try await makeStore()
        let collection = RecipeCollection(name: "Dinner", isOnHome: true)
        try store.saveCollection(collection)
        let regular = Recipe(title: "Our regular dinner")
        let idea = Recipe(title: "Something new", imageData: Data([1, 2, 3]), tags: ["Easy"],
                          notes: "Try this next week", sourceURL: URL(string: "https://example.com/recipe"),
                          ingredients: [Ingredient(name: "Rice", quantity: "200", unit: "g")],
                          steps: [RecipeStep(text: "Cook the rice.")], collectionIDs: [collection.id])
        try store.addRecipe(regular)
        try store.saveToExplore(idea)
        try store.saveToExplore(idea) // Repeated keep must not make another recipe or collection.
        try store.setReaction("❤️", for: idea)
        let before = try #require(store.recipes.first { $0.id == idea.id })
        #expect(before.isInExplore)
        #expect(store.recipes.first { $0.id == regular.id } == regular)
        #expect(!store.collectionSections.contains { $0.id == RecipeCollection.exploreID })
        let context = store.persistence.container.viewContext
        let objects = try context.fetch(NSFetchRequest<RecipeMO>(entityName: "Recipe"))
        let objectID = try #require(objects.first { $0.id == idea.id }).objectID
        let exploreRecords = try context.fetch(NSFetchRequest<RecipeCollectionMO>(entityName: "RecipeCollection"))
        #expect(exploreRecords.filter { $0.id == RecipeCollection.exploreID }.count == 1)

        try store.setExplore(false, recipeID: idea.id)
        try store.refresh()
        var expected = before
        expected.collectionIDs.remove(RecipeCollection.exploreID)
        #expect(store.recipes.first { $0.id == idea.id } == expected)
        #expect(try context.fetch(NSFetchRequest<RecipeMO>(entityName: "Recipe")).first { $0.id == idea.id }?.objectID == objectID)
        try store.setExplore(true, recipeID: idea.id)
        try store.refresh()
        #expect(store.recipes.first { $0.id == idea.id } == before)
        #expect(store.recipes.count == 2)
        #expect(throws: (any Error).self) { try store.deleteCollection(RecipeCollection.exploreID) }
        #expect(throws: (any Error).self) { try store.saveCollection(.explore) }
    }

    @Test func exploreMembershipSurvivesCollectionSyncArrivingLater() async throws {
        let store = try await makeStore()
        let idea = Recipe(title: "Saved for later")
        try store.saveToExplore(idea)
        let context = store.persistence.container.viewContext
        let object = try #require(context.fetch(NSFetchRequest<RecipeMO>(entityName: "Recipe")).first)
        #expect(RecipeStore.domainRecipe(object, members: [], collections: []).isInExplore)
        // A missing collection record must not change the recipe's destination.
        for collection in try context.fetch(NSFetchRequest<RecipeCollectionMO>(entityName: "RecipeCollection")) {
            context.delete(collection)
        }
        try context.save(); try store.refresh()
        #expect(store.recipes.first?.isInExplore == true)
        #expect(store.collections.filter { $0.id == RecipeCollection.exploreID }.count == 1)
        try store.setMemberships([], recipeID: idea.id)
        #expect(store.recipes.first?.isInExplore == false)
        try store.setMemberships([RecipeCollection.exploreID], recipeID: idea.id)
        #expect(store.recipes.first?.isInExplore == true)
    }

    @Test func chatCollectionsAndCollectionDropsPersistWithoutReplacingContent() async throws {
        let store = try await makeStore()
        let a = RecipeCollection(name: "A"), b = RecipeCollection(name: "B"), c = RecipeCollection(name: "C")
        try store.saveCollection(a); try store.saveCollection(b); try store.saveCollection(c)
        let recipe = Recipe(title: "Soup", ingredients: [Ingredient(name: "Carrot")], collectionIDs: [a.id, c.id])
        try store.addRecipe(recipe)
        let household = try #require(store.activeHouseholdID)
        let draft = RecipeDraft(recipe: recipe)
        let proposal = RecipeCollectionProposal(base: draft.collectionIDs, edit: .init(add: [b.id], remove: []), householdID: household)
        let edited = try proposal.applying(to: draft, collections: store.collections, householdID: household)
        #expect(store.recipes[0].collectionIDs == [a.id, c.id]) // Draft stays local until Save.
        try store.updateRecipe(edited.applying(to: recipe))
        try store.refresh()
        #expect(store.recipes[0].collectionIDs == [a.id, b.id, c.id])
        let drag = RecipeDragItem(recipeID: recipe.id, householdID: household, sourceCollectionID: a.id)
        try store.moveRecipe(drag, to: b.id)
        try store.refresh()
        #expect(store.recipes[0].collectionIDs == [b.id, c.id])
        #expect(store.recipes[0].ingredients == recipe.ingredients)
        #expect(throws: (any Error).self) { try store.moveRecipe(drag, to: b.id) }
        #expect(throws: (any Error).self) { try store.setMemberships([UUID()], recipeID: recipe.id) }
        #expect(store.recipes[0].collectionIDs == [b.id, c.id])
    }
    @Test func reactionsNeverOverwriteAnotherMember() async throws {
        let store = try await makeStore(); let recipe = Recipe(title: "Soup"); try store.addRecipe(recipe)
        let context = store.persistence.container.viewContext
        let object = try #require(context.fetch(NSFetchRequest<RecipeMO>(entityName: "Recipe")).first)
        let other = ReactionMO(entity: NSEntityDescription.entity(forEntityName: "Reaction", in: context)!, insertInto: context); other.id = UUID(); other.personID = "another-person"; other.emoji = "❤️"; other.recipe = object
        try context.save()
        try store.setReaction("❤️", for: recipe); #expect(store.recipes[0].reactions.count == 2)
        try store.setReaction("👍", for: recipe); #expect(store.recipes[0].reactions.contains { $0.personID == "another-person" && $0.emoji == "❤️" })
        try store.setReaction(nil, for: recipe); #expect(store.recipes[0].reactions.count == 1)
    }
    @Test func householdQueriesAndNewObjectsStayScoped() async throws {
        let store = try await makeStore(); let first = try #require(store.activeHouseholdID)
        try store.addRecipe(Recipe(title: "Private"))
        let context = store.persistence.container.viewContext
        let other = SupperLibraryMO(entity: NSEntityDescription.entity(forEntityName: "SupperLibrary", in: context)!, insertInto: context); context.assign(other, to: try #require(store.persistence.sharedStore))
        other.id = UUID(); other.name = "Shared"; other.createdAt = Date(); try context.save()
        try store.selectHousehold(try #require(other.id)); #expect(store.recipes.isEmpty)
        try store.addRecipe(Recipe(title: "Shared recipe", ingredients: [Ingredient(name: "onion")]))
        let objects = try context.fetch(NSFetchRequest<RecipeMO>(entityName: "Recipe"))
        let sharedRecipe = try #require(objects.first { $0.title == "Shared recipe" })
        #expect(sharedRecipe.objectID.persistentStore == store.persistence.sharedStore)
        #expect((sharedRecipe.ingredients?.allObjects.first as? IngredientMO)?.objectID.persistentStore == store.persistence.sharedStore)
        try store.selectHousehold(first); #expect(store.recipes.map(\.title) == ["Private"])
    }
    private func addLibrary(to store: RecipeStore, incoming: Bool = false) throws -> UUID {
        let context = store.persistence.container.viewContext
        let root = SupperLibraryMO(entity: NSEntityDescription.entity(forEntityName: "SupperLibrary", in: context)!, insertInto: context)
        context.assign(root, to: try #require(incoming ? store.persistence.sharedStore : store.persistence.privateStore))
        let id = UUID(); root.id = id; root.name = "Other library"; root.createdAt = Date()
        try context.save(); try store.refresh()
        return id
    }

    @Test func deletingLibraryCascadesOnlyItsGraphAndPreservesSelection() async throws {
        let store = try await makeStore(); let first = try #require(store.activeHouseholdID)
        let recipe = Recipe(title: "Remove me", ingredients: [Ingredient(name: "carrot")], steps: [RecipeStep(text: "Chop")])
        try store.addRecipe(recipe); try store.setReaction("❤️", for: recipe)
        try store.saveCollection(RecipeCollection(name: "Remove collection"))
        try store.addGroceryItem(name: "Remove groceries")
        let second = try addLibrary(to: store)
        try store.selectHousehold(second)
        try store.addRecipe(Recipe(title: "Keep me"))
        try store.addGroceryItem(name: "Keep groceries")
        try await store.removeHousehold(first)
        #expect(store.activeHouseholdID == second)
        #expect(store.households.map(\.id) == [second])
        #expect(store.recipes.map(\.title) == ["Keep me"])
        #expect(store.groceryItems.count == 1)
        let context = store.persistence.container.viewContext
        for entity in ["Ingredient", "RecipeStep", "Reaction", "RecipeCollection"] {
            #expect(try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity)) == 0)
        }
        #expect(try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "HouseholdMember")) == 1)
        #expect(store.removingHouseholdID == nil)
    }

    @Test func deletingActivePrivateLibrarySelectsRemainingSharedLibrary() async throws {
        let store = try await makeStore(); let first = try #require(store.activeHouseholdID)
        let shared = try addLibrary(to: store, incoming: true)
        try store.selectHousehold(shared); try store.addRecipe(Recipe(title: "Shared supper"))
        try store.selectHousehold(first)
        try await store.removeHousehold(first)
        #expect(store.activeHouseholdID == shared)
        #expect(store.households.count == 1)
        #expect(store.recipes.map(\.title) == ["Shared supper"])
    }

    @Test func deletingLastLibraryCreatesUsableEmptyLibrary() async throws {
        let store = try await makeStore(); let first = try #require(store.activeHouseholdID)
        try store.addRecipe(Recipe(title: "Old recipe"))
        try await store.removeHousehold(first)
        #expect(store.activeHouseholdID != first)
        #expect(store.households.count == 1)
        #expect(store.recipes.isEmpty)
        try store.addRecipe(Recipe(title: "New recipe"))
        #expect(store.recipes.map(\.title) == ["New recipe"])
    }

    @Test func missingSharedMetadataNeverDeletesOwnersRecipes() async throws {
        let store = try await makeStore()
        let shared = try addLibrary(to: store, incoming: true)
        try store.selectHousehold(shared); try store.addRecipe(Recipe(title: "Owner's recipe"))
        await #expect(throws: (any Error).self) { try await store.removeHousehold(shared) }
        #expect(store.activeHouseholdID == shared)
        #expect(store.recipes.map(\.title) == ["Owner's recipe"])
        #expect(store.removingHouseholdID == nil)
    }

    @Test func missingInvitationCacheRecoversOnlyTheExactZoneAndOwner() throws {
        let zone = CKRecordZone.ID(zoneName: "Household", ownerName: "owner-a")
        let otherOwner = CKRecordZone.ID(zoneName: "Household", ownerName: "owner-b")
        let share = CKShare(recordZoneID: zone), unrelated = CKShare(recordZoneID: otherOwner)
        let record = CKRecord.ID(recordName: "library", zoneID: zone)
        let recovered = try HouseholdCloudLookup.cachedShare(matching: { nil }, recordID: { record }, shares: { [unrelated, share] })
        #expect(recovered?.recordID == share.recordID)
        let wrongOwner = try HouseholdCloudLookup.cachedShare(matching: { nil }, recordID: { record }, shares: { [unrelated] })
        #expect(wrongOwner == nil)
        let noIdentity = try HouseholdCloudLookup.cachedShare(matching: { nil }, recordID: { nil }, shares: { [share] })
        #expect(noIdentity == nil)
    }

    @Test func failedObjectLookupRecoversFromStoreCacheButDoesNotBecomeUnshared() throws {
        let failure = NSError(domain: NSCocoaErrorDomain, code: 134060)
        let zone = CKRecordZone.ID(zoneName: "Household", ownerName: "owner")
        let record = CKRecord.ID(recordName: "library", zoneID: zone)
        let share = CKShare(recordZoneID: zone)
        let recovered = try HouseholdCloudLookup.cachedShare(matching: { throw failure }, recordID: { record }, shares: { [share] })
        #expect(recovered?.recordID == share.recordID)
        #expect(throws: (any Error).self) {
            try HouseholdCloudLookup.cachedShare(matching: { throw failure }, recordID: { record }, shares: { [] })
        }
    }

    @Test func leavingWithoutCachedShareUsesKnownZoneAndRejectsAmbiguousPurges() throws {
        let zone = CKRecordZone.ID(zoneName: "Library", ownerName: "owner")
        let other = CKRecordZone.ID(zoneName: "Other", ownerName: "owner")
        let plan = try HouseholdRemovalPlan(incoming: true, zoneID: zone, otherZones: [other])
        if case .purge(let target) = plan { #expect(target == zone) }
        else { Issue.record("Incoming library must purge its zone, never delete managed objects") }
        for zones in ([[zone], [nil]] as [[CKRecordZone.ID?]]) {
            #expect(throws: (any Error).self) { try HouseholdRemovalPlan(incoming: true, zoneID: zone, otherZones: zones) }
        }
        #expect(throws: (any Error).self) { try HouseholdRemovalPlan(incoming: true, zoneID: nil, otherZones: []) }
    }

    @Test func hidingBrokenIncomingLibraryIsLocalReversibleAndKeepsOwnersGraph() async throws {
        let store = try await makeStore(); let owned = try #require(store.activeHouseholdID)
        let shared = try addLibrary(to: store, incoming: true)
        try store.selectHousehold(shared)
        try store.addRecipe(Recipe(title: "Owner's recipe", ingredients: [Ingredient(name: "onion")]))
        try store.addGroceryItem(name: "Owner's groceries")
        let context = store.persistence.container.viewContext
        let before = try context.fetch(NSFetchRequest<RecipeMO>(entityName: "Recipe")).map(\.objectID)
        try store.hideIncomingLibrary(shared)
        #expect(store.activeHouseholdID == owned)
        #expect(store.households.map(\.id) == [owned])
        #expect(store.hiddenLibraryCount == 1)
        #expect(!context.hasChanges)
        #expect(try context.fetch(NSFetchRequest<RecipeMO>(entityName: "Recipe")).map(\.objectID) == before)
        #expect(try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "GroceryItem")) == 1)
        try store.ensureLibrary(); try store.refresh()
        #expect(store.households.map(\.id) == [owned])
        #expect(throws: (any Error).self) { try store.selectHousehold(shared) }
        try store.showHiddenLibraries(); try store.selectHousehold(shared)
        #expect(store.hiddenLibraryCount == 0)
        #expect(store.recipes.map(\.title) == ["Owner's recipe"])
        #expect(store.groceryItems.count == 1)
        #expect(throws: (any Error).self) { try store.hideIncomingLibrary(owned) }
    }

    @Test func hiddenLibraryIsNotSelectedAfterVisibleLibraryDeletion() async throws {
        let store = try await makeStore(); let owned = try #require(store.activeHouseholdID)
        let shared = try addLibrary(to: store, incoming: true)
        try store.hideIncomingLibrary(shared)
        try await store.removeHousehold(owned)
        #expect(store.households.count == 1)
        #expect(store.activeHouseholdID != shared)
        #expect(store.activeHouseholdID != owned)
        #expect(store.hiddenLibraryCount == 1)
    }

    @Test func coreDataDiagnosticsExposeDebugReasonAndMultipleUnderlyingErrors() async throws {
        let error = NSError(domain: NSCocoaErrorDomain, code: 134060,
                            userInfo: [NSDebugDescriptionErrorKey: "The object already belongs to a share"])
        #expect(CloudProblem.message(error).contains("134060"))
        #expect(CloudProblem.message(error).contains("already belongs to a share"))
        #expect(CloudProblem.diagnostics(error).contains("already belongs to a share"))
        let nested = NSError(domain: CKErrorDomain, code: CKError.Code.networkUnavailable.rawValue)
        let multiple = NSError(domain: NSCocoaErrorDomain, code: 134400,
                               userInfo: ["NSMultipleUnderlyingErrors": [nested]])
        #expect(CloudProblem.message(multiple).contains("internet connection"))
        let store = try await makeStore()
        store.recordCloudError(error, operation: "Preparing household")
        store.recordCloudError(multiple, operation: "Reading invitation")
        #expect(store.cloudDiagnostics?.contains("Preparing household") == true)
        #expect(store.cloudDiagnostics?.contains("Reading invitation") == true)
        #expect(store.cloudDiagnostics?.contains("134060") == true)
    }

    @Test func removalRejectsStaleIDsAndConcurrentActions() async throws {
        let store = try await makeStore(); let first = try #require(store.activeHouseholdID)
        await #expect(throws: (any Error).self) { try await store.removeHousehold(UUID()) }
        store.shareProgress = "Saving invitation…"
        await #expect(throws: (any Error).self) { try await store.removeHousehold(first) }
        store.shareProgress = nil
        #expect(store.activeHouseholdID == first)
        #expect(store.households.count == 1)
    }

    @Test func cloudCheckHasVisibleFeedbackAndKeepsSharingFailure() async throws {
        let store = try await makeStore()
        store.sharingMessage = "Sharing setup needs an update."
        store.cloudMessage = "Previous sync failure"
        await store.checkCloudAccount()
        #expect(store.cloudAccountMessage?.contains("disabled in this build") == true)
        #expect(store.sharingMessage == "Sharing setup needs an update.")
        #expect(store.cloudMessage == "Previous sync failure")
        #expect(!store.checkingCloudAccount)
    }

    @Test func deployableSchemaMatchesCurrentManagedObjectModel() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let schema = try String(contentsOf: root.appendingPathComponent("Config/CloudKitSchema.ckdb"), encoding: .utf8)
        let model = PersistenceStack.model()
        let fieldPattern = try NSRegularExpression(pattern: #"(?m)^\s+(CD_\w+)\s+(STRING|INT64|TIMESTAMP|BYTES|ASSET)\b"#)
        for entity in model.entities {
            let name = try #require(entity.name)
            let start = try #require(schema.range(of: "RECORD TYPE CD_\(name) ("))
            let tail = String(schema[start.upperBound...])
            let end = try #require(tail.range(of: ");"))
            let block = String(tail[..<end.lowerBound])
            let range = NSRange(block.startIndex..., in: block)
            var actual: [String: String] = [:]
            for match in fieldPattern.matches(in: block, range: range) {
                let key = (block as NSString).substring(with: match.range(at: 1))
                actual[key] = (block as NSString).substring(with: match.range(at: 2))
            }
            var expected = ["CD_entityName": "STRING", "CD_moveReceipt": "BYTES", "CD_moveReceipt_ckAsset": "ASSET"]
            for attribute in entity.attributesByName.values {
                let type: String
                switch attribute.attributeType {
                case .stringAttributeType, .UUIDAttributeType: type = "STRING"
                case .integer64AttributeType, .booleanAttributeType: type = "INT64"
                case .dateAttributeType: type = "TIMESTAMP"
                case .binaryDataAttributeType: type = "BYTES"
                default: Issue.record("Add a CloudKit schema mapping for \(name).\(attribute.name)"); continue
                }
                expected["CD_" + attribute.name] = type
                if attribute.attributeType == .stringAttributeType || attribute.attributeType == .binaryDataAttributeType {
                    expected["CD_" + attribute.name + "_ckAsset"] = "ASSET"
                }
            }
            for relationship in entity.relationshipsByName.values where !relationship.isToMany {
                expected["CD_" + relationship.name] = "STRING"
            }
            #expect(actual == expected, "CloudKit schema differs for \(name)")
        }
        #expect(schema.contains("RECORD TYPE \"cloudkit.share\""))
        #expect(schema.contains("\"cloudkit.title\""))
        #expect(schema.components(separatedBy: "RECORD TYPE ").count - 1 == model.entities.count + 2)
    }

    @Test func productionSchemaErrorIsRecognizedInsidePartialFailure() {
        let missing = NSError(domain: CKErrorDomain, code: CKError.Code.serverRejectedRequest.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Cannot create new type cloudkit.share in production schema"])
        let partial = NSError(domain: CKErrorDomain, code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: ["invitation": missing]])
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134400, userInfo: [NSUnderlyingErrorKey: partial])
        #expect(CloudProblem.isMissingProductionSchema(wrapped))
        #expect(CloudProblem.message(wrapped).contains("deployed to production"))
        #expect(!CloudProblem.message(wrapped).contains("Error saving record"))
        #expect(CloudProblem.diagnostics(wrapped).contains("cloudkit.share"))
        let unrelated = NSError(domain: CKErrorDomain, code: CKError.Code.serverRejectedRequest.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "A different request was rejected"])
        #expect(!CloudProblem.isMissingProductionSchema(unrelated))
    }

    @Test func migratesShippedV1WithoutResettingData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Supper-private.sqlite")
        let legacy = NSPersistentStoreCoordinator(managedObjectModel: PersistenceStack.legacyModel())
        let oldStore = try legacy.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: [NSPersistentHistoryTrackingKey: true])
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType); context.persistentStoreCoordinator = legacy
        let libraryID = UUID(), recipeID = UUID(), ingredientID = UUID()
        let root = NSEntityDescription.insertNewObject(forEntityName: "SupperLibrary", into: context)
        root.setValue(libraryID, forKey: "id"); root.setValue("Original", forKey: "name")
        let recipe = NSEntityDescription.insertNewObject(forEntityName: "Recipe", into: context)
        recipe.setValue(recipeID, forKey: "id"); recipe.setValue("Legacy chilli", forKey: "title"); recipe.setValue(Data([1,2,3]), forKey: "imageData"); recipe.setValue(root, forKey: "library")
        let ingredient = NSEntityDescription.insertNewObject(forEntityName: "Ingredient", into: context)
        ingredient.setValue(ingredientID, forKey: "id"); ingredient.setValue("1 tsp cumin", forKey: "name"); ingredient.setValue(recipe, forKey: "recipe")
        let reaction = NSEntityDescription.insertNewObject(forEntityName: "Reaction", into: context)
        reaction.setValue(UUID(), forKey: "id"); reaction.setValue("me", forKey: "personID"); reaction.setValue("❤️", forKey: "emoji"); reaction.setValue(recipe, forKey: "recipe")
        try context.save(); context.reset(); try legacy.remove(oldStore)
        let stack = PersistenceStack(cloudEnabled: false, directory: directory)
        let store = RecipeStore(persistence: stack); await store.load()
        #expect(store.isReady); #expect(store.errorMessage == nil)
        let migrated = try #require(store.recipes.first)
        #expect(migrated.id == recipeID); #expect(migrated.imageData == Data([1,2,3]))
        #expect(migrated.ingredients[0].id == ingredientID); #expect(migrated.ingredients[0].name == "cumin")
        #expect(migrated.ingredients[0].quantity == "1"); #expect(migrated.reactions[0].personID == "me")
        #expect(store.activeHouseholdID == libraryID)
    }
}
