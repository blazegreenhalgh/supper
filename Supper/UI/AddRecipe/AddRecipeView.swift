import SwiftUI
import PhotosUI

struct AddRecipeView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    private let original: Recipe?
    private let onSaveDraft: ((Recipe) -> Void)?
    @State private var newID = UUID()
    @State private var draft: RecipeDraft
    @State private var photoItem: PhotosPickerItem?
    @State private var urlText: String
    @State private var tagsText: String
    @State private var showingURLImport = false
    @State private var showingAssistant = false
    @State private var chatExpanded = false
    @State private var showingCover = false
    @StateObject private var recipeChat = RecipeChatSession()
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @State private var householdID: UUID?

    init(recipe: Recipe? = nil, onSaveDraft: ((Recipe) -> Void)? = nil) {
        original = recipe
        self.onSaveDraft = onSaveDraft
        _draft = State(initialValue: recipe.map(RecipeDraft.init(recipe:)) ?? RecipeDraft())
        _urlText = State(initialValue: recipe?.sourceURL?.absoluteString ?? "")
        _tagsText = State(initialValue: recipe?.tags.joined(separator: ", ") ?? "")
    }
    var body: some View {
        GeometryReader { geometry in
            editor
                .contentMargins(.bottom, 20, for: .scrollContent)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // The inset follows the keyboard and reserves scroll space.
                    // Only the chat has a material; there is no filled footer.
                    RecipeEditorChatView(draft: assistantDraft, session: recipeChat, expanded: $chatExpanded)
                        .frame(height: chatExpanded ? min(380, max(180, geometry.size.height * 0.48)) : 56)
                        .frame(maxWidth: chatExpanded ? 680 : 420)
                        .padding(.horizontal, chatExpanded ? 12 : 24)
                }
        }
        .onAppear {
            if householdID == nil { householdID = store.activeHouseholdID }
            #if DEBUG
            recipeChat.loadUITestProposal(draft: assistantDraft.wrappedValue, collections: store.collections, householdID: store.activeHouseholdID)
            #endif
        }
        .onDisappear { task?.cancel(); recipeChat.stop() }
    }

    private var editor: some View {
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
                    Button("Generate cover", systemImage: "photo") { showingCover = true }
                        .font(.subheadline).foregroundStyle(.primary)
                        .accessibilityIdentifier("generateRecipeCover")
                    if draft.imageData != nil { Button("Remove photo", role: .destructive) { draft.imageData = nil }.font(.subheadline) }
                } footer: { Text("Start with just a title. Add everything else when you’re ready.") }
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
                        IngredientListEditor(ingredients: $draft.ingredients, sourceURL: URL(string: urlText)) {
                            recipeChat.editingField = $0 ? "ingredient" : nil
                        }
                    } label: {
                        editorLink("Ingredients", systemImage: "carrot", detail: draft.ingredients.isEmpty ? "Add" : "\(draft.ingredients.count) items")
                    }.accessibilityIdentifier("editIngredients")
                    NavigationLink {
                        MethodListEditor(steps: $draft.steps) {
                            recipeChat.editingField = $0 ? "step" : nil
                        }
                    } label: {
                        editorLink("Method", systemImage: "list.number", detail: draft.steps.isEmpty ? "Add" : "\(draft.steps.count) steps")
                    }.accessibilityIdentifier("editMethod")
                }
                Section("Time & servings") {
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
                }
                Section("Details") {
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
                ToolbarItem(placement: .confirmationAction) { Button(onSaveDraft == nil ? "Save" : "Done", action: save).disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
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
            .sheet(isPresented: $showingCover) { RecipeCoverView(draft: assistantDraft) }
            .supperError($errorMessage, title: "Couldn't save changes")
        }
    }
    private var assistantDraft: Binding<RecipeDraft> {
        Binding(get: {
            var value = draft
            value.tags = parsedTags
            let source = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            value.sourceURL = source.isEmpty ? nil : URL(string: source)
            return value
        }, set: { draft = $0 })
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
            guard onSaveDraft != nil || householdID == store.activeHouseholdID else { throw SupperError.invalid("The active household changed. Switch back before saving this draft.") }
            let source = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !source.isEmpty {
                guard let url = URL(string: source), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw SupperError.invalid("Use a complete http or https source URL, or leave it empty.") }
                draft.sourceURL = url
            } else { draft.sourceURL = nil }
            draft.tags = parsedTags
            guard draft.servings.map({ $0 > 0 }) ?? true, draft.durationMinutes.map({ $0 > 0 }) ?? true else {
                throw SupperError.invalid("Servings and duration must be positive, or leave them empty.")
            }
            guard draft.ingredients.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), draft.steps.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw SupperError.invalid("Fill in or remove any blank ingredient rows and method steps before saving.")
            }
            if let onSaveDraft, let original {
                onSaveDraft(draft.applying(to: original))
            } else if let original {
                guard let latest = store.recipes.first(where: { $0.id == original.id }) else { throw SupperError.invalid("The original recipe is unavailable. Your draft is still here.") }
                try store.updateRecipe(draft.applying(to: latest))
            } else { var recipe = draft.makeRecipe(); recipe.id = newID; try store.addRecipe(recipe) }
            dismiss()
        } catch { errorMessage = "\(error.localizedDescription) Your changes are kept here; correct the problem and tap Save again." }
    }
}
