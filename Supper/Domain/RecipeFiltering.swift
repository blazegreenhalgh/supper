import Foundation

public struct RecipeFilter: Equatable, Sendable {
    public var query = ""
    public var maximumMinutes: Int?
    public var tags: Set<String> = []
    public var collectionIDs: Set<UUID> = []
    public var reaction: ReactionFilter = .any
    public enum ReactionFilter: String, CaseIterable, Sendable {
        case any = "Any reaction", mine = "I reacted", household = "Household favourites"
    }
    public init() {}
    public var isActive: Bool { !query.isEmpty || maximumMinutes != nil || !tags.isEmpty || !collectionIDs.isEmpty || reaction != .any }
    public func matches(_ recipe: Recipe, collections: [RecipeCollection], memberID: String, members: [HouseholdMember] = []) -> Bool {
        if let maximumMinutes, !(recipe.durationMinutes.map { $0 <= maximumMinutes } ?? false) { return false }
        if !tags.allSatisfy({ tag in recipe.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }) { return false }
        if !collectionIDs.isSubset(of: recipe.collectionIDs) { return false }
        if reaction == .mine && !recipe.reactions.contains(where: { ReactionIdentity.canonical($0.personID, members: members) == ReactionIdentity.canonical(memberID, members: members) }) { return false }
        if reaction == .household && !recipe.reactions.contains(where: { ["❤️", "😍", "👍"].contains($0.emoji) }) { return false }
        let names = collections.filter { recipe.collectionIDs.contains($0.id) }.map(\.name)
        let haystack = ([recipe.title, recipe.notes] + recipe.tags + recipe.ingredients.map(\.name) + names).joined(separator: " ")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { haystack.localizedCaseInsensitiveContains(String($0)) }
    }
    /// Deterministic fallback; model-assisted interpretation remains explicitly reviewable.
    public static func naturalLanguage(_ text: String) -> Self {
        var filter = Self()
        var query = text.lowercased()
        if let regex = try? NSRegularExpression(pattern: #"(?:under|within|less than|up to)\s+(\d+)\s*(?:minutes?|mins?)"#),
           let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
           let number = Range(match.range(at: 1), in: query), let full = Range(match.range, in: query) {
            let limit = Int(query[number])
            filter.maximumMinutes = query[full].hasPrefix("under") || query[full].hasPrefix("less than") ? limit.map { max(0, $0 - 1) } : limit
            query.removeSubrange(full)
        }
        if query.split(separator: " ").contains("easy") { filter.tags.insert("Easy") }
        let stop: Set<String> = ["easy", "recipe", "recipes", "something", "with", "a", "an", "please", "find", "me"]
        filter.query = query.split(whereSeparator: \.isWhitespace).filter { !stop.contains(String($0)) }.joined(separator: " ")
        return filter
    }
}

public enum RecipePicker {
    public static func pick(from recipes: [Recipe], excluding last: UUID?) -> Recipe? {
        let alternatives = recipes.filter { $0.id != last }
        return (alternatives.isEmpty ? recipes : alternatives).randomElement()
    }
}
