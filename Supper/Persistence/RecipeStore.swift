#if SWIFT_PACKAGE
import SupperCore
#endif
import Foundation
import CoreData
import Combine
import CloudKit

@MainActor
final class RecipeStore: ObservableObject {
    static let shared: RecipeStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SupperUITests-" + UUID().uuidString)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return RecipeStore(persistence: PersistenceStack(cloudEnabled: false, directory: directory))
        }
        #endif
        return RecipeStore()
    }()
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var groceryItems: [GroceryItem] = []
    @Published private(set) var collections: [RecipeCollection] = []
    @Published private(set) var members: [HouseholdMember] = []
    @Published private(set) var households: [HouseholdSummary] = []
    @Published private(set) var isReady = false
    @Published var errorMessage: String?
    @Published var cloudMessage: String?
    @Published var shareProgress: String?
    @Published var pendingInvitation: CKShare.Metadata?
    @Published var joiningHousehold = false
    @Published var currentMemberID: String

    let persistence: PersistenceStack
    var library: SupperLibraryMO?
    var queuedInvitations: [CKShare.Metadata] = []
    private var observers: [NSObjectProtocol] = []
    private var loading = false
    let identity: MemberIdentity
    var activeHouseholdID: UUID? { library?.id }
    var activeHousehold: HouseholdSummary? { households.first { $0.id == activeHouseholdID } }
    var currentMemberName: String { members.first { $0.id == currentMemberID }?.name ?? identity.name }

    init(persistence: PersistenceStack = PersistenceStack(), identity: MemberIdentity? = nil) {
        let identity = identity ?? MemberIdentity()
        self.persistence = persistence; self.identity = identity; currentMemberID = identity.id
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func load() async {
        guard !isReady, !loading else { return }
        loading = true; defer { loading = false }
        do {
            try await persistence.load()
            try ensureLibrary()
            try ensureMember()
            try refresh()
            observeChanges()
            isReady = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"), recipes.isEmpty {
                try addRecipe(Recipe(title: "Chicken with rice", durationMinutes: 25, servings: 4, tags: ["Easy"],
                    ingredients: [Ingredient(name: "chicken breast", quantity: "500", unit: "g"), Ingredient(name: "cumin", quantity: "1", unit: "tsp", group: "Spice mix"), Ingredient(name: "onion, finely diced (brown, white or yellow)", quantity: "1")],
                    steps: [RecipeStep(text: "Cook the chicken."), RecipeStep(text: "Serve with rice.", order: 1)]))
            }
            #endif
            if let first = queuedInvitations.first { pendingInvitation = first; queuedInvitations.removeAll() }
            await checkCloudAccount()
        } catch { errorMessage = "Couldn't open your library. Your data is kept. \(error.localizedDescription)" }
    }

    func requireLibrary() throws -> SupperLibraryMO {
        guard let library, !library.isDeleted, library.managedObjectContext != nil else {
            throw SupperError.invalid("Choose a household in Settings, then try again.")
        }
        if persistence.cloudEnabled, !library.objectID.isTemporaryID,
           !persistence.container.canUpdateRecord(forManagedObjectWith: library.objectID) {
            throw SupperError.invalid("This household is read-only or sharing access has changed. Ask its owner for editing access, or choose your private library.")
        }
        return library
    }

    /// All UI writes are atomic. A failure rolls back managed objects, while the editor retains its value draft.
    func mutate(_ action: (NSManagedObjectContext, SupperLibraryMO) throws -> Void) throws {
        let root = try requireLibrary(); let context = persistence.container.viewContext
        do { try action(context, root); if context.hasChanges { try context.save() }; try refresh() }
        catch { context.rollback(); throw error }
    }
    func assign(_ object: NSManagedObject, root: SupperLibraryMO, context: NSManagedObjectContext) {
        if let store = root.objectID.persistentStore ?? persistence.privateStore { context.assign(object, to: store) }
    }

    func addRecipe(_ recipe: Recipe) throws {
        try validate(recipe)
        try mutate { context, root in
            if try fetchRecipeObject(recipe.id, context: context) != nil { return }
            let object = RecipeMO(entity: NSEntityDescription.entity(forEntityName: "Recipe", in: context)!, insertInto: context); assign(object, root: root, context: context)
            object.library = root; apply(recipe, to: object, context: context, root: root)
        }
    }
    func updateRecipe(_ recipe: Recipe) throws {
        try validate(recipe)
        try mutate { context, root in
            guard let object = try fetchRecipeObject(recipe.id, context: context) else {
                throw SupperError.invalid("This recipe is no longer in this household. Keep the editor open to copy your changes.")
            }
            apply(recipe, to: object, context: context, root: root)
        }
    }
    private func validate(_ recipe: Recipe) throws {
        guard !recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SupperError.invalid("Add a recipe title before saving.") }
        guard recipe.servings.map({ $0 > 0 }) ?? true, recipe.durationMinutes.map({ $0 > 0 }) ?? true else {
            throw SupperError.invalid("Servings and duration must be positive, or leave them empty.")
        }
    }
    func deleteRecipe(_ recipe: Recipe) throws {
        try mutate { context, _ in
            guard let object = try fetchRecipeObject(recipe.id, context: context) else { return }
            context.delete(object)
        }
    }

    func addIngredientsToGroceryList(from recipe: Recipe, ingredients: [Ingredient], operationID: UUID) throws {
        try mutate { context, root in
            let request = NSFetchRequest<GroceryItemMO>(entityName: "GroceryItem")
            request.predicate = NSPredicate(format: "library == %@", root)
            let existing = try context.fetch(request)
            var keys = Set(existing.compactMap(\.operationKey)) // Includes tombstones.
            var order = (existing.compactMap { $0.order?.intValue }.max() ?? -1) + 1
            for ingredient in ingredients {
                let key = GroceryMerging.contributionKey(operationID: operationID, ingredientID: ingredient.id)
                guard keys.insert(key).inserted else { continue }
                let item = GroceryItemMO(entity: NSEntityDescription.entity(forEntityName: "GroceryItem", in: context)!, insertInto: context); assign(item, root: root, context: context)
                item.id = UUID(); item.operationKey = key; item.name = ingredient.name
                item.quantity = ingredient.quantity; item.unit = ingredient.unit
                item.categoryOverride = ingredient.categoryOverride?.rawValue
                item.sourceRecipeIDsJSON = Self.encodeUUIDs([recipe.id]); item.isChecked = false; item.removed = false
                item.order = NSNumber(value: order); item.library = root; order += 1
            }
        }
    }
    func addGroceryItem(name: String) throws {
        let ingredient = IngredientLineParser.parse(name)
        guard !ingredient.name.isEmpty else { return }
        try mutate { context, root in
            let item = GroceryItemMO(entity: NSEntityDescription.entity(forEntityName: "GroceryItem", in: context)!, insertInto: context); assign(item, root: root, context: context)
            item.id = UUID(); item.name = ingredient.name; item.quantity = ingredient.quantity; item.unit = ingredient.unit
            item.isChecked = false; item.removed = false; item.library = root
            item.order = NSNumber(value: (groceryItems.map(\.order).max() ?? 0) + 1)
        }
    }
    func toggleGroceryItem(_ item: GroceryItem) throws {
        try changeContributions(item.contributionIDs) { $0.isChecked = NSNumber(value: !item.isChecked) }
    }
    func setGroceryCategory(_ category: GroceryAisle?, item: GroceryItem) throws {
        try changeContributions(item.contributionIDs) { $0.categoryOverride = category?.rawValue }
    }
    func deleteGroceryItems(at offsets: IndexSet) throws {
        let ids = offsets.filter { groceryItems.indices.contains($0) }.flatMap { groceryItems[$0].contributionIDs }
        try changeContributions(ids) { $0.removed = true }
    }
    private func changeContributions(_ ids: [UUID], action: (GroceryItemMO) -> Void) throws {
        try mutate { context, root in
            let request = NSFetchRequest<GroceryItemMO>(entityName: "GroceryItem")
            request.predicate = NSPredicate(format: "library == %@", root)
            let objects = try context.fetch(request)
            let identifiers = Set(ids)
            let keys = Set(objects.filter { identifiers.contains($0.id ?? UUID()) }.compactMap(\.operationKey))
            for object in objects where identifiers.contains(object.id ?? UUID()) || object.operationKey.map({ keys.contains($0) }) == true { action(object) }
        }
    }

    func setReaction(_ emoji: String?, for recipe: Recipe) throws {
        try mutate { context, root in
            guard let object = try fetchRecipeObject(recipe.id, context: context) else { throw SupperError.invalid("Recipe no longer available.") }
            let reactions = object.reactions?.allObjects.compactMap { $0 as? ReactionMO } ?? []
            let own = reactions.filter { ReactionIdentity.canonical($0.personID ?? "", members: members) == currentMemberID }
                .sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
            let reaction = own.first ?? ReactionMO(entity: NSEntityDescription.entity(forEntityName: "Reaction", in: context)!, insertInto: context)
            if reaction.isInserted { assign(reaction, root: root, context: context) }
            reaction.id = reaction.id ?? UUID(); reaction.personID = currentMemberID
            reaction.emoji = emoji ?? ""; reaction.updatedAt = Date(); reaction.recipe = object
            // Keep an empty latest reaction as a removal tombstone across sync races.
            for duplicate in own.dropFirst() { context.delete(duplicate) }
        }
    }
    func memberName(_ id: String) -> String {
        guard id != "me", !id.isEmpty else { return "Previous member" }
        let canonical = ReactionIdentity.canonical(id, members: members)
        return members.first { $0.id == canonical }?.name ?? "Household member"
    }
    func renameMember(_ name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SupperError.invalid("Enter your display name.") }
        try mutate { _, root in
            let objects = root.members?.allObjects.compactMap { $0 as? HouseholdMemberMO } ?? []
            for member in objects where ReactionIdentity.canonical(member.id ?? "", members: members) == currentMemberID {
                member.name = name; member.updatedAt = Date()
            }
        }
        identity.name = name
    }

    func saveCollection(_ collection: RecipeCollection) throws {
        guard !collection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SupperError.invalid("Give the collection a name.") }
        try mutate { context, root in
            let existing = (root.collections?.allObjects as? [RecipeCollectionMO] ?? []).first { $0.id == collection.id }
            let object = existing ?? RecipeCollectionMO(entity: NSEntityDescription.entity(forEntityName: "RecipeCollection", in: context)!, insertInto: context)
            if object.isInserted { assign(object, root: root, context: context) }
            object.id = collection.id; object.name = collection.name; object.isOnHome = NSNumber(value: collection.isOnHome)
            object.order = NSNumber(value: collection.order); object.removed = false; object.library = root
        }
    }
    func deleteCollection(_ id: UUID) throws {
        try mutate { _, root in
            for object in root.collections?.allObjects as? [RecipeCollectionMO] ?? [] where object.id == id { object.removed = true }
        }
    }
    func reorderCollections(_ ids: [UUID]) throws {
        try mutate { _, root in
            for object in root.collections?.allObjects as? [RecipeCollectionMO] ?? [] {
                if let id = object.id, let index = ids.firstIndex(of: id) { object.order = NSNumber(value: index) }
            }
        }
    }
    func setMemberships(_ ids: Set<UUID>, recipeID: UUID) throws {
        try mutate { context, _ in
            guard let recipe = try fetchRecipeObject(recipeID, context: context) else { throw SupperError.invalid("Recipe no longer available.") }
            recipe.collectionIDsJSON = Self.encodeUUIDs(Array(ids))
        }
    }

    private func ensureLibrary() throws {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<SupperLibraryMO>(entityName: "SupperLibrary")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let roots = try context.fetch(request)
        let selected = UserDefaults.standard.string(forKey: "activeHousehold").flatMap(UUID.init(uuidString:))
        if let selected, let root = roots.first(where: { $0.id == selected }) { library = root; return }
        if let root = roots.first(where: { $0.objectID.persistentStore == persistence.privateStore }) { library = root; return }
        guard let store = persistence.privateStore else { throw SupperError.invalid("Your private library isn't ready. Reopen Supper and try again.") }
        let root = SupperLibraryMO(entity: NSEntityDescription.entity(forEntityName: "SupperLibrary", in: context)!, insertInto: context); context.assign(root, to: store)
        root.id = UUID(); root.name = "Our Supper"; root.createdAt = Date()
        try context.save(); library = root
    }
    func selectHousehold(_ id: UUID) throws {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<SupperLibraryMO>(entityName: "SupperLibrary")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let root = try context.fetch(request).first else { throw SupperError.invalid("This household is no longer available. Your other libraries are kept.") }
        library = root; UserDefaults.standard.set(id.uuidString, forKey: "activeHousehold")
        try ensureMember(); try refresh()
    }
    func ensureMember() throws {
        guard let root = library else { return }
        let context = persistence.container.viewContext
        let existing = root.members?.allObjects as? [HouseholdMemberMO] ?? []
        if persistence.cloudEnabled, !persistence.container.canUpdateRecord(forManagedObjectWith: root.objectID) { return }
        let object = existing.first { $0.id == identity.id } ?? HouseholdMemberMO(entity: NSEntityDescription.entity(forEntityName: "HouseholdMember", in: context)!, insertInto: context)
        if object.isInserted { assign(object, root: root, context: context); object.id = identity.id; object.name = identity.name; object.updatedAt = Date(); object.library = root }
        // Only this installation's provisional identity is resolved, never a legacy "me" record.
        if let account = identity.accountID, object.accountID == nil { object.accountID = account }
        if context.hasChanges { try context.save() }
    }

    func refresh() throws {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<SupperLibraryMO>(entityName: "SupperLibrary")
        let roots = try context.fetch(request)
        households = roots.compactMap { root in root.id.map { HouseholdSummary(id: $0, name: root.name ?? "Supper", incoming: root.objectID.persistentStore == persistence.sharedStore) } }
        if let pending = UserDefaults.standard.string(forKey: "pendingShareRecord") {
            for root in roots where root.objectID.persistentStore == persistence.sharedStore {
                if let share = try persistence.container.fetchShares(matching: [root.objectID])[root.objectID], share.recordID.recordName == pending,
                   share.recordID.zoneID.zoneName == UserDefaults.standard.string(forKey: "pendingShareZone"),
                   share.recordID.zoneID.ownerName == UserDefaults.standard.string(forKey: "pendingShareOwner") {
                    library = root; UserDefaults.standard.set(root.id?.uuidString, forKey: "activeHousehold")
                    UserDefaults.standard.removeObject(forKey: "pendingShareRecord"); joiningHousehold = false
                    try ensureMember()
                }
            }
        }
        guard let root = library, roots.contains(where: { $0.objectID == root.objectID }) else {
            recipes = []; groceryItems = []; collections = []; members = []
            cloudMessage = "This household is no longer available. Choose another library in Household settings."
            return
        }
        let memberObjects = root.members?.allObjects as? [HouseholdMemberMO] ?? []
        members = memberObjects.compactMap { object in object.id.map { HouseholdMember(id: $0, name: object.name ?? "Household member", accountID: object.accountID) } }
        currentMemberID = ReactionIdentity.canonical(identity.id, members: members)
        collections = (root.collections?.allObjects as? [RecipeCollectionMO] ?? []).filter { $0.removed?.boolValue != true }.compactMap { object in
            object.id.map { RecipeCollection(id: $0, name: object.name ?? "Collection", isOnHome: object.isOnHome?.boolValue ?? false, order: object.order?.intValue ?? 0) }
        }.sorted { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }
        recipes = (root.recipes?.allObjects as? [RecipeMO] ?? []).map { Self.domainRecipe($0, members: members, collections: collections) }.sorted { $0.createdAt > $1.createdAt }
        let contributions = (root.groceryItems?.allObjects as? [GroceryItemMO] ?? []).filter { $0.removed?.boolValue != true }
        // A repeated operation delivered twice is projected once; a removed copy suppresses retries.
        let removedKeys = Set((root.groceryItems?.allObjects as? [GroceryItemMO] ?? []).filter { $0.removed?.boolValue == true }.compactMap(\.operationKey))
        var seen = Set<String>()
        groceryItems = GroceryMerging.merge(contributions.sorted {
            if ($0.isChecked?.boolValue ?? false) != ($1.isChecked?.boolValue ?? false) { return $0.isChecked?.boolValue == true }
            return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
        }.filter {
            guard let key = $0.operationKey else { return true }
            return !removedKeys.contains(key) && seen.insert(key).inserted
        }.map(Self.domainGroceryItem))
    }

    private func observeChanges() {
        for name in [NSNotification.Name.NSPersistentStoreRemoteChange, NSNotification.Name.NSManagedObjectContextDidSave] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isReady else { return }
                    do { try self.refresh() } catch { self.cloudMessage = error.localizedDescription }
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: persistence.container, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in
                if let error = event.error { self?.cloudMessage = CloudProblem.message(error) }
                else if event.endDate != nil { do { try self?.refresh() } catch { self?.cloudMessage = error.localizedDescription } }
            }
        })
    }
    private func fetchRecipeObject(_ id: UUID, context: NSManagedObjectContext) throws -> RecipeMO? {
        guard let library else { return nil }
        let request = NSFetchRequest<RecipeMO>(entityName: "Recipe")
        request.predicate = NSPredicate(format: "id == %@ AND library == %@", id as CVarArg, library)
        return try context.fetch(request).first
    }
    private func apply(_ recipe: Recipe, to object: RecipeMO, context: NSManagedObjectContext, root: SupperLibraryMO) {
        object.id = recipe.id; object.title = recipe.title; object.imageData = recipe.imageData
        object.durationMinutes = recipe.durationMinutes.map(NSNumber.init(value:)); object.servings = recipe.servings.map(NSNumber.init(value:))
        object.tagsJSON = Self.encodeStrings(recipe.tags); object.notes = recipe.notes; object.sourceURL = recipe.sourceURL?.absoluteString
        object.createdAt = recipe.createdAt; object.collectionIDsJSON = Self.encodeUUIDs(Array(recipe.collectionIDs))
        let oldIngredients = object.ingredients?.allObjects as? [IngredientMO] ?? []
        let ids = Set(recipe.ingredients.map(\.id))
        for child in oldIngredients where !ids.contains(child.id ?? UUID()) { context.delete(child) }
        for (order, ingredient) in recipe.ingredients.enumerated() {
            let child = oldIngredients.first { $0.id == ingredient.id } ?? IngredientMO(entity: NSEntityDescription.entity(forEntityName: "Ingredient", in: context)!, insertInto: context)
            if child.isInserted { assign(child, root: root, context: context) }
            child.id = ingredient.id; child.name = ingredient.name; child.quantity = ingredient.quantity; child.unit = ingredient.unit
            child.order = NSNumber(value: order); child.groupName = ingredient.group; child.categoryOverride = ingredient.categoryOverride?.rawValue; child.recipe = object
        }
        let oldSteps = object.steps?.allObjects as? [RecipeStepMO] ?? []
        let stepIDs = Set(recipe.steps.map(\.id))
        for child in oldSteps where !stepIDs.contains(child.id ?? UUID()) { context.delete(child) }
        for (order, step) in recipe.steps.enumerated() {
            let child = oldSteps.first { $0.id == step.id } ?? RecipeStepMO(entity: NSEntityDescription.entity(forEntityName: "RecipeStep", in: context)!, insertInto: context)
            if child.isInserted { assign(child, root: root, context: context) }
            child.id = step.id; child.text = step.text; child.order = NSNumber(value: order); child.recipe = object
        }
        // Reactions are a separate member-owned operation and are never rewritten by an editor.
    }
    static func domainRecipe(_ object: RecipeMO, members: [HouseholdMember], collections: [RecipeCollection]) -> Recipe {
        let ingredients = (object.ingredients?.allObjects as? [IngredientMO] ?? []).map { item -> Ingredient in
            var value = Ingredient(id: item.id ?? UUID(), name: item.name ?? "", quantity: item.quantity ?? "", unit: item.unit ?? "", order: item.order?.intValue ?? 0, group: item.groupName ?? "", categoryOverride: item.categoryOverride.flatMap(GroceryAisle.init(rawValue:)))
            if value.quantity.isEmpty && value.unit.isEmpty {
                let parsed = IngredientLineParser.parse(value.name, id: value.id, order: value.order, group: value.group)
                value.name = parsed.name; value.quantity = parsed.quantity; value.unit = parsed.unit
            }
            return value
        }.sorted { $0.order < $1.order }
        let steps = (object.steps?.allObjects as? [RecipeStepMO] ?? []).map { RecipeStep(id: $0.id ?? UUID(), text: $0.text ?? "", order: $0.order?.intValue ?? 0) }.sorted { $0.order < $1.order }
        let reactions = (object.reactions?.allObjects as? [ReactionMO] ?? []).map { RecipeReaction(id: $0.id ?? UUID(), personID: $0.personID ?? "", emoji: $0.emoji ?? "", updatedAt: $0.updatedAt ?? .distantPast) }
        return Recipe(id: object.id ?? UUID(), title: object.title ?? "Untitled Recipe", imageData: object.imageData,
                      durationMinutes: object.durationMinutes?.intValue, servings: object.servings?.intValue, tags: decodeStrings(object.tagsJSON),
                      notes: object.notes ?? "", sourceURL: object.sourceURL.flatMap(URL.init(string:)), ingredients: ingredients, steps: steps,
                      reactions: ReactionIdentity.deduplicated(reactions, members: members),
                      collectionIDs: Set(decodeUUIDs(object.collectionIDsJSON)).intersection(Set(collections.map(\.id))), createdAt: object.createdAt ?? .distantPast)
    }
    private static func domainGroceryItem(_ object: GroceryItemMO) -> GroceryItem {
        var ingredient = Ingredient(name: object.name ?? "", quantity: object.quantity ?? "", unit: object.unit ?? "")
        if ingredient.quantity.isEmpty && ingredient.unit.isEmpty { ingredient = IngredientLineParser.parse(ingredient.name) }
        return GroceryItem(id: object.id ?? UUID(), name: ingredient.name, quantity: ingredient.quantity, unit: ingredient.unit,
                           isChecked: object.isChecked?.boolValue ?? false, sourceRecipeIDs: decodeUUIDs(object.sourceRecipeIDsJSON),
                           categoryOverride: object.categoryOverride.flatMap(GroceryAisle.init(rawValue:)), order: object.order?.intValue ?? 0)
    }
    static func encodeStrings(_ values: [String]) -> String { String(decoding: (try? JSONEncoder().encode(values)) ?? Data("[]".utf8), as: UTF8.self) }
    static func decodeStrings(_ value: String?) -> [String] { (try? JSONDecoder().decode([String].self, from: Data((value ?? "[]").utf8))) ?? [] }
    static func encodeUUIDs(_ values: [UUID]) -> String { encodeStrings(values.map(\.uuidString)) }
    static func decodeUUIDs(_ value: String?) -> [UUID] { decodeStrings(value).compactMap(UUID.init(uuidString:)) }
}

struct HouseholdSummary: Identifiable, Hashable {
    var id: UUID
    var name: String
    var incoming: Bool
}
