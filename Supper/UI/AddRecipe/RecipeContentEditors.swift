import SwiftUI

/// Child screens edit only the parent recipe draft. Nothing reaches persistence until Save Recipe.
struct IngredientListEditor: View {
    @Binding var ingredients: [Ingredient]
    let sourceURL: URL?
    @State private var editing: Ingredient?
    @State private var recoveringGroups = false
    @State private var formatting = false

    var body: some View {
        List {
            Section {
                Button("Add ingredient", systemImage: "plus.circle.fill") { editing = Ingredient(name: "") }
                    .accessibilityIdentifier("addIngredient")
            }
            Section {
                ForEach(ingredients) { ingredient in
                    Button { editing = ingredient } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 10) {
                                IngredientLabel(ingredient: ingredient)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            if !ingredient.group.isEmpty {
                                Text(ingredient.group).font(.caption).foregroundStyle(.secondary).padding(.leading, 45)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                .onDelete { ingredients.remove(atOffsets: $0) }
                .onMove { ingredients.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                HStack {
                    Text("\(ingredients.count) ingredients")
                    Spacer()
                    if !ingredients.isEmpty {
                        Button("Auto format", systemImage: "sparkles") { formatting = true }
                            .font(.caption).textCase(nil).buttonStyle(.borderless)
                            .accessibilityIdentifier("autoFormatIngredients")
                    }
                }
            } footer: {
                Text(ingredients.isEmpty ? "Add ingredients one at a time. Quantities, groups and shopping categories are optional." : "Tap an ingredient to edit it. Tap Edit to reorder or remove ingredients.")
            }
            if let sourceURL, ["https", "http"].contains(sourceURL.scheme ?? ""), !ingredients.isEmpty {
                Section {
                    Button("Recover groups from source", systemImage: "arrow.triangle.2.circlepath") { recoveringGroups = true }
                } footer: { Text("Review the source’s ingredient groups before applying them. Your names and amounts stay the same.") }
            }
        }
        .scrollContentBackground(.hidden).background(SupperStyle.canvas)
        .navigationTitle("Ingredients").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton().disabled(ingredients.isEmpty) } }
        .sheet(item: $editing) { ingredient in
            IngredientEditor(ingredient: ingredient, isNew: !ingredients.contains { $0.id == ingredient.id }) { value in
                if let index = ingredients.firstIndex(where: { $0.id == value.id }) { ingredients[index] = value }
                else { ingredients.append(value) }
            }
        }
        .sheet(isPresented: $recoveringGroups) { GroupRecoveryView(ingredients: $ingredients, sourceURL: sourceURL) }
        .sheet(isPresented: $formatting) { IngredientFormattingView(ingredients: $ingredients) }
    }
}

private struct IngredientEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var ingredient: Ingredient
    let isNew: Bool
    let apply: (Ingredient) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredient name") {
                    TextField("e.g. olive oil", text: $ingredient.name, axis: .vertical)
                        .accessibilityIdentifier("ingredientName")
                }
                Section {
                    LabeledContent("Quantity") {
                        TextField("e.g. 1½", text: $ingredient.quantity).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("ingredientQuantity")
                    }
                    LabeledContent("Unit") {
                        TextField("e.g. tbsp", text: $ingredient.unit).multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("ingredientUnit")
                    }
                } header: { Text("Amount · optional") } footer: { Text("Fractions, ranges and amounts such as “to taste” are welcome.") }
                Section {
                    TextField("e.g. Spice mix or Sauce", text: $ingredient.group)
                } header: { Text("Recipe group · optional") } footer: { Text("Group ingredients by what they’re used for in the recipe.") }
                Section {
                    Picker("Category", selection: $ingredient.categoryOverride) {
                        Text("Automatic").tag(Optional<GroceryAisle>.none)
                        ForEach(GroceryAisle.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                } header: { Text("Shopping category") } footer: {
                    Text("Automatic suggestion: \(IngredientPresentation.matching(ingredient.name).aisle.rawValue). Choose a category to override it in Groceries.")
                }
            }
            .scrollContentBackground(.hidden).background(SupperStyle.canvas)
            .navigationTitle(isNew ? "Add Ingredient" : "Edit Ingredient").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done") {
                        ingredient.name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        ingredient.quantity = ingredient.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
                        ingredient.unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
                        ingredient.group = ingredient.group.trimmingCharacters(in: .whitespacesAndNewlines)
                        apply(ingredient); dismiss()
                    }.disabled(ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveIngredient")
                }
            }
        }
    }
}

