import CoreData
import CloudKit

final class PersistenceStack {
    let container: NSPersistentCloudKitContainer
    let cloudEnabled: Bool
    let containerIdentifier: String

    private let privateURL: URL
    private let sharedURL: URL

    init(cloudEnabled: Bool = true, inMemory: Bool = false, directory: URL? = nil) {
        self.cloudEnabled = cloudEnabled
        self.containerIdentifier = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String
            ?? "iCloud.com.blazegreenhalgh.Supper"

        let directory = directory ?? NSPersistentContainer.defaultDirectoryURL()
        privateURL = directory.appendingPathComponent("Supper-private.sqlite")
        sharedURL = directory.appendingPathComponent("Supper-shared.sqlite")

        container = NSPersistentCloudKitContainer(name: "Supper", managedObjectModel: Self.model())
        container.persistentStoreDescriptions = [
            (privateURL, CKDatabase.Scope.private),
            (sharedURL, CKDatabase.Scope.shared)
        ].map { url, scope in
            let description = NSPersistentStoreDescription(url: url)
            description.shouldAddStoreAsynchronously = true

            if inMemory {
                description.type = NSInMemoryStoreType
            } else {
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
            }

            if cloudEnabled {
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
                options.databaseScope = scope
                description.cloudKitContainerOptions = options
            }
            return description
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "Supper"
    }

    var privateStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStore(for: privateURL)
    }

    var sharedStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStore(for: sharedURL)
    }

    func load() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var remaining = container.persistentStoreDescriptions.count
            var firstError: Error?

            container.loadPersistentStores { _, error in
                lock.lock()
                if let error, firstError == nil { firstError = error }
                remaining -= 1
                let finished = remaining == 0
                let capturedError = firstError
                lock.unlock()

                if finished {
                    if let capturedError { continuation.resume(throwing: capturedError) }
                    else { continuation.resume() }
                }
            }
        }
    }

    static func model() -> NSManagedObjectModel {
        func entity(_ name: String, _ className: String) -> NSEntityDescription {
            let entity = NSEntityDescription()
            entity.name = name
            entity.managedObjectClassName = className
            return entity
        }

        func attribute(_ name: String, _ type: NSAttributeType, external: Bool = false) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = true
            if external { attribute.allowsExternalBinaryDataStorage = true }
            return attribute
        }

        func relationship(
            _ name: String,
            destination: NSEntityDescription,
            toMany: Bool,
            deleteRule: NSDeleteRule
        ) -> NSRelationshipDescription {
            let relationship = NSRelationshipDescription()
            relationship.name = name
            relationship.destinationEntity = destination
            relationship.minCount = 0
            relationship.maxCount = toMany ? 0 : 1
            relationship.isOptional = true
            relationship.isOrdered = false
            relationship.deleteRule = deleteRule
            return relationship
        }

        let library = entity("SupperLibrary", "SupperLibraryMO")
        let recipe = entity("Recipe", "RecipeMO")
        let ingredient = entity("Ingredient", "IngredientMO")
        let step = entity("RecipeStep", "RecipeStepMO")
        let reaction = entity("Reaction", "ReactionMO")
        let grocery = entity("GroceryItem", "GroceryItemMO")

        library.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("createdAt", .dateAttributeType)
        ]

        recipe.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("imageData", .binaryDataAttributeType, external: true),
            attribute("durationMinutes", .integer64AttributeType),
            attribute("servings", .integer64AttributeType),
            attribute("tagsJSON", .stringAttributeType),
            attribute("notes", .stringAttributeType),
            attribute("sourceURL", .stringAttributeType),
            attribute("createdAt", .dateAttributeType)
        ]

        ingredient.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("quantity", .stringAttributeType),
            attribute("unit", .stringAttributeType),
            attribute("order", .integer64AttributeType)
        ]

        step.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("text", .stringAttributeType),
            attribute("order", .integer64AttributeType)
        ]

        reaction.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("personID", .stringAttributeType),
            attribute("emoji", .stringAttributeType)
        ]

        grocery.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("quantity", .stringAttributeType),
            attribute("unit", .stringAttributeType),
            attribute("isChecked", .booleanAttributeType),
            attribute("sourceRecipeIDsJSON", .stringAttributeType),
            attribute("order", .integer64AttributeType)
        ]

        let libraryRecipes = relationship("recipes", destination: recipe, toMany: true, deleteRule: .cascadeDeleteRule)
        let recipeLibrary = relationship("library", destination: library, toMany: false, deleteRule: .nullifyDeleteRule)
        libraryRecipes.inverseRelationship = recipeLibrary
        recipeLibrary.inverseRelationship = libraryRecipes
        library.properties.append(libraryRecipes)
        recipe.properties.append(recipeLibrary)

        let recipeIngredients = relationship("ingredients", destination: ingredient, toMany: true, deleteRule: .cascadeDeleteRule)
        let ingredientRecipe = relationship("recipe", destination: recipe, toMany: false, deleteRule: .nullifyDeleteRule)
        recipeIngredients.inverseRelationship = ingredientRecipe
        ingredientRecipe.inverseRelationship = recipeIngredients
        recipe.properties.append(recipeIngredients)
        ingredient.properties.append(ingredientRecipe)

        let recipeSteps = relationship("steps", destination: step, toMany: true, deleteRule: .cascadeDeleteRule)
        let stepRecipe = relationship("recipe", destination: recipe, toMany: false, deleteRule: .nullifyDeleteRule)
        recipeSteps.inverseRelationship = stepRecipe
        stepRecipe.inverseRelationship = recipeSteps
        recipe.properties.append(recipeSteps)
        step.properties.append(stepRecipe)

        let recipeReactions = relationship("reactions", destination: reaction, toMany: true, deleteRule: .cascadeDeleteRule)
        let reactionRecipe = relationship("recipe", destination: recipe, toMany: false, deleteRule: .nullifyDeleteRule)
        recipeReactions.inverseRelationship = reactionRecipe
        reactionRecipe.inverseRelationship = recipeReactions
        recipe.properties.append(recipeReactions)
        reaction.properties.append(reactionRecipe)

        let libraryGroceries = relationship("groceryItems", destination: grocery, toMany: true, deleteRule: .cascadeDeleteRule)
        let groceryLibrary = relationship("library", destination: library, toMany: false, deleteRule: .nullifyDeleteRule)
        libraryGroceries.inverseRelationship = groceryLibrary
        groceryLibrary.inverseRelationship = libraryGroceries
        library.properties.append(libraryGroceries)
        grocery.properties.append(groceryLibrary)

        let model = NSManagedObjectModel()
        model.entities = [library, recipe, ingredient, step, reaction, grocery]
        return model
    }
}
