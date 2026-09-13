import Foundation

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
    public var createdAt: Date

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
        self.createdAt = createdAt
    }
}

public struct Ingredient: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var quantity: String
    public var unit: String
    public var order: Int

    public init(id: UUID = UUID(), name: String, quantity: String = "", unit: String = "", order: Int = 0) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
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

    public init(id: UUID = UUID(), text: String, order: Int = 0) {
        self.id = id
        self.text = text
        self.order = order
    }
}

public struct RecipeReaction: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var personID: String
    public var emoji: String

    public init(id: UUID = UUID(), personID: String, emoji: String) {
        self.id = id
        self.personID = personID
        self.emoji = emoji
    }
}

public struct GroceryItem: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var quantity: String
    public var unit: String
    public var isChecked: Bool
    public var sourceRecipeIDs: [UUID]
    public var order: Int

    public init(
        id: UUID = UUID(),
        name: String,
        quantity: String = "",
        unit: String = "",
        isChecked: Bool = false,
        sourceRecipeIDs: [UUID] = [],
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.isChecked = isChecked
        self.sourceRecipeIDs = sourceRecipeIDs
        self.order = order
    }
}

public struct RecipeDraft: Sendable {
    public var title: String
    public var imageData: Data?
    public var durationMinutes: Int?
    public var servings: Int?
    public var tags: [String]
    public var notes: String
    public var sourceURL: URL?
    public var ingredients: [Ingredient]
    public var steps: [RecipeStep]

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
        self.ingredients = ingredients
        self.steps = steps
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
            steps: steps
        )
    }
}
