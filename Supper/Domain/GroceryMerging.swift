import Foundation

public enum IngredientName {
    public static func normalized(_ name: String) -> String {
        let aliases = ["breasts":"breast", "thighs":"thigh", "eggs":"egg", "onions":"onion", "carrots":"carrot", "potatoes":"potato", "tomatoes":"tomato", "lemons":"lemon", "limes":"lime", "cloves":"clove", "apples":"apple", "bananas":"banana", "peppers":"pepper", "chillies":"chilli", "chilies":"chilli", "chili":"chilli", "yogurt":"yoghurt"]
        return name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .split(whereSeparator: \.isWhitespace).map { aliases[String($0)] ?? String($0) }.joined(separator: " ")
    }
}

public struct GroceryUnit: Sendable {
    public var dimension: String
    public var multiplier: Double
    public var mergeable: Bool
    public static func recognizes(_ text: String) -> Bool { unit(text).dimension != "unknown:" + text.lowercased() }
    public static func unit(_ text: String) -> Self {
        let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch key {
        case "g", "gram", "grams", "gramme", "grammes": return Self(dimension: "weight", multiplier: 1, mergeable: true)
        case "kg", "kilogram", "kilograms": return Self(dimension: "weight", multiplier: 1000, mergeable: true)
        case "ml", "millilitre", "millilitres", "milliliter", "milliliters": return Self(dimension: "volume", multiplier: 1, mergeable: true)
        case "l", "litre", "litres", "liter", "liters": return Self(dimension: "volume", multiplier: 1000, mergeable: true)
        case "", "each", "count", "piece", "pieces": return Self(dimension: "count", multiplier: 1, mergeable: true)
        case "clove", "cloves": return Self(dimension: "clove", multiplier: 1, mergeable: true)
        case "cup", "cups", "tbsp", "tbspn", "tbspns", "tbs", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons", "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "can", "cans", "tin", "tins", "bunch", "bunches":
            return Self(dimension: key, multiplier: 1, mergeable: false)
        default: return Self(dimension: "unknown:" + key, multiplier: 1, mergeable: false)
        }
    }
}

/// Persistent rows are contributions, never computed totals. Rendering totals can't overwrite a
/// concurrent recipe addition. Each row keeps its own checked/deleted state and idempotency key.
public enum GroceryMerging {
    public static func merge(_ contributions: [GroceryItem]) -> [GroceryItem] {
        var rows: [GroceryItem] = []
        var totals: [String: Double] = [:]
        var indices: [String: Int] = [:]
        for source in contributions.sorted(by: { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }) {
            let unit = GroceryUnit.unit(source.unit)
            guard unit.mergeable, let quantity = RecipeQuantity.parse(source.quantity), quantity.upper == nil else {
                rows.append(source); continue
            }
            // Manual overrides stay distinct from automatic suggestions.
            let key = [IngredientName.normalized(source.name), unit.dimension, source.category.rawValue,
                       source.categoryOverride == nil ? "auto" : "manual", String(source.isChecked)].joined(separator: "|")
            totals[key, default: 0] += quantity.lower * unit.multiplier
            let index: Int
            if let existing = indices[key] {
                index = existing
                rows[index].sourceRecipeIDs = Array(Set(rows[index].sourceRecipeIDs + source.sourceRecipeIDs)).sorted { $0.uuidString < $1.uuidString }
                rows[index].contributionIDs += source.contributionIDs
            } else {
                index = rows.count; indices[key] = index
                var item = source; item.name = IngredientName.normalized(source.name)
                rows.append(item)
            }
            let total = totals[key]!
            switch unit.dimension {
            case "weight": rows[index].unit = total >= 1000 ? "kg" : "g"; rows[index].quantity = RecipeQuantity.decimal(total >= 1000 ? total / 1000 : total)
            case "volume": rows[index].unit = total >= 1000 ? "l" : "ml"; rows[index].quantity = RecipeQuantity.decimal(total >= 1000 ? total / 1000 : total)
            case "count": rows[index].unit = ""; rows[index].quantity = RecipeQuantity.format(total)
            default: rows[index].unit = unit.dimension; rows[index].quantity = RecipeQuantity.format(total)
            }
        }
        return rows
    }
    public static func contributionKey(operationID: UUID, ingredientID: UUID) -> String {
        operationID.uuidString + ":" + ingredientID.uuidString
    }
}
