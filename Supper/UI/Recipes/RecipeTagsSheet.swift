import SwiftUI

struct RecipeTagsSheet: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    private let onSaveTags: (([String]) -> Void)?
    @State private var tags: [String]
    @State private var householdID: UUID?
    @State private var error: String?

    init(recipe: Recipe, onSaveTags: (([String]) -> Void)? = nil) {
        self.recipe = recipe
        self.onSaveTags = onSaveTags
        _tags = State(initialValue: RecipeTagNames.normalized(recipe.tags))
    }
    var body: some View {
        NavigationStack {
            RecipeTagsEditor(tags: $tags, draft: RecipeDraft(recipe: recipe))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(onSaveTags == nil ? "Save" : "Done", action: save)
                    }
                }
                .onAppear { if householdID == nil { householdID = store.activeHouseholdID } }
                .supperError($error, title: "Couldn't save tags")
        }
    }
    private func save() {
        do {
            let tags = RecipeTagNames.normalized(tags)
            if let onSaveTags { onSaveTags(tags); dismiss(); return }
            guard householdID == store.activeHouseholdID,
                  var latest = store.recipes.first(where: { $0.id == recipe.id }) else {
                throw SupperError.invalid("Switch back to this recipe’s household before saving your tags.")
            }
            latest.tags = tags
            try store.updateRecipe(latest)
            dismiss()
        } catch { self.error = "\(error.localizedDescription) Your tags are kept here; try Save again." }
    }
}

struct TagsView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var namingTag = false
    @State private var originalName: String?
    @State private var name = ""
    @State private var deletingTag: String?
    @State private var confirmingDelete = false
    @State private var householdID: UUID?
    @State private var error: String?
    private var visibleTags: [String] {
        store.tags.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(visibleTags, id: \.self) { tag in
                        Button { edit(tag) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tag").foregroundStyle(.secondary)
                                Text(tag).foregroundStyle(.primary)
                                Spacer()
                                let count = store.recipes.filter { recipe in recipe.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }.count
                                Text("\(count)").font(.subheadline).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 5)
                        }
                        .accessibilityIdentifier("manageTag-" + tag)
                        .accessibilityHint("Rename this tag on all recipes")
                        .swipeActions {
                            Button("Delete", role: .destructive) { deletingTag = tag; confirmingDelete = true }
                        }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { edit(tag) }
                            Button("Delete tag", systemImage: "trash", role: .destructive) { deletingTag = tag; confirmingDelete = true }
                        }
                    }
                } footer: {
                    if !store.tags.isEmpty { Text("Tap a tag to rename it everywhere. Swipe to delete it from all recipes.") }
                }
            }
            .overlay {
                if visibleTags.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Your tags start here" : "No matching tags", systemImage: "tag",
                        description: Text(query.isEmpty ? "Create a tag, then add it to any recipe." : "Try another tag name."))
                        .allowsHitTesting(false)
                }
            }
            .scrollContentBackground(.hidden).background(SupperStyle.canvas)
            .navigationTitle("Tags").navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "Find a tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New tag", systemImage: "plus") {
                        originalName = nil; name = ""; namingTag = true
                    }.accessibilityIdentifier("newLibraryTag")
                }
            }
            .alert(originalName == nil ? "New Tag" : "Rename Tag", isPresented: $namingTag) {
                TextField("Tag name", text: $name).accessibilityIdentifier("libraryTagName")
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    do { try checkHousehold(); try store.saveTag(name, replacing: originalName) }
                    catch { self.error = error.localizedDescription }
                }.disabled(RecipeTagNames.clean(name).isEmpty)
            } message: {
                if originalName != nil { Text("This changes the tag on every recipe. Using an existing name combines the tags.") }
            }
            .alert("Delete tag?", isPresented: $confirmingDelete, presenting: deletingTag) { tag in
                Button("Delete tag", role: .destructive) {
                    do { try checkHousehold(); try store.deleteTag(tag) }
                    catch { self.error = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) { }
            } message: { tag in Text("Remove “\(tag)” from all recipes? Your recipes will stay in the library.") }
            .onAppear { if householdID == nil { householdID = store.activeHouseholdID } }
            .supperError($error, title: "Couldn't update tag")
        }
    }
    private func edit(_ tag: String) { originalName = tag; name = tag; namingTag = true }
    private func checkHousehold() throws {
        guard householdID == store.activeHouseholdID else { throw SupperError.invalid("The household changed. Reopen Tags to continue." ) }
    }
}
