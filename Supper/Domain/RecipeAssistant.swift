import Foundation

public enum RecipeEditOperation: String, Codable, Sendable { case add, update, remove }

public struct AssistantIngredientEdit: Codable, Sendable {
    public var operation: RecipeEditOperation
    /// Zero-based index in the supplied draft; -1 for an addition.
    public var index: Int
    public var name: String
    public var quantity: String
    public var unit: String
    public var group: String
    public init(operation: RecipeEditOperation, index: Int = -1, name: String = "", quantity: String = "", unit: String = "", group: String = "") {
        self.operation = operation; self.index = index; self.name = name
        self.quantity = quantity; self.unit = unit; self.group = group
    }
}

public struct AssistantStepEdit: Codable, Sendable {
    public var operation: RecipeEditOperation
    public var index: Int
    public var text: String
    public var group: String
    public init(operation: RecipeEditOperation, index: Int = -1, text: String = "", group: String = "") {
        self.operation = operation; self.index = index; self.text = text; self.group = group
    }
}

/// A bounded, atomic patch. Existing rows retain identity, order and shopping overrides.
/// The model cannot replace the photograph, source, collections or household metadata.
public struct RecipeAssistantPatch: Codable, Sendable {
    public var title: String?
    public var servings: Int?
    public var durationMinutes: Int?
    public var ingredients: [AssistantIngredientEdit] = []
    public var steps: [AssistantStepEdit] = []
    public init(title: String? = nil, servings: Int? = nil, durationMinutes: Int? = nil,
                ingredients: [AssistantIngredientEdit] = [], steps: [AssistantStepEdit] = []) {
        self.title = title; self.servings = servings; self.durationMinutes = durationMinutes
        self.ingredients = ingredients; self.steps = steps
    }

    public func applying(to original: RecipeDraft) throws -> RecipeDraft {
        func invalid() -> SupperError { .invalid("The suggested changes couldn’t be matched to this recipe. Please try a smaller request.") }
        guard ingredients.count <= 60, steps.count <= 40,
              servings.map({ (1...1000).contains($0) }) ?? true,
              durationMinutes.map({ (1...10080).contains($0) }) ?? true else { throw invalid() }
        var result = original
        if let title {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200 else { throw invalid() }
            result.title = title
        }
        if let servings { result.servings = servings }
        if let durationMinutes { result.durationMinutes = durationMinutes }
        var ingredientIndices = Set<Int>()
        var removedIngredients = Set<Int>()
        for edit in ingredients {
            guard edit.name.count <= 300, edit.quantity.count <= 100, edit.unit.count <= 60,
                  edit.group.count <= 100, !edit.group.contains("\n") else { throw invalid() }
            if edit.operation != .remove, edit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw invalid() }
            if edit.operation == .add {
                guard edit.index == -1 else { throw invalid() }
                result.ingredients.append(Ingredient(name: edit.name, quantity: edit.quantity, unit: edit.unit, group: edit.group))
            } else {
                guard original.ingredients.indices.contains(edit.index), ingredientIndices.insert(edit.index).inserted else { throw invalid() }
                if edit.operation == .remove { removedIngredients.insert(edit.index) }
                else {
                    result.ingredients[edit.index].name = edit.name
                    result.ingredients[edit.index].quantity = edit.quantity
                    result.ingredients[edit.index].unit = edit.unit
                    result.ingredients[edit.index].group = edit.group
                }
            }
        }
        result.ingredients = result.ingredients.enumerated().filter { !removedIngredients.contains($0.offset) }.map(\.element)
        var stepIndices = Set<Int>()
        var removedSteps = Set<Int>()
        for edit in steps {
            guard edit.text.count <= 2000, edit.group.count <= 100, !edit.group.contains("\n") else { throw invalid() }
            if edit.operation != .remove, edit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw invalid() }
            if edit.operation == .add {
                guard edit.index == -1 else { throw invalid() }
                result.steps.append(RecipeStep(text: edit.text, group: edit.group))
            } else {
                guard original.steps.indices.contains(edit.index), stepIndices.insert(edit.index).inserted else { throw invalid() }
                if edit.operation == .remove { removedSteps.insert(edit.index) }
                else { result.steps[edit.index].text = edit.text; result.steps[edit.index].group = edit.group }
            }
        }
        result.steps = result.steps.enumerated().filter { !removedSteps.contains($0.offset) }.map(\.element)
        for index in result.ingredients.indices { result.ingredients[index].order = index }
        for index in result.steps.indices { result.steps[index].order = index }
        return result
    }
}

