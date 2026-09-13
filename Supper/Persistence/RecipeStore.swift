import Foundation
import CoreData
import Combine

@MainActor
final class RecipeStore: ObservableObject {
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var groceryItems: [GroceryItem] = []
    @Published private(set) var isReady = false
    @Published var errorMessage: String?

    let persistence: PersistenceStack
    private var library: SupperLibraryMO?
    private var remoteChangeObserver: NSObjectProtocol?

    init(persistence: PersistenceStack = PersistenceStack()) {
        self.persistence = persistence
    }

    deinit {
        if let remoteChangeObserver { NotificationCenter.default.removeObserver(remoteChangeObserver) }
    }

    func load() async {
        guard !isReady else { return }
        do {
            try await persistence.load()
            try ensureLibrary()
            try refresh()
            observeRemoteChanges()
            isReady = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addRecipe(_ recipe: Recipe) throws {
        guard let library else { return }
        let context = persistence.container.viewContext
        let object = RecipeMO(context: context)
        apply(recipe, to: object)
        object.library = library
        try context.save()
        try refresh()
    }

    func updateRecipe(_ recipe: Recipe) throws {
        let context = persistence.container.viewContext
        guard let object = try fetchRecipeObject(recipe.id, context: context) else { return }
        apply(recipe, to: object)
        try context.save()
        try refresh()
    }

    func deleteRecipe(_ recipe: Recipe) throws {
        let context = persistence.container.viewContext
        guard let object = try fetchRecipeObject(recipe.id, context: context) else { return }
        context.delete(object)
        try context.save()
        try refresh()
    }

    func addIngredientsToGroceryList(from recipe: Recipe, ingredients: [Ingredient]) throws {
        guard let library else { return }
        let context = persistence.container.viewContext
        var nextOrder = (groceryItems.map(\.order).max() ?? -1) + 1

        for ingredient in ingredients {
            let item = GroceryItemMO(context: context)
            item.id = UUID()
            item.name = ingredient.name
            item.quantity = ingredient.quantity
            item.unit = ingredient.unit
            item.isChecked = false
            item.sourceRecipeIDsJSON = Self.encodeUUIDs([recipe.id])
            item.order = NSNumber(value: nextOrder)
            item.library = library
            nextOrder += 1
        }

        try context.save()
        try refresh()
    }

    func addGroceryItem(name: String) throws {
        guard let library else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let context = persistence.container.viewContext
        let item = GroceryItemMO(context: context)
        item.id = UUID()
        item.name = trimmed
        item.quantity = ""
        item.unit = ""
        item.isChecked = false
        item.sourceRecipeIDsJSON = "[]"
        item.order = NSNumber(value: (groceryItems.map(\.order).max() ?? -1) + 1)
        item.library = library
        try context.save()
        try refresh()
    }

    func toggleGroceryItem(_ item: GroceryItem) throws {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<GroceryItemMO>(entityName: "GroceryItem")
        request.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
        request.fetchLimit = 1
        guard let object = try context.fetch(request).first else { return }
        object.isChecked = NSNumber(value: !item.isChecked)
        try context.save()
        try refresh()
    }

    func deleteGroceryItems(at offsets: IndexSet) throws {
        let context = persistence.container.viewContext
        let ids = offsets.compactMap { groceryItems.indices.contains($0) ? groceryItems[$0].id : nil }
        guard !ids.isEmpty else { return }
        let request = NSFetchRequest<GroceryItemMO>(entityName: "GroceryItem")
        request.predicate = NSPredicate(format: "id IN %@", ids)
        for object in try context.fetch(request) { context.delete(object) }
        try context.save()
        try refresh()
    }

    func setReaction(_ emoji: String?, for recipe: Recipe, personID: String) throws {
        let context = persistence.container.viewContext
        guard let object = try fetchRecipeObject(recipe.id, context: context) else { return }
        let reactions = object.reactions?.allObjects.compactMap { $0 as? ReactionMO } ?? []
        let existing = reactions.first { $0.personID == personID }

        if let emoji, !emoji.isEmpty {
            let reaction = existing ?? ReactionMO(context: context)
            reaction.id = reaction.id ?? UUID()
            reaction.personID = personID
            reaction.emoji = emoji
            reaction.recipe = object
        } else if let existing {
            context.delete(existing)
        }

        try context.save()
        try refresh()
    }

    private func ensureLibrary() throws {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<SupperLibraryMO>(entityName: "SupperLibrary")
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            library = existing
            return
        }

        let root = SupperLibraryMO(context: context)
        root.id = UUID()
        root.name = "Our Supper"
        root.createdAt = Date()
        library = root
        try context.save()
    }

    private func refresh() throws {
        let context = persistence.container.viewContext

        let recipeRequest = NSFetchRequest<RecipeMO>(entityName: "Recipe")
        recipeRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        recipes = try context.fetch(recipeRequest).map(Self.domainRecipe)

        let groceryRequest = NSFetchRequest<GroceryItemMO>(entityName: "GroceryItem")
        groceryRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        groceryItems = try context.fetch(groceryRequest).map(Self.domainGroceryItem)
    }

    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? self?.refresh()
            }
        }
    }

    private func fetchRecipeObject(_ id: UUID, context: NSManagedObjectContext) throws -> RecipeMO? {
        let request = NSFetchRequest<RecipeMO>(entityName: "Recipe")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ recipe: Recipe, to object: RecipeMO) {
        let context = object.managedObjectContext!
        object.id = recipe.id
        object.title = recipe.title
        object.imageData = recipe.imageData
        object.durationMinutes = recipe.durationMinutes.map(NSNumber.init(value:))
        object.servings = recipe.servings.map(NSNumber.init(value:))
        object.tagsJSON = Self.encodeStrings(recipe.tags)
        object.notes = recipe.notes
        object.sourceURL = recipe.sourceURL?.absoluteString
        object.createdAt = recipe.createdAt

        for child in object.ingredients?.allObjects.compactMap({ $0 as? NSManagedObject }) ?? [] { context.delete(child) }
        for ingredient in recipe.ingredients {
            let child = IngredientMO(context: context)
            child.id = ingredient.id
            child.name = ingredient.name
            child.quantity = ingredient.quantity
            child.unit = ingredient.unit
            child.order = NSNumber(value: ingredient.order)
            child.recipe = object
        }

        for child in object.steps?.allObjects.compactMap({ $0 as? NSManagedObject }) ?? [] { context.delete(child) }
        for step in recipe.steps {
            let child = RecipeStepMO(context: context)
            child.id = step.id
            child.text = step.text
            child.order = NSNumber(value: step.order)
            child.recipe = object
        }
    }

    private static func domainRecipe(_ object: RecipeMO) -> Recipe {
        let ingredients = (object.ingredients?.allObjects.compactMap { $0 as? IngredientMO } ?? [])
            .map { Ingredient(id: $0.id ?? UUID(), name: $0.name ?? "", quantity: $0.quantity ?? "", unit: $0.unit ?? "", order: $0.order?.intValue ?? 0) }
            .sorted { $0.order < $1.order }

        let steps = (object.steps?.allObjects.compactMap { $0 as? RecipeStepMO } ?? [])
            .map { RecipeStep(id: $0.id ?? UUID(), text: $0.text ?? "", order: $0.order?.intValue ?? 0) }
            .sorted { $0.order < $1.order }

        let reactions = (object.reactions?.allObjects.compactMap { $0 as? ReactionMO } ?? [])
            .map { RecipeReaction(id: $0.id ?? UUID(), personID: $0.personID ?? "", emoji: $0.emoji ?? "") }

        return Recipe(
            id: object.id ?? UUID(),
            title: object.title ?? "Untitled Recipe",
            imageData: object.imageData,
            durationMinutes: object.durationMinutes?.intValue,
            servings: object.servings?.intValue,
            tags: decodeStrings(object.tagsJSON),
            notes: object.notes ?? "",
            sourceURL: object.sourceURL.flatMap(URL.init(string:)),
            ingredients: ingredients,
            steps: steps,
            reactions: reactions,
            createdAt: object.createdAt ?? Date()
        )
    }

    private static func domainGroceryItem(_ object: GroceryItemMO) -> GroceryItem {
        GroceryItem(
            id: object.id ?? UUID(),
            name: object.name ?? "",
            quantity: object.quantity ?? "",
            unit: object.unit ?? "",
            isChecked: object.isChecked?.boolValue ?? false,
            sourceRecipeIDs: decodeUUIDs(object.sourceRecipeIDsJSON),
            order: object.order?.intValue ?? 0
        )
    }

    private static func encodeStrings(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeStrings(_ value: String?) -> [String] {
        guard let value, let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func encodeUUIDs(_ values: [UUID]) -> String {
        encodeStrings(values.map(\.uuidString))
    }

    private static func decodeUUIDs(_ value: String?) -> [UUID] {
        decodeStrings(value).compactMap(UUID.init(uuidString:))
    }
}
