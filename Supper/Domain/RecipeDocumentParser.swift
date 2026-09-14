import Foundation

public struct RecipeDocumentParser {
    public init() {}
    public func parse(html: String, sourceURL: URL) throws -> RecipeDraft {
        guard let recipe = extractRecipeObject(from: html) else { throw SupperError.invalid("No recipe metadata found. Try pasting the recipe text or choose manual entry.") }
        var ingredients = ingredientObjects(recipe["recipeIngredient"])
        let pageIngredients = explicitPageIngredients(html)
        if ingredients.isEmpty { ingredients = pageIngredients }
        else { ingredients = GroupRecovery.applyUnambiguous(to: ingredients, recovered: pageIngredients) }
        let duration = ["totalTime", "cookTime", "prepTime"].compactMap { string(recipe[$0]).flatMap(parseISODuration) }.first
        return RecipeDraft(title: cleanText(string(recipe["name"]) ?? ""), durationMinutes: duration,
                           servings: string(recipe["recipeYield"]).flatMap(firstInteger), tags: parseTags(recipe),
                           sourceURL: sourceURL, ingredients: ingredients,
                           steps: instructionSteps(recipe["recipeInstructions"]))
    }

    public func imageURL(html: String) -> URL? { extractRecipeObject(from: html).flatMap { extractImageURL($0["image"]) } }

    func ingredientObjects(_ value: Any?, group: String = "") -> [Ingredient] {
        var result: [Ingredient] = []
        func visit(_ value: Any, group: String) {
            if let line = value as? String {
                result.append(IngredientLineParser.parse(cleanText(line), order: result.count, group: group))
            } else if let array = value as? [Any] {
                for item in array { visit(item, group: group) }
            } else if let object = value as? [String: Any] {
                if let children = object["itemListElement"] ?? object["recipeIngredient"] ?? object["ingredients"] {
                    visit(children, group: cleanText(string(object["name"]) ?? group))
                } else if let name = string(object["name"]) ?? string(object["text"]) {
                    var item = IngredientLineParser.parse(cleanText(name), order: result.count, group: group)
                    if let quantity = string(object["quantity"]) ?? (object["quantity"] as? NSNumber)?.stringValue { item.quantity = quantity }
                    if let unit = string(object["unitText"]) ?? string(object["unit"]) { item.unit = unit }
                    result.append(item)
                }
            }
        }
        if let value { visit(value, group: group) }
        return result
    }

