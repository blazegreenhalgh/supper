#if SWIFT_PACKAGE
import SupperCore
#endif
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
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.setOption(Self.migrationManager(), forKey: NSPersistentStoreStagedMigrationManagerOptionKey)

            if inMemory {
                description.type = NSInMemoryStoreType
            } else {
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                #if os(iOS)
                description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
                #endif
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
        let model = legacyModel()
        func add(_ entity: String, _ name: String, _ type: NSAttributeType) {
            let attribute = NSAttributeDescription(); attribute.name = name
            attribute.attributeType = type; attribute.isOptional = true
            model.entitiesByName[entity]!.properties.append(attribute)
        }
        add("Recipe", "collectionIDsJSON", .stringAttributeType)
        add("Ingredient", "groupName", .stringAttributeType)
        add("Ingredient", "categoryOverride", .stringAttributeType)
        add("Reaction", "updatedAt", .dateAttributeType)
        add("GroceryItem", "operationKey", .stringAttributeType)
        add("GroceryItem", "removed", .booleanAttributeType)
        add("GroceryItem", "categoryOverride", .stringAttributeType)
        func child(_ name: String, _ className: String, _ inverse: String) {
            let entity = NSEntityDescription(); entity.name = name; entity.managedObjectClassName = className
            model.entities.append(entity)
            let library = model.entitiesByName["SupperLibrary"]!
            let toRoot = NSRelationshipDescription(); toRoot.name = "library"; toRoot.destinationEntity = library
            toRoot.minCount = 0; toRoot.maxCount = 1; toRoot.isOptional = true; toRoot.deleteRule = .nullifyDeleteRule
            let children = NSRelationshipDescription(); children.name = inverse; children.destinationEntity = entity
            children.minCount = 0; children.maxCount = 0; children.isOptional = true; children.deleteRule = .cascadeDeleteRule
            children.inverseRelationship = toRoot; toRoot.inverseRelationship = children
            library.properties.append(children); entity.properties.append(toRoot)
        }
        child("RecipeCollection", "RecipeCollectionMO", "collections")
        add("RecipeCollection", "id", .UUIDAttributeType); add("RecipeCollection", "name", .stringAttributeType)
        add("RecipeCollection", "isOnHome", .booleanAttributeType); add("RecipeCollection", "order", .integer64AttributeType)
        add("RecipeCollection", "removed", .booleanAttributeType)
        child("HouseholdMember", "HouseholdMemberMO", "members")
        add("HouseholdMember", "id", .stringAttributeType); add("HouseholdMember", "name", .stringAttributeType)
        add("HouseholdMember", "accountID", .stringAttributeType); add("HouseholdMember", "updatedAt", .dateAttributeType)
        return model
    }

    /// Explicit model references make the shipped programmatic v1 model available to Core Data.
    /// Staged lightweight migration retains mirroring metadata and persistent history in place.
    static func migrationManager() -> NSStagedMigrationManager {
        let source = legacyModel(); let destination = model()
        let sourceCoordinator = NSPersistentStoreCoordinator(managedObjectModel: source)
        let destinationCoordinator = NSPersistentStoreCoordinator(managedObjectModel: destination)
        return withExtendedLifetime((sourceCoordinator, destinationCoordinator)) {
            let stage = NSCustomMigrationStage(
                migratingFrom: NSManagedObjectModelReference(model: source, versionChecksum: source.versionChecksum),
                to: NSManagedObjectModelReference(model: destination, versionChecksum: destination.versionChecksum))
            return NSStagedMigrationManager([stage])
        }
    }
}
