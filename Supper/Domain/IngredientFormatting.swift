import Foundation

public struct IngredientFormatChange: Identifiable, Sendable {
    public var id: UUID { original.id }
    public let original: Ingredient
    public var proposed: Ingredient
    public let notice: String?
}

/// AI may tidy punctuation and case. Source quantities and ingredient identity stay deterministic.
public enum IngredientFormatting {
    public static func proposal(for original: Ingredient) -> IngredientFormatChange {
        var proposed = original
        var notice: String?
        let name = original.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let measures = weights(in: name)
        if let first = measures.first, measures.count <= 2, isStandalone(measures, in: name) {
            let quantity = original.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = original.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let matching = measures.first {
                (quantity.isEmpty || RecipeQuantity.parse(quantity) == RecipeQuantity.parse($0.quantity)) &&
                (unit.isEmpty || weightUnit(unit) == $0.unit)
            }
            // An explicit existing amount wins. Never replace a count with a package's weight.
            let chosen = quantity.isEmpty && unit.isEmpty ? measures.first(where: { ["g", "kg"].contains($0.unit) }) ?? first : matching
            if let chosen {
                if quantity.isEmpty { proposed.quantity = chosen.quantity }
                if unit.isEmpty { proposed.unit = chosen.unit }
                let fullRange = NSRange(location: first.range.location, length: NSMaxRange(measures.last!.range) - first.range.location)
                if let range = Range(fullRange, in: name) {
                    proposed.name = name.replacingCharacters(in: range, with: "")
                    if measures.count > 1 { notice = "Uses the source’s \(proposed.amount) amount. The alternative weight is shown above for comparison." }
                }
            } else { notice = "The weight in the name differs from the amount fields. Kept both for you to check." }
        } else if measures.isEmpty && original.quantity.isEmpty && original.unit.isEmpty,
                  name.range(of: #"\b(?:fl\.?|fluid)\s*(?:oz|ounces?)\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
            let parsed = IngredientLineParser.parse(name, id: original.id)
            proposed.name = parsed.name; proposed.quantity = parsed.quantity; proposed.unit = parsed.unit
        }
        proposed.name = sentenceCase(tidyPunctuation(proposed.name))
        if proposed.name.isEmpty { proposed = original }
        return IngredientFormatChange(original: original, proposed: proposed, notice: notice)
    }

    /// Reject additions, omissions, reordering and changes to numbers from model output.
    /// The model cannot modify quantity, unit, group, category or IDs at all.
    public static func accepting(modelName: String, for change: IngredientFormatChange) -> IngredientFormatChange {
        let name = tidyPunctuation(modelName)
        guard !name.isEmpty, name.count <= change.proposed.name.count + 40,
              words(name) == words(change.proposed.name),
              numericFragments(name) == numericFragments(change.proposed.name),
              name.filter({ "/%×".contains($0) }) == change.proposed.name.filter({ "/%×".contains($0) }) else { return change }
        var result = change
        result.proposed.name = sentenceCase(name)
        return result
    }

    public static func applying(_ changes: [IngredientFormatChange], selected: Set<UUID>, to ingredients: [Ingredient]) -> [Ingredient] {
        ingredients.map { ingredient in
            guard selected.contains(ingredient.id), let change = changes.first(where: { $0.id == ingredient.id }),
                  ingredient == change.original else { return ingredient }
            // Only apply to the exact draft reviewed; late edits cannot be overwritten.
            return change.proposed
        }
    }