    /// Reads explicit headings and ingredient list items. Script/style text is never interpreted.
    public func explicitPageIngredients(_ html: String) -> [Ingredient] {
        let safe = html.replacingOccurrences(of: #"<(script|style)\b[^>]*>[\s\S]*?</\1>"#, with: "", options: [.regularExpression, .caseInsensitive])
        let pattern = #"<(h[1-6])\b[^>]*>([\s\S]*?)</\1>|<(?:div|span)[^>]*class=["'][^"']*(?:wprm-recipe-group-name|ingredient-group-name)[^"']*["'][^>]*>([\s\S]*?)</(?:div|span)>|<li\b([^>]*)>([\s\S]*?)</li>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        var active = false; var group = ""; var result: [Ingredient] = []
        for match in regex.matches(in: safe, range: NSRange(safe.startIndex..., in: safe)) {
            func value(_ i: Int) -> String { Range(match.range(at: i), in: safe).map { String(safe[$0]) } ?? "" }
            let heading = cleanText(value(2).isEmpty ? value(3) : value(2))
            if !heading.isEmpty {
                let lower = heading.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                if lower == "ingredients" { active = true; group = "" }
                else if ["instructions", "method", "directions", "notes", "nutrition"].contains(lower) { active = false; group = "" }
                else if active || !value(3).isEmpty { group = heading.trimmingCharacters(in: CharacterSet(charactersIn: ":")); active = true }
            } else {
                let attributes = value(4).lowercased()
                guard active || attributes.contains("recipe-ingredient") || attributes.contains("recipeingredient") else { continue }
                if attributes.contains("instruction") { active = false; continue }
                let line = cleanText(value(5))
                if !line.isEmpty { result.append(IngredientLineParser.parse(line, order: result.count, group: group)) }
            }
        }
        return result
    }

    func extractRecipeObject(from html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        for match in regex.matches(in: html, range: range) {
            guard let contentRange = Range(match.range(at: 1), in: html) else { continue }
            let raw = String(html[contentRange])
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#34;", with: "\"")
            guard let data = raw.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let found = findRecipe(in: json) { return found }
        }
        return nil
    }

    func findRecipe(in value: Any) -> [String: Any]? {
        if let object = value as? [String: Any] {
            if isRecipeType(object["@type"]) { return object }
            if let graph = object["@graph"], let found = findRecipe(in: graph) { return found }
            for child in object.values {
                if let found = findRecipe(in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findRecipe(in: child) { return found }
            }
        }
        return nil
    }

    func isRecipeType(_ value: Any?) -> Bool {
        if let value = value as? String { return value.caseInsensitiveCompare("Recipe") == .orderedSame }
        if let values = value as? [String] { return values.contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame } }
        return false
    }

    func instructionStrings(_ value: Any?) -> [String] {
        instructionSteps(value).map(\.text)
    }

    /// Preserve HowToSection headings so variants and components from an online
    /// source are not flattened into one ambiguous method for the assistant.
    func instructionSteps(_ value: Any?) -> [RecipeStep] {
        var result: [RecipeStep] = []
        func visit(_ value: Any, group: String) {
            if let text = value as? String {
                let cleaned = cleanText(text)
                if !cleaned.isEmpty { result.append(RecipeStep(text: cleaned, order: result.count, group: group)) }
            } else if let array = value as? [Any] {
                for item in array { visit(item, group: group) }
            } else if let object = value as? [String: Any] {
                if let list = object["itemListElement"] {
                    visit(list, group: cleanText(string(object["name"]) ?? group))
                } else if let text = string(object["text"]) { visit(text, group: group) }
            }
        }
        if let value { visit(value, group: "") }
        return result
    }

    func parseTags(_ recipe: [String: Any]) -> [String] {
        let raw = [recipe["keywords"], recipe["recipeCategory"], recipe["recipeCuisine"]]
            .flatMap(strings)
            .flatMap { $0.split(separator: ",").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return raw.filter { seen.insert($0.lowercased()).inserted }.prefix(8).map { $0 }
    }

    func strings(_ value: Any?) -> [String] {
        if let value = value as? String { return [value] }
        if let values = value as? [String] { return values }
        return []
    }

    func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        if let values = value as? [String] { return values.first }
        return nil
    }

    func extractImageURL(_ value: Any?) -> URL? {
        if let string = value as? String { return URL(string: string) }
        if let strings = value as? [String], let first = strings.first { return URL(string: first) }
        if let object = value as? [String: Any], let url = string(object["url"]) { return URL(string: url) }
        if let array = value as? [Any] {
            for item in array { if let url = extractImageURL(item) { return url } }
        }
        return nil
    }

    func parseISODuration(_ value: String) -> Int? {
        let pattern = #"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)) else { return nil }
        func number(_ index: Int) -> Int {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: value) else { return 0 }
            return Int(value[range]) ?? 0
        }
        return number(1) * 24 * 60 + number(2) * 60 + number(3)
    }

    func firstInteger(_ value: String) -> Int? {
        value.split { !$0.isNumber }.compactMap { Int($0) }.first
    }

    func cleanText(_ value: String) -> String {
        var text = value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, decoded) in ["&amp;":"&", "&quot;":"\"", "&#39;":"'", "&apos;":"'", "&nbsp;":" ", "&frac12;":"½", "&frac14;":"¼", "&frac34;":"¾", "&lt;":"<", "&gt;":">"] { text = text.replacingOccurrences(of: entity, with: decoded) }
        if let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let full = Range(match.range, in: text), let number = Range(match.range(at: 1), in: text) else { continue }
                let raw = String(text[number]); let n = raw.hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
                if let n, let scalar = UnicodeScalar(n) { text.replaceSubrange(full, with: String(scalar)) }
            }
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

public enum GroupRecovery {
    /// Match only uniquely identifiable ingredient names. Never copy quantity, unit, order, or ID.
    public static func suggestions(for original: [Ingredient], recovered: [Ingredient]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for ingredient in original {
            let name = IngredientName.normalized(ingredient.name)
            let matches = recovered.filter { IngredientName.normalized($0.name) == name && !$0.group.isEmpty }
            if matches.count == 1 { result[ingredient.id] = matches[0].group }
        }
        return result
    }
    public static func applyUnambiguous(to original: [Ingredient], recovered: [Ingredient]) -> [Ingredient] {
        let groups = suggestions(for: original, recovered: recovered)
        return original.map { ingredient in
            var item = ingredient
            if item.group.isEmpty, let group = groups[item.id] { item.group = group }
            return item
        }
    }
}
