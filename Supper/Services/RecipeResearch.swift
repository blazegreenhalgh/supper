import Foundation

struct RecipeResearch {
    func find(_ request: String, client: OpenAIClient, explicitSourceText: String? = nil,
              progress: @escaping @MainActor @Sendable (String) -> Void) async throws -> [RecipeDraft] {
        await progress("Finding published recipes online…")
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let sourceText = explicitSourceText ?? request
        let explicit = (detector?.matches(in: sourceText, range: NSRange(sourceText.startIndex..., in: sourceText)) ?? [])
            .compactMap(\.url).compactMap { RecipeSearchFeed.publicURL($0.absoluteString) }
        let links = explicit.isEmpty ? try await client.searchRecipes(request) : explicit
        var seen = Set<URL>()
        let candidates = Array(links.map(RecipeSearchFeed.canonical).filter { seen.insert($0).inserted }.prefix(8))
        var drafts: [RecipeDraft] = []
        await progress("Reading source ingredients and methods…")
        for start in stride(from: 0, to: candidates.count, by: 3) {
            try Task.checkCancellation()
            let batch = Array(candidates[start..<min(start + 3, candidates.count)])
            let values = await withTaskGroup(of: (Int, RecipeDraft?).self, returning: [RecipeDraft].self) { group in
                for (index, url) in batch.enumerated() {
                    group.addTask {
                        if let cached = await RecipeResearchCache.shared.read(url) { return (index, cached) }
                        guard let value = try? await RecipeImportService().importRecipe(from: url, includeImage: false),
                              !value.title.isEmpty, !value.ingredients.isEmpty, !value.steps.isEmpty,
                              RecipeAIContext.text(value).count <= 24_000 else { return (index, nil) }
                        await RecipeResearchCache.shared.save(value, url: url)
                        return (index, value)
                    }
                }
                var values: [(Int, RecipeDraft)] = []
                for await (index, value) in group { if let value { values.append((index, value)) } }
                return values.sorted { $0.0 < $1.0 }.map(\.1)
            }
            drafts.append(contentsOf: values)
        }
        try Task.checkCancellation()
        guard !drafts.isEmpty else {
            throw SupperError.invalid("I couldn’t read a complete published recipe for this request. Try another recipe URL or a more specific dish. I won’t fill missing ingredients or methods from memory.")
        }
        return drafts
    }
}

/// Short-lived public-page cache only; no prompts, keys, private drafts or photos.
private actor RecipeResearchCache {
    static let shared = RecipeResearchCache()
    private var values: [URL: (Date, RecipeDraft)] = [:]
    func read(_ url: URL) -> RecipeDraft? {
        guard let value = values[url], Date().timeIntervalSince(value.0) < 600 else { values[url] = nil; return nil }
        return value.1
    }
    func save(_ draft: RecipeDraft, url: URL) {
        if values.count >= 16, let oldest = values.min(by: { $0.value.0 < $1.value.0 })?.key { values[oldest] = nil }
        values[url] = (Date(), draft)
    }
}