    private struct Weight {
        let range: NSRange
        let quantity: String
        let unit: String
    }
    private static func weights(in text: String) -> [Weight] {
        let number = #"(?:\d+\s+\d+[/⁄]\d+|\d+[/⁄]\d+|\d+(?:\.\d+)?\s*[½⅓⅔¼¾⅛⅜⅝⅞]?|[½⅓⅔¼¾⅛⅜⅝⅞])"#
        let pattern = #"(?<![\p{L}\d./–—-])("# + number + #"(?:\s*(?:[-–—]|to)\s*"# + number + #")?)\s*(kilograms?|kgs?|grams?|g|ounces?|oz|pounds?|lbs?)\b\.?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let q = Range(match.range(at: 1), in: text), let u = Range(match.range(at: 2), in: text),
                  RecipeQuantity.parse(String(text[q])) != nil, let unit = weightUnit(String(text[u])) else { return nil }
            return Weight(range: match.range, quantity: String(text[q]).trimmingCharacters(in: .whitespaces), unit: unit)
        }
    }
    private static func isStandalone(_ measures: [Weight], in text: String) -> Bool {
        guard let first = measures.first, let last = measures.last,
              let firstRange = Range(first.range, in: text), let lastRange = Range(last.range, in: text) else { return false }
        let before = String(text[..<firstRange.lowerBound])
        let after = String(text[lastRange.upperBound...])
        // Package multipliers/counts, 'each', and size descriptions must retain their meaning.
        let remaining = before + after
        let withoutReferences = remaining.replacingOccurrences(of: #"\bnotes?\s+\d+\b|\d+(?:\.\d+)?\s*%"#, with: "", options: [.regularExpression, .caseInsensitive])
        guard !withoutReferences.contains(where: \.isNumber),
              remaining.range(of: #"\b(each|per|pack|packet|package|size|sized)\b|[×]"#, options: [.regularExpression, .caseInsensitive]) == nil else { return false }
        if measures.count == 2 {
            let betweenRange = NSRange(location: NSMaxRange(first.range), length: last.range.location - NSMaxRange(first.range))
            guard let r = Range(betweenRange, in: text) else { return false }
            let between = text[r].trimmingCharacters(in: .whitespacesAndNewlines)
            guard ["/", "(", "or"].contains(between.lowercased()) else { return false }
        }
        // Extract a leading amount, or an explicit trailing amount in brackets/after a comma.
        let leading = before.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "•*-(["))).isEmpty
        let trailing = after.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ")]"))).isEmpty &&
            ["(", "[", ","].contains(before.trimmingCharacters(in: .whitespaces).last.map(String.init) ?? "")
        return leading || trailing
    }
    private static func weightUnit(_ text: String) -> String? {
        switch text.lowercased() {
        case "g", "gram", "grams": return "g"
        case "kg", "kgs", "kilogram", "kilograms": return "kg"
        case "oz", "ounce", "ounces": return "oz"
        case "lb", "lbs", "pound", "pounds": return "lb"
        default: return nil
        }
    }
    private static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    private static func numericFragments(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[\d½⅓⅔¼¾⅛⅜⅝⅞]+(?:[\s./⁄–—-]+[\d½⅓⅔¼¾⅛⅜⅝⅞]+)*"#) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
    private static func sentenceCase(_ text: String) -> String {
        let lower = text.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
    private static func tidyPunctuation(_ text: String) -> String {
        let input = Array(text.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")"))
        var output: [Character] = []; var opens: [(index: Int, kept: Bool)] = []
        for (index, character) in input.enumerated() {
            if character == "(" {
                let next = input.dropFirst(index + 1).first { !$0.isWhitespace }
                let keep = next != "," && next != "(" && next != ")"
                opens.append((output.count, keep)); if keep { output.append(character) }
            } else if character == ")" {
                if let open = opens.popLast(), open.kept { output.append(character) }
            } else { output.append(character) }
        }
        for open in opens.reversed() where open.kept { output.remove(at: open.index) }
        var result = String(output)
        for (pattern, replacement) in [(#"^[\s•*]+"#, ""), (#"\(\s*\)"#, ""), (#"\s+([,;:)])"#, "$1"),
                                        (#"([,;])\s*[,;]+"#, "$1"), (#"\(\s+"#, "("), (#"\s+"#, " ")] {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
    }
}
