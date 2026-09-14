import Foundation

public enum RecipeDiscoveryMode: String, CaseIterable, Sendable {
    case online = "Find online"
    case create = "Create with AI"
}

public struct RecipeSuggestion: Identifiable, Sendable {
    public var recipe: Recipe
    public let mode: RecipeDiscoveryMode
    public var id: UUID { recipe.id }
    public var sourceLabel: String {
        mode == .create ? "Created with AI" : (recipe.sourceURL?.host?.replacingOccurrences(of: "www.", with: "") ?? "Found online")
    }
    public init(recipe: Recipe, mode: RecipeDiscoveryMode) { self.recipe = recipe; self.mode = mode }
}

/// Value drafts only: reviewing and editing a suggestion never writes to a household.
public struct RecipeDiscoveryReview: Sendable {
    public private(set) var suggestions: [RecipeSuggestion]
    public private(set) var keptIDs: Set<UUID> = []
    public private(set) var discardedIDs: [UUID] = []
    public var pending: [RecipeSuggestion] {
        suggestions.filter { !keptIDs.contains($0.id) && !discardedIDs.contains($0.id) }
    }
    public init(suggestions: [RecipeSuggestion] = []) {
        var seen = Set<String>()
        self.suggestions = suggestions.filter { seen.insert(Self.key($0.recipe)).inserted }
    }
    public mutating func edit(_ recipe: Recipe) {
        guard pending.contains(where: { $0.id == recipe.id }), let index = suggestions.firstIndex(where: { $0.id == recipe.id }) else { return }
        suggestions[index].recipe = recipe
    }
    /// Call only after the store has successfully saved this exact recipe ID.
    public mutating func didKeep(_ id: UUID) {
        guard pending.contains(where: { $0.id == id }) else { return }
        keptIDs.insert(id)
    }
    public mutating func discard(_ id: UUID) {
        guard pending.contains(where: { $0.id == id }) else { return }
        discardedIDs.append(id)
    }
    public mutating func undoDiscard() { _ = discardedIDs.popLast() }
    public static func key(_ recipe: Recipe) -> String {
        if let url = recipe.sourceURL { return RecipeSearchFeed.canonical(url).absoluteString }
        return recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
    }
}

/// Parse actual search results; an LLM is never asked to invent source URLs.
public enum RecipeSearchFeed {
    public static func publisherLinks(in data: Data, host: String) throws -> [URL] {
        struct SearchResult: Decodable { var url: String; var subtype: String }
        let results = try JSONDecoder().decode([SearchResult].self, from: data)
        var seen = Set<String>()
        return results.compactMap { result in
            guard result.subtype == "post", let url = publicURL(result.url), url.host?.lowercased() == host.lowercased() else { return nil }
            let clean = canonical(url)
            return seen.insert(clean.absoluteString).inserted ? clean : nil
        }
    }
    public static func fallbackKeywords(_ prompt: String) -> String {
        let filler: Set<String> = ["i", "want", "would", "like", "a", "an", "the", "some", "something", "with", "and", "for", "me", "please", "recipe", "recipes", "meal", "dinner", "under", "minutes", "minute", "min", "mins", "in", "that", "is", "make", "find", "of", "bit", "cosy", "cozy", "quick", "easy"]
        return prompt.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { !filler.contains(String($0)) && !$0.allSatisfy(\.isNumber) }.prefix(3).joined(separator: " ")
    }
    public static func publicURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), host.contains("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), !host.hasSuffix(".internal"),
              !host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return url
    }
    public static func canonical(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.fragment = nil
        parts.queryItems = parts.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid"].contains($0.name.lowercased()) }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        return parts.url ?? url
    }
}
