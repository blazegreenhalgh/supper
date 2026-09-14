import Foundation
import CoreData
import Testing
@testable import SupperCore
@testable import SupperPersistence

@Suite(.serialized) @MainActor struct PersistenceTests {
    func makeStore() async throws -> RecipeStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = RecipeStore(persistence: PersistenceStack(cloudEnabled: false, directory: directory))
        await store.load()
        #expect(store.errorMessage == nil)
        #expect(store.isReady)
        return store
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
        try store.toggleGroceryItem(store.groceryItems[0]); #expect(store.groceryItems.allSatisfy(\.isChecked))
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
    @Test func reactionsNeverOverwriteAnotherMember() async throws {
        let store = try await makeStore(); let recipe = Recipe(title: "Soup"); try store.addRecipe(recipe)
        let context = store.persistence.container.viewContext
        let object = try #require(context.fetch(NSFetchRequest<RecipeMO>(entityName: "Recipe")).first)
        let other = ReactionMO(context: context); other.id = UUID(); other.personID = "another-person"; other.emoji = "❤️"; other.recipe = object
        try context.save()
        try store.setReaction("❤️", for: recipe); #expect(store.recipes[0].reactions.count == 2)
        try store.setReaction("👍", for: recipe); #expect(store.recipes[0].reactions.contains { $0.personID == "another-person" && $0.emoji == "❤️" })
        try store.setReaction(nil, for: recipe); #expect(store.recipes[0].reactions.count == 1)
    }
    @Test func householdQueriesAndNewObjectsStayScoped() async throws {
        let store = try await makeStore(); let first = try #require(store.activeHouseholdID)
        try store.addRecipe(Recipe(title: "Private"))
        let context = store.persistence.container.viewContext
        let other = SupperLibraryMO(context: context); context.assign(other, to: try #require(store.persistence.sharedStore))
        other.id = UUID(); other.name = "Shared"; other.createdAt = Date(); try context.save()
        try store.selectHousehold(try #require(other.id)); #expect(store.recipes.isEmpty)
        try store.addRecipe(Recipe(title: "Shared recipe", ingredients: [Ingredient(name: "onion")]))
        let objects = try context.fetch(NSFetchRequest<RecipeMO>(entityName: "Recipe"))
        let sharedRecipe = try #require(objects.first { $0.title == "Shared recipe" })
        #expect(sharedRecipe.objectID.persistentStore == store.persistence.sharedStore)
        #expect((sharedRecipe.ingredients?.allObjects.first as? IngredientMO)?.objectID.persistentStore == store.persistence.sharedStore)
        try store.selectHousehold(first); #expect(store.recipes.map(\.title) == ["Private"])
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
