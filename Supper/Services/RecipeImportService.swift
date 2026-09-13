import Foundation

struct RecipeImportService {
    enum ImportError: LocalizedError {
        case invalidResponse
        case recipeMetadataNotFound

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "That page could not be loaded."
            case .recipeMetadataNotFound: "Supper couldn't find structured recipe data on that page yet."
            }
        }
    }

    func importRecipe(from url: URL) async throws -> RecipeDraft {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 Supper/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidResponse
        }

        guard let recipe = extractRecipeObject(from: html) else {
            throw ImportError.recipeMetadataNotFound
        }

        let title = string(recipe["name"]) ?? url.deletingPathExtension().lastPathComponent
        let duration = ["totalTime", "cookTime", "prepTime"]
            .compactMap { string(recipe[$0]).flatMap(parseISODuration) }
            .first
        let servings = string(recipe["recipeYield"]).flatMap(firstInteger)
        let ingredients = strings(recipe["recipeIngredient"]).enumerated().map { index, raw in
            Ingredient(name: raw, order: index)
        }
        let steps = instructionStrings(recipe["recipeInstructions"]).enumerated().map { index, text in
            RecipeStep(text: text, order: index)
        }
        let tags = parseTags(recipe)
        let imageURL = extractImageURL(recipe["image"])
        let imageData: Data?
        if let imageURL {
            imageData = try? await fetchImageData(imageURL)
        } else {
            imageData = nil
        }

        return RecipeDraft(
            title: title,
            imageData: imageData,
            durationMinutes: duration,
            servings: servings,
            tags: tags,
            sourceURL: url,
            ingredients: ingredients,
            steps: steps
        )
    }

    private func extractRecipeObject(from html: String) -> [String: Any]? {
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

    private func findRecipe(in value: Any) -> [String: Any]? {
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

    private func isRecipeType(_ value: Any?) -> Bool {
        if let value = value as? String { return value.caseInsensitiveCompare("Recipe") == .orderedSame }
        if let values = value as? [String] { return values.contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame } }
        return false
    }

    private func instructionStrings(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings.map(cleanText).filter { !$0.isEmpty } }
        if let string = value as? String { return [cleanText(string)].filter { !$0.isEmpty } }
        if let array = value as? [Any] {
            return array.flatMap { item -> [String] in
                if let string = item as? String { return [cleanText(string)] }
                if let object = item as? [String: Any] {
                    if let text = string(object["text"]) { return [cleanText(text)] }
                    if let list = object["itemListElement"] { return instructionStrings(list) }
                }
                return []
            }.filter { !$0.isEmpty }
        }
        return []
    }

    private func parseTags(_ recipe: [String: Any]) -> [String] {
        let raw = [recipe["keywords"], recipe["recipeCategory"], recipe["recipeCuisine"]]
            .flatMap(strings)
            .flatMap { $0.split(separator: ",").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return raw.filter { seen.insert($0.lowercased()).inserted }.prefix(8).map { $0 }
    }

    private func strings(_ value: Any?) -> [String] {
        if let value = value as? String { return [value] }
        if let values = value as? [String] { return values }
        return []
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let values = value as? [String] { return values.first }
        return nil
    }

    private func extractImageURL(_ value: Any?) -> URL? {
        if let string = value as? String { return URL(string: string) }
        if let strings = value as? [String], let first = strings.first { return URL(string: first) }
        if let object = value as? [String: Any], let url = string(object["url"]) { return URL(string: url) }
        if let array = value as? [Any] {
            for item in array { if let url = extractImageURL(item) { return url } }
        }
        return nil
    }

    private func fetchImageData(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw ImportError.invalidResponse }
        return data
    }

    private func parseISODuration(_ value: String) -> Int? {
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

    private func firstInteger(_ value: String) -> Int? {
        value.split { !$0.isNumber }.compactMap { Int($0) }.first
    }

    private func cleanText(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
