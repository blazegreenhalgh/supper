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
    @State private var errorMessage: String?
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
                        VStack(spacing: 10) {
                            if let data = draft.imageData {
                                RecipeImage(data: data).frame(height: 180).clipShape(.rect(cornerRadius: 16))
                            }
                            Label(draft.imageData == nil ? "Add photo" : "Change photo", systemImage: "photo.badge.plus")
                                .font(.subheadline.weight(.medium)).foregroundStyle(.tint)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }.buttonStyle(.plain)
                    TextField("Recipe name", text: $draft.title).font(.title3.weight(.semibold))
                    if draft.imageData != nil { Button("Remove photo", role: .destructive) { draft.imageData = nil }.font(.subheadline) }
                } footer: { Text("Start with a photo and title. Everything else is optional.") }
                if original == nil {
                    Section("Import a recipe") {
                        Button { showingURLImport = true } label: {
                            Label("From a website", systemImage: "link")
                        }
                        Button { showingAssistant = true } label: {
                            Label("From text or a recipe photo", systemImage: "text.viewfinder")
                        }
                    }
                }
                Section("Recipe") {
                    NavigationLink {
                        IngredientListEditor(ingredients: $draft.ingredients, sourceURL: URL(string: urlText))
                    } label: {
                        editorLink("Ingredients", systemImage: "carrot", detail: draft.ingredients.isEmpty ? "Add" : "\(draft.ingredients.count) items")
                    }.accessibilityIdentifier("editIngredients")
                    NavigationLink {
                        MethodListEditor(steps: $draft.steps)
                    } label: {
                        editorLink("Method", systemImage: "list.number", detail: draft.steps.isEmpty ? "Add" : "\(draft.steps.count) steps")
                    }.accessibilityIdentifier("editMethod")
                }
                Section("Details") {
                    LabeledContent("Duration") {
                        HStack(spacing: 4) {
                            TextField("Optional", value: $draft.durationMinutes, format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).accessibilityLabel("Duration in minutes")
                            Text("min").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Base servings") {
                        TextField("Optional", value: $draft.servings, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).accessibilityLabel("Base servings")
                    }
                    NavigationLink {
                        RecipeTagsEditor(tagsText: $tagsText, draft: draft)
                    } label: { editorLink("Tags", systemImage: "tag", detail: parsedTags.isEmpty ? "Add" : "\(parsedTags.count)") }
                    NavigationLink {
                        DraftCollectionsEditor(selected: $draft.collectionIDs)
                    } label: { editorLink("Collections", systemImage: "folder", detail: draft.collectionIDs.isEmpty ? "Add" : "\(draft.collectionIDs.count)") }
                    NavigationLink {
                        Form {
                            Section("Notes") { TextField("Anything you’d like to remember", text: $draft.notes, axis: .vertical).lineLimit(8...30) }
                        }.navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
                    } label: { editorLink("Notes", systemImage: "note.text", detail: draft.notes.isEmpty ? "Add" : "Edit") }
                }
                Section("Source") {
                    TextField("Website URL (optional)", text: $urlText).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .scrollContentBackground(.hidden).background(SupperStyle.canvas)
            .navigationTitle(original == nil ? "New Recipe" : "Edit Recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } }
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
    private func editorLink(_ title: String, systemImage: String, detail: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
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
