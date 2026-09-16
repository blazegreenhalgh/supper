import Foundation

public struct RecipeDragItem: Codable, Sendable {
    public let recipeID: UUID
    public let householdID: UUID
    public let sourceCollectionID: UUID?
    public init(recipeID: UUID, householdID: UUID, sourceCollectionID: UUID?) {
        self.recipeID = recipeID; self.householdID = householdID; self.sourceCollectionID = sourceCollectionID
    }
    public func memberships(for recipe: Recipe, destination: UUID, householdID: UUID?, available: Set<UUID>) throws -> Set<UUID> {
        guard self.householdID == householdID, recipe.id == recipeID, available.contains(destination),
              sourceCollectionID.map({ available.contains($0) && recipe.collectionIDs.contains($0) }) ?? true else {
            throw SupperError.invalid("This recipe or collection has changed. Try dragging it again.")
        }
        var ids = recipe.collectionIDs
        if let sourceCollectionID { ids.remove(sourceCollectionID) }
        ids.insert(destination)
        return ids
    }
}

public struct Recipe: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var imageData: Data?
    public var durationMinutes: Int?
    public var servings: Int?
    public var tags: [String]
    public var notes: String
    public var sourceURL: URL?
    public var ingredients: [Ingredient]
    public var steps: [RecipeStep]
    public var reactions: [RecipeReaction]
    public var collectionIDs: Set<UUID>
    public var createdAt: Date
    public var isInExplore: Bool { collectionIDs.contains(RecipeCollection.exploreID) }

    public init(
        id: UUID = UUID(),
        title: String,
        imageData: Data? = nil,
        durationMinutes: Int? = nil,
        servings: Int? = nil,
        tags: [String] = [],
        notes: String = "",
        sourceURL: URL? = nil,
        ingredients: [Ingredient] = [],
        steps: [RecipeStep] = [],
        reactions: [RecipeReaction] = [],
        collectionIDs: Set<UUID> = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.imageData = imageData
        self.durationMinutes = durationMinutes
        self.servings = servings
        self.tags = tags
        self.notes = notes
        self.sourceURL = sourceURL
        self.ingredients = ingredients
        self.steps = steps
        self.reactions = reactions
        self.collectionIDs = collectionIDs
        self.createdAt = createdAt
    }
}

public struct Ingredient: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var quantity: String
    public var unit: String
    public var order: Int
    public var group: String
    public var categoryOverride: GroceryAisle?
    public var category: GroceryAisle { categoryOverride ?? IngredientPresentation.matching(name).aisle }
    public var amount: String { [quantity, unit].filter { !$0.isEmpty }.joined(separator: " ") }

    public init(id: UUID = UUID(), name: String, quantity: String = "", unit: String = "", order: Int = 0, group: String = "", categoryOverride: GroceryAisle? = nil) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.group = group
        self.categoryOverride = categoryOverride
        self.order = order
    }

    public var displayText: String {
        [quantity, unit, name].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
    }
}

public struct RecipeStep: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var order: Int
    public var group: String

    public init(id: UUID = UUID(), text: String, order: Int = 0, group: String = "") {
        self.id = id
        self.text = text
        self.order = order
        self.group = group
    }

    /// Human-readable Markdown keeps section names compatible with the existing
    /// CloudKit text field and older clients, without requiring a schema rollout.
    public var storedText: String {
        let heading = group.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return heading.isEmpty ? text : "## \(heading)\n\n\(text)"
    }

    public init(id: UUID = UUID(), storedText: String, order: Int = 0) {
        if storedText.hasPrefix("## "), let separator = storedText.range(of: "\n\n"),
           !storedText[..<separator.lowerBound].contains("\n") {
            self.init(id: id, text: String(storedText[separator.upperBound...]), order: order,
                      group: String(storedText[..<separator.lowerBound].dropFirst(3)))
        } else { self.init(id: id, text: storedText, order: order) }
    }
}

public struct RecipeReaction: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var personID: String
    public var emoji: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), personID: String, emoji: String, updatedAt: Date = .distantPast) {
        self.id = id
        self.personID = personID
        self.emoji = emoji
        self.updatedAt = updatedAt
    }
}

public struct GroceryItem: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var quantity: String
    public var unit: String
    public var isChecked: Bool
    public var sourceRecipeIDs: [UUID]
    public var contributionIDs: [UUID]
    public var categoryOverride: GroceryAisle?
    public var category: GroceryAisle { categoryOverride ?? IngredientPresentation.matching(name).aisle }
    public var order: Int

    public init(
        id: UUID = UUID(),
        name: String,
        quantity: String = "",
        unit: String = "",
        isChecked: Bool = false,
        sourceRecipeIDs: [UUID] = [],
        contributionIDs: [UUID] = [],
        categoryOverride: GroceryAisle? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.isChecked = isChecked
        self.sourceRecipeIDs = sourceRecipeIDs
        self.contributionIDs = contributionIDs.isEmpty ? [id] : contributionIDs
        self.categoryOverride = categoryOverride
        self.order = order
    }
}

