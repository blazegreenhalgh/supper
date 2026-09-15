import Foundation

/// New recipe content must match a downloaded source or the user's literal input.
public enum RecipeAIEvidence {
    public static func validate(_ patch: RecipeAssistantPatch, draft: RecipeDraft, source: RecipeDraft, request: String) throws {
        func same(_ a: String, _ b: String) -> Bool { normalized(a) == normalized(b) }
        func userSupplied(_ value: String) -> Bool { !value.isEmpty && normalized(request).contains(normalized(value)) }
        func suppliedAmount(_ value: String) -> Bool {
            guard !value.isEmpty else { return false }
            let escaped = NSRegularExpression.escapedPattern(for: normalized(value))
            return normalized(request).range(of: "(?<![\\p{L}\\p{N}./])" + escaped + "(?![\\p{N}./])", options: .regularExpression) != nil
        }
        func matches(_ edit: AssistantIngredientEdit, _ item: Ingredient) -> Bool {
            same(edit.name, item.name) && same(edit.quantity, item.quantity) && same(edit.unit, item.unit)
        }
        for edit in patch.ingredients where edit.operation != .remove {
            let original = draft.ingredients.indices.contains(edit.index) ? draft.ingredients[edit.index] : nil
            let line = [edit.quantity, edit.unit, edit.name].filter { !$0.isEmpty }.joined(separator: " ")
            let explicitEdit = original.map { same(edit.name, $0.name) && same(edit.unit, $0.unit) && suppliedAmount(edit.quantity) } ?? false
            guard source.ingredients.contains(where: { matches(edit, $0) }) || original.map({ matches(edit, $0) }) == true || userSupplied(line) || explicitEdit else { throw unsupported }
        }
        for edit in patch.steps where edit.operation != .remove {
            let original = draft.steps.indices.contains(edit.index) ? draft.steps[edit.index] : nil
            // Complete steps retain source warnings, temperatures and durations.
            guard source.steps.contains(where: { same(edit.text, $0.text) }) || original.map({ same(edit.text, $0.text) }) == true || userSupplied(edit.text) else { throw unsupported }
        }
        if let minutes = patch.durationMinutes, minutes != draft.durationMinutes, minutes != source.durationMinutes, !suppliedAmount(String(minutes)) { throw unsupported }
        if let servings = patch.servings, servings != draft.servings, servings != source.servings, !suppliedAmount(String(servings)) { throw unsupported }
        _ = try patch.applying(to: draft)
    }
    private static func normalized(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() }
    private static var unsupported: SupperError {
        .invalid("Some suggested details weren’t present in the published recipe or your request, so I haven’t applied them. Try adding just the sourced ingredients or method, or state your changes explicitly.")
    }
}

public enum RecipeAIContext {
    public static func text(_ draft: RecipeDraft) -> String {
        let ingredients = draft.ingredients.enumerated().map { "[\($0.offset)] \($0.element.quantity) | \($0.element.unit) | \($0.element.name) | section: \($0.element.group)" }.joined(separator: "\n")
        let steps = draft.steps.enumerated().map { "[\($0.offset)] section: \($0.element.group) | \($0.element.text)" }.joined(separator: "\n")
        return "Title: \(draft.title)\nServings: \(draft.servings.map(String.init) ?? "unknown")\nTotal minutes: \(draft.durationMinutes.map(String.init) ?? "unknown")\nINGREDIENTS:\n\(ingredients)\nMETHOD:\n\(steps)"
    }
    public static var patchSchema: [String: Any] {
        let operation: [String: Any] = ["type": "string", "enum": ["add", "update", "remove"]]
        return AISchema.object([
            "title": AISchema.optionalString, "servings": AISchema.optionalInteger, "durationMinutes": AISchema.optionalInteger,
            "ingredients": AISchema.array(AISchema.object(["operation": operation, "index": AISchema.integer,
                "name": AISchema.string, "quantity": AISchema.string, "unit": AISchema.string, "group": AISchema.string])),
            "steps": AISchema.array(AISchema.object(["operation": operation, "index": AISchema.integer, "text": AISchema.string, "group": AISchema.string]))
        ])
    }
}