struct MethodListEditor: View {
    @Binding var steps: [RecipeStep]
    @State private var editing: RecipeStep?
    var body: some View {
        List {
            Section { Button("Add step", systemImage: "plus.circle.fill") { editing = RecipeStep(text: "") } }
            Section {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    Button { editing = step } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Step \(index + 1)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                Text(step.text).font(.body).foregroundStyle(.primary).lineLimit(3)
                            }
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
                .onDelete { steps.remove(atOffsets: $0) }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            } header: { Text("\(steps.count) steps") } footer: { Text("Tap a step to edit it. Tap Edit to change the order or remove steps.") }
        }
        .scrollContentBackground(.hidden).background(SupperStyle.canvas)
        .navigationTitle("Method").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton().disabled(steps.isEmpty) } }
        .sheet(item: $editing) { step in
            MethodStepEditor(step: step, isNew: !steps.contains { $0.id == step.id }) { value in
                if let index = steps.firstIndex(where: { $0.id == value.id }) { steps[index] = value }
                else { steps.append(value) }
            }
        }
    }
}
private struct MethodStepEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var step: RecipeStep
    let isNew: Bool
    let apply: (RecipeStep) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("Instructions") { TextField("What happens in this step?", text: $step.text, axis: .vertical).lineLimit(8...30) }
            }
            .navigationTitle(isNew ? "Add Step" : "Edit Step").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done") { apply(step); dismiss() }
                        .disabled(step.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct DraftCollectionsEditor: View {
    @EnvironmentObject private var store: RecipeStore
    @Binding var selected: Set<UUID>
    var body: some View {
        List {
            if store.collections.isEmpty { Text("Tap Edit on the Recipes screen to create a collection.").foregroundStyle(.secondary) }
            ForEach(store.collections) { collection in
                Toggle(collection.name, isOn: Binding(get: { selected.contains(collection.id) }, set: { on in
                    if on { selected.insert(collection.id) } else { selected.remove(collection.id) }
                }))
            }
        }.navigationTitle("Collections").navigationBarTitleDisplayMode(.inline)
    }
}

struct RecipeTagsEditor: View {
    @Binding var tagsText: String
    let draft: RecipeDraft
    var title = "Tags"
    @State private var suggestions: [String] = []
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("e.g. Easy, Dinner, Vegetarian", text: $tagsText, axis: .vertical).lineLimit(2...6)
                    .accessibilityIdentifier("recipeTagsText")
            } header: { Text("Tags") } footer: { Text("Separate tags with commas. Use them to find recipes in Search.") }
            Section {
                if busy {
                    ProgressView("Suggesting tags…")
                    Button("Cancel suggestions") { task?.cancel(); busy = false }
                } else { Button("Suggest tags", systemImage: "sparkles", action: suggest) }
                ForEach(suggestions, id: \.self) { tag in
                    Button("Add “\(tag)”", systemImage: "plus.circle") {
                        tagsText = tagsText.trimmingCharacters(in: .whitespacesAndNewlines)
                        tagsText += tagsText.isEmpty ? tag : ", " + tag
                        suggestions.removeAll { $0 == tag }
                    }
                }
            }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .onDisappear { task?.cancel() }.supperError($error, title: "Tag suggestions")
    }
    private func suggest() {
        task?.cancel(); busy = true
        task = Task {
            defer { busy = false }
            do {
                let existing = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                let values = try await OnDeviceRecipeAssistant().suggestTags(for: draft)
                try Task.checkCancellation()
                suggestions = values.filter { !existing.contains($0.lowercased()) }
                if suggestions.isEmpty { error = "No additional tags suggested. You can enter your own tags above." }
            } catch { if !(error is CancellationError) { self.error = "\(error.localizedDescription) You can still enter tags manually." } }
        }
    }
}
