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