public struct RecipeAssistantSource: Identifiable, Hashable, Sendable {
    public let title: String
    public let url: URL
    public var id: URL { url }
    public init(title: String, url: URL) { self.title = title; self.url = url }
}

public struct RecipeAssistantChange: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let before: String?
    public let after: String?
}

public struct RecipeAssistantProposal: Identifiable, Sendable {
    public let id = UUID()
    public let base: RecipeDraft
    public let suggested: RecipeDraft
    public let sources: [RecipeAssistantSource]
    public init(base: RecipeDraft, suggested: RecipeDraft, sources: [RecipeAssistantSource]) {
        self.base = base; self.suggested = suggested
        var seen = Set<URL>()
        self.sources = sources.filter { seen.insert($0.url).inserted }
    }
    public var changes: [RecipeAssistantChange] {
        var values: [RecipeAssistantChange] = []
        func field(_ label: String, _ before: String?, _ after: String?) {
            if before != after { values.append(RecipeAssistantChange(id: label, label: label, before: before, after: after)) }
        }
        field("Title", base.title, suggested.title)
        field("Servings", base.servings.map(String.init), suggested.servings.map(String.init))
        field("Duration (min)", base.durationMinutes.map(String.init), suggested.durationMinutes.map(String.init))
        func ingredientText(_ item: Ingredient) -> String {
            item.group.isEmpty ? item.displayText : "\(item.group) · \(item.displayText)"
        }
        func stepText(_ item: RecipeStep) -> String {
            item.group.isEmpty ? item.text : "\(item.group) · \(item.text)"
        }
        for item in base.ingredients {
            let next = suggested.ingredients.first { $0.id == item.id }
            if next.map(ingredientText) != ingredientText(item) {
                values.append(RecipeAssistantChange(id: item.id.uuidString, label: "Ingredient", before: ingredientText(item), after: next.map(ingredientText)))
            }
        }
        for item in suggested.ingredients where !base.ingredients.contains(where: { $0.id == item.id }) {
            values.append(RecipeAssistantChange(id: item.id.uuidString, label: "Add ingredient", before: nil, after: ingredientText(item)))
        }
        for item in base.steps {
            let next = suggested.steps.first { $0.id == item.id }
            if next.map(stepText) != stepText(item) {
                values.append(RecipeAssistantChange(id: item.id.uuidString, label: "Method", before: stepText(item), after: next.map(stepText)))
            }
        }
        for item in suggested.steps where !base.steps.contains(where: { $0.id == item.id }) {
            values.append(RecipeAssistantChange(id: item.id.uuidString, label: "Add step", before: nil, after: stepText(item)))
        }
        return values
    }
    public func applying(to current: RecipeDraft) throws -> RecipeDraft {
        guard current == base else { throw SupperError.invalid("You’ve edited the recipe since this suggestion. Ask again to use your latest changes.") }
        guard !sources.isEmpty else { throw SupperError.invalid("No online source was found for this suggestion.") }
        var result = suggested
        let newSources = sources.filter { !result.notes.contains($0.url.absoluteString) && result.sourceURL != $0.url }
        if !newSources.isEmpty {
            let links = newSources.map { "\($0.title)\n\($0.url.absoluteString)" }.joined(separator: "\n\n")
            result.notes += (result.notes.isEmpty ? "" : "\n\n") + "Sources consulted with Ask AI:\n" + links
        }
        return result
    }
}

public struct RecipeAssistantUndo: Sendable {
    public let before: RecipeDraft
    public let after: RecipeDraft
    public init(before: RecipeDraft, after: RecipeDraft) { self.before = before; self.after = after }
    public func restoring(_ current: RecipeDraft) throws -> RecipeDraft {
        guard current == after else { throw SupperError.invalid("The recipe has changed since this AI edit. Undo is unavailable so your newer edits stay intact.") }
        return before
    }
}