public struct RecipeDraft: Hashable, Sendable {
    public var collectionIDs: Set<UUID> = []
    public var title: String
    public var imageData: Data?
    public var durationMinutes: Int?
    public var servings: Int?
    public var tags: [String]
    public var notes: String
    public var sourceURL: URL?
    public var ingredientSections: RecipeSectionedContent<Ingredient>
    public var methodSections: RecipeSectionedContent<RecipeStep>
    // Flat adapters keep imports, AI review and the existing CloudKit schema compatible.
    public var ingredients: [Ingredient] {
        get { ingredientSections.flattened }
        set { ingredientSections.replaceItems(newValue) }
    }
    public var steps: [RecipeStep] {
        get { methodSections.flattened }
        set { methodSections.replaceItems(newValue) }
    }

    public init(
        title: String = "",
        imageData: Data? = nil,
        durationMinutes: Int? = nil,
        servings: Int? = nil,
        tags: [String] = [],
        notes: String = "",
        sourceURL: URL? = nil,
        ingredients: [Ingredient] = [],
        steps: [RecipeStep] = []
    ) {
        self.title = title
        self.imageData = imageData
        self.durationMinutes = durationMinutes
        self.servings = servings
        self.tags = tags
        self.notes = notes
        self.sourceURL = sourceURL
        self.ingredientSections = RecipeSectionedContent(items: ingredients)
        self.methodSections = RecipeSectionedContent(items: steps)
    }

    public func makeRecipe() -> Recipe {
        Recipe(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            imageData: imageData,
            durationMinutes: durationMinutes,
            servings: servings,
            tags: tags,
            notes: notes,
            sourceURL: sourceURL,
            ingredients: ingredients,
            steps: steps,
            collectionIDs: collectionIDs
        )
    }
}


extension RecipeDraft {
    public init(recipe: Recipe) {
        self.init(title: recipe.title, imageData: recipe.imageData, durationMinutes: recipe.durationMinutes,
                  servings: recipe.servings, tags: recipe.tags, notes: recipe.notes, sourceURL: recipe.sourceURL,
                  ingredients: recipe.ingredients, steps: recipe.steps)
        collectionIDs = recipe.collectionIDs
    }

    /// Apply editable fields only. The caller supplies the latest recipe to retain reactions and identity.
    public func applying(to original: Recipe) -> Recipe {
        var edited = makeRecipe()
        edited.id = original.id
        edited.createdAt = original.createdAt
        edited.reactions = original.reactions
        return edited
    }
}

public struct RecipeCollection: Identifiable, Hashable, Sendable {
    /// A reserved homepage section, excluded from recipe memberships and filters.
    public static let allRecipesID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    /// Shared membership in the built-in saved-for-later collection.
    public static let exploreID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    public static var explore: RecipeCollection { RecipeCollection(id: exploreID, name: "Explore") }
    public var id: UUID
    public var name: String
    public var isOnHome: Bool
    public var order: Int
    public init(id: UUID = UUID(), name: String, isOnHome: Bool = false, order: Int = 0) {
        self.id = id; self.name = name; self.isOnHome = isOnHome; self.order = order
    }
}

public struct HouseholdMember: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var accountID: String?
    public init(id: String, name: String, accountID: String? = nil) {
        self.id = id; self.name = name; self.accountID = accountID
    }
}

public enum ReactionIdentity {
    public static func canonical(_ id: String, members: [HouseholdMember]) -> String {
        guard id != "me", !id.isEmpty, let member = members.first(where: { $0.id == id }),
              let account = member.accountID, !account.isEmpty else { return id }
        return members.filter { $0.accountID == account }.map(\.id).sorted().first ?? id
    }
    public static func deduplicated(_ reactions: [RecipeReaction], members: [HouseholdMember] = []) -> [RecipeReaction] {
        var seen = Set<String>()
        return reactions.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }.filter {
            // Unknown legacy authors cannot safely be attributed to the current member.
            let key = $0.personID == "me" || $0.personID.isEmpty ? "legacy:" + $0.id.uuidString : canonical($0.personID, members: members)
            return seen.insert(key).inserted && !$0.emoji.isEmpty
        }
    }
}

