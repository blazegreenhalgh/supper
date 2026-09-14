import Foundation

public struct StepIngredientInput: Hashable, Sendable {
    public let ingredients: [Ingredient]
    public let steps: [RecipeStep]
    public init(ingredients: [Ingredient], steps: [RecipeStep]) {
        self.ingredients = ingredients; self.steps = steps
    }
}

public struct StepIngredientMatches: Sendable {
    public let input: StepIngredientInput
    public var ingredientIDs: [UUID: Set<UUID>]
    public var notice: String?

    public init(input: StepIngredientInput, ingredientIDs: [UUID: Set<UUID>], notice: String? = nil) {
        self.input = input; self.ingredientIDs = ingredientIDs; self.notice = notice
    }
    public func ingredients(for stepID: UUID, baseServings: Int?, selectedServings: Int?) -> [Ingredient] {
        input.ingredients.filter { ingredientIDs[stepID, default: []].contains($0.id) }
            .map { $0.scaled(from: baseServings, to: selectedServings) }
    }
}

public enum StepIngredientMatching {
    /// The model chooses only indexes. Names, quantities and ordering always come from the recipe.
    public static func validatedIDs(_ indexes: [Int], input: StepIngredientInput) -> Set<UUID> {
        Set(indexes.compactMap { input.ingredients.indices.contains($0) ? input.ingredients[$0].id : nil })
    }

    /// Offline fallback: explicit ingredient/group names only, without fuzzy word overlap.
    public static func explicitMatches(_ input: StepIngredientInput) -> StepIngredientMatches {
        var matches: [UUID: Set<UUID>] = [:]
        for step in input.steps {
            let text = normalized(step.text)
            for ingredient in input.ingredients {
                let name = ingredient.name.components(separatedBy: CharacterSet(charactersIn: ",(;")).first ?? ingredient.name
                let group = normalized(ingredient.group)
                let ingredientName = normalized(name)
                if (!ingredientName.isEmpty && contains(ingredientName, in: text)) ||
                    (!group.isEmpty && contains(group, in: text)) {
                    matches[step.id, default: []].insert(ingredient.id)
                }
            }
        }
        return StepIngredientMatches(input: input, ingredientIDs: matches)
    }
    private static func normalized(_ text: String) -> String {
        IngredientName.normalized(text).components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    private static func contains(_ phrase: String, in text: String) -> Bool {
        (" " + text + " ").contains(" " + phrase + " ")
    }
}
