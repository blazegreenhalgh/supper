import SwiftUI
import PhotosUI

struct AddRecipeView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    private let original: Recipe?
    @State private var newID = UUID()
    @State private var draft: RecipeDraft
    @State private var photoItem: PhotosPickerItem?
    @State private var urlText: String
    @State private var tagsText: String
    @State private var showingURLImport = false
    @State private var showingAssistant = false
    @State private var showingGroups = false
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive
    @State private var suggestions: [String] = []
    @State private var suggesting = false
    @State private var task: Task<Void, Never>?
    @State private var householdID: UUID?

    init(recipe: Recipe? = nil) {
        original = recipe
        _draft = State(initialValue: recipe.map(RecipeDraft.init(recipe:)) ?? RecipeDraft())
        _urlText = State(initialValue: recipe?.sourceURL?.absoluteString ?? "")
        _tagsText = State(initialValue: recipe?.tags.joined(separator: ", ") ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        if let data = draft.imageData {
                            RecipeImage(data: data).frame(height: 220).clipShape(.rect(cornerRadius: 18))
                        } else {
                            Label("Add a photo", systemImage: "photo.badge.plus").frame(maxWidth: .infinity, minHeight: 90)
                        }
                    }.buttonStyle(.plain)
                    if draft.imageData != nil { Button("Remove photo", role: .destructive) { draft.imageData = nil } }
                    TextField("Recipe name", text: $draft.title).font(.title3.weight(.semibold))
                } footer: { Text("A photo and title are enough. Everything below is optional.") }
                Section("Details") {
                    TextField("Duration in minutes", value: $draft.durationMinutes, format: .number).keyboardType(.numberPad)
                    TextField("Base servings", value: $draft.servings, format: .number).keyboardType(.numberPad)
                    TextField("Tags, separated by commas", text: $tagsText)
                    Button(suggesting ? "Suggesting tags…" : "Suggest tags", systemImage: "sparkles") { suggestTags() }.disabled(suggesting)
                    if suggesting { Button("Cancel suggestions", role: .cancel) { task?.cancel(); suggesting = false } }
                    if !suggestions.isEmpty {
                        ForEach(suggestions, id: \.self) { tag in
                            Button("Add “\(tag)”") {
                                var tags = parsedTags; if !tags.contains(tag) { tags.append(tag) }
                                tagsText = tags.joined(separator: ", "); suggestions.removeAll { $0 == tag }
                            }
                        }
                    }
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                    TextField("Source URL", text: $urlText).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Collections") {
                    if store.collections.isEmpty { Text("Create collections from the homepage menu.").foregroundStyle(.secondary) }
                    ForEach(store.collections) { collection in
                        Toggle(collection.name, isOn: Binding(get: { draft.collectionIDs.contains(collection.id) }, set: { on in
                            if on { draft.collectionIDs.insert(collection.id) } else { draft.collectionIDs.remove(collection.id) }
                        }))
                    }
                }
                Section {
                    ForEach($draft.ingredients) { $ingredient in
                        IngredientEditorRow(ingredient: $ingredient)
                    }
                    .onDelete { draft.ingredients.remove(atOffsets: $0) }
                    .onMove { draft.ingredients.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add ingredient", systemImage: "plus") { draft.ingredients.append(Ingredient(name: "")) }
                    if draft.sourceURL != nil && !draft.ingredients.isEmpty {
                        Button("Recover groups from source", systemImage: "arrow.triangle.2.circlepath") { showingGroups = true }
                    }
                } header: { Text("Ingredients") } footer: { Text("Use Reorder to move or remove ingredients and method steps.") }
                Section("Method") {
                    ForEach($draft.steps) { $step in
                        TextField("Method step", text: $step.text, axis: .vertical).lineLimit(2...12)
                    }
                    .onDelete { draft.steps.remove(atOffsets: $0) }
                    .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add step", systemImage: "plus") { draft.steps.append(RecipeStep(text: "")) }
                }
                if original == nil {
                    Section("Import") {
                        Button("Import from URL", systemImage: "link") { showingURLImport = true }
                        Button("Recipe text or screenshot", systemImage: "text.viewfinder") { showingAssistant = true }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden).background(SupperStyle.canvas)
            .navigationTitle(original == nil ? "New Recipe" : "Edit Recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button(editMode.isEditing ? "Finish reordering" : "Reorder") { editMode = editMode.isEditing ? .inactive : .active } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear { if householdID == nil { householdID = store.activeHouseholdID } }
            .onDisappear { task?.cancel() }
            .onChange(of: photoItem) { _, item in
                task?.cancel(); task = Task {
                    do {
                        if let item, let data = try await item.loadTransferable(type: Data.self) {
                            try Task.checkCancellation(); draft.imageData = data
                        }
                    } catch { if !(error is CancellationError) { errorMessage = "Couldn't load this photo. Choose it again. \(error.localizedDescription)" } }
                }
            }
            .sheet(isPresented: $showingURLImport) { URLImportView(onImported: imported) }
            .sheet(isPresented: $showingAssistant) { RecipeAssistanceView(onImported: imported) }
            .sheet(isPresented: $showingGroups) { GroupRecoveryView(ingredients: $draft.ingredients, sourceURL: draft.sourceURL) }
            .supperError($errorMessage, title: "Couldn't save changes")
        }
    }
    private var parsedTags: [String] {
        var seen = Set<String>()
        return tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
    private func imported(_ value: RecipeDraft) {
        draft = value; urlText = value.sourceURL?.absoluteString ?? ""; tagsText = value.tags.joined(separator: ", ")
        showingURLImport = false; showingAssistant = false
    }
    private func suggestTags() {
        suggesting = true; task?.cancel()
        task = Task {
            defer { suggesting = false }
            do {
                let tags = try await OnDeviceRecipeAssistant().suggestTags(for: draft)
                try Task.checkCancellation(); suggestions = tags.filter { !parsedTags.contains($0) }
                if suggestions.isEmpty { errorMessage = "No additional tags suggested. You can enter your own tags above." }
            } catch { if !(error is CancellationError) { errorMessage = "Couldn't suggest tags. You can still enter them manually. \(error.localizedDescription)" } }
        }
    }
    private func save() {
        do {
            guard householdID == store.activeHouseholdID else { throw SupperError.invalid("The active household changed. Switch back before saving this draft.") }
            let source = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !source.isEmpty {
                guard let url = URL(string: source), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw SupperError.invalid("Use a complete http or https source URL, or leave it empty.") }
                draft.sourceURL = url
            } else { draft.sourceURL = nil }
            draft.tags = parsedTags
            guard draft.ingredients.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), draft.steps.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw SupperError.invalid("Fill in or remove any blank ingredient rows and method steps before saving.")
            }
            if let original {
                guard let latest = store.recipes.first(where: { $0.id == original.id }) else { throw SupperError.invalid("The original recipe is unavailable. Your draft is still here.") }
                try store.updateRecipe(draft.applying(to: latest))
            } else { var recipe = draft.makeRecipe(); recipe.id = newID; try store.addRecipe(recipe) }
            dismiss()
        } catch { errorMessage = "\(error.localizedDescription) Your changes are kept here; correct the problem and tap Save again." }
    }
}

private struct IngredientEditorRow: View {
    @Binding var ingredient: Ingredient
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ingredient name", text: $ingredient.name)
            HStack {
                TextField("Quantity", text: $ingredient.quantity).accessibilityLabel("Ingredient quantity")
                TextField("Unit", text: $ingredient.unit).accessibilityLabel("Ingredient unit")
            }.font(.subheadline)
            DisclosureGroup("Grouping & category") {
                TextField("Recipe group, e.g. Spice mix", text: $ingredient.group)
                Picker("Shopping category", selection: $ingredient.categoryOverride) {
                    Text("Automatic · \(IngredientPresentation.matching(ingredient.name).aisle.rawValue)").tag(Optional<GroceryAisle>.none)
                    ForEach(GroceryAisle.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
            }.font(.subheadline)
        }.padding(.vertical, 6)
    }
}