public struct IngredientSection: Identifiable, Sendable {
    public var title: String
    public var ingredients: [Ingredient]
    public var id: String { title }
    public static func sections(_ ingredients: [Ingredient], byShoppingCategory: Bool = false) -> [Self] {
        var result: [Self] = []
        for ingredient in ingredients {
            let title = byShoppingCategory ? ingredient.category.rawValue : (ingredient.group.isEmpty ? "Ingredients" : ingredient.group)
            if let index = result.firstIndex(where: { $0.title == title }) { result[index].ingredients.append(ingredient) }
            else { result.append(Self(title: title, ingredients: [ingredient])) }
        }
        return result
    }
}

public enum SupperError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}


/// Sections own their rows while editing. Only the persistence/import boundary needs
/// the legacy per-row heading. Section moves therefore always move all their content.
public protocol RecipeSectionItem: Identifiable, Hashable, Sendable where ID == UUID {
    var group: String { get set }
    var order: Int { get set }
}
extension Ingredient: RecipeSectionItem {}
extension RecipeStep: RecipeSectionItem {}

public struct RecipeContentSection<Item: RecipeSectionItem>: Identifiable, Hashable, Sendable {
    public var title: String
    public var items: [Item]
    public var id: String { title }
}

public struct RecipeSectionedContent<Item: RecipeSectionItem>: Hashable, Sendable {
    public var sections: [RecipeContentSection<Item>] = []

    public init(items: [Item] = []) { replaceItems(items) }

    public var flattened: [Item] {
        var rows: [Item] = []
        for section in sections {
            for var item in section.items {
                item.group = section.title
                item.order = rows.count
                rows.append(item)
            }
        }
        return rows
    }

    public mutating func replaceItems(_ items: [Item]) {
        let previous = sections
        var rebuilt: [RecipeContentSection<Item>] = []
        for var item in items {
            let title = item.group.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = rebuilt.firstIndex(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                item.group = rebuilt[index].title
                rebuilt[index].items.append(item)
            } else {
                item.group = title
                rebuilt.append(.init(title: title, items: [item]))
            }
        }
        // Formatting and source recovery must not remove newly created empty sections.
        for (index, section) in previous.enumerated() where !rebuilt.contains(where: { $0.title == section.title }) {
            rebuilt.insert(.init(title: section.title, items: []), at: min(index, rebuilt.count))
        }
        sections = rebuilt.isEmpty ? [.init(title: "", items: [])] : rebuilt
    }

    @discardableResult public mutating func addSection(_ name: String) -> String {
        let title = name.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if let existing = sections.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) { return existing.title }
        sections.append(.init(title: title, items: []))
        return title
    }

    public mutating func save(_ item: Item, in title: String) {
        let destination = addSection(title)
        if let section = sections.firstIndex(where: { $0.title == destination }),
           let index = sections[section].items.firstIndex(where: { $0.id == item.id }) {
            var value = item; value.group = destination
            sections[section].items[index] = value
        } else {
            for index in sections.indices { sections[index].items.removeAll { $0.id == item.id } }
            var value = item; value.group = destination
            sections[sections.firstIndex(where: { $0.title == destination })!].items.append(value)
        }
    }

    @discardableResult public mutating func moveItem(_ id: UUID, to title: String, before nextID: UUID? = nil) -> Bool {
        guard id != nextID, sections.contains(where: { $0.title == title }),
              let item = flattened.first(where: { $0.id == id }),
              nextID == nil || sections.first(where: { $0.title == title })!.items.contains(where: { $0.id == nextID }) else { return false }
        for index in sections.indices { sections[index].items.removeAll { $0.id == id } }
        let index = sections.firstIndex(where: { $0.title == title })!
        var value = item; value.group = title
        let insertion = nextID.flatMap { next in sections[index].items.firstIndex(where: { $0.id == next }) } ?? sections[index].items.count
        sections[index].items.insert(value, at: insertion)
        return true
    }

    @discardableResult public mutating func moveSection(_ title: String, before nextTitle: String?) -> Bool {
        guard title != nextTitle, let index = sections.firstIndex(where: { $0.title == title }),
              nextTitle == nil || sections.contains(where: { $0.title == nextTitle }) else { return false }
        let section = sections.remove(at: index)
        let insertion = nextTitle.flatMap { title in sections.firstIndex(where: { $0.title == title }) } ?? sections.count
        sections.insert(section, at: insertion)
        return true
    }

    @discardableResult public mutating func renameSection(_ title: String, to name: String) -> Bool {
        let name = name.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let index = sections.firstIndex(where: { $0.title == title }),
              !sections.contains(where: { $0.title != title && $0.title.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        sections[index].title = name
        for row in sections[index].items.indices { sections[index].items[row].group = name }
        return true
    }
}

/// Tags are individual names. Punctuation, including commas, stays part of a name.
public enum RecipeTagNames {
    public static func clean(_ name: String) -> String {
        name.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
    public static func normalized(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map(clean).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
