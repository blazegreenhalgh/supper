import SwiftUI

struct RecipeTagsSheet: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State private var tagsText: String
    @State private var householdID: UUID?
    @State private var error: String?
    @State private var addingTags = false
    @State private var newTagsText = ""

    init(recipe: Recipe) {
        self.recipe = recipe
        _tagsText = State(initialValue: recipe.tags.joined(separator: ", "))
    }
    private var tags: [String] {
        var seen = Set<String>()
        return tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if tags.isEmpty { Text("Add tags to make this recipe easier to find.").foregroundStyle(.secondary) }
                    ForEach(tags, id: \.self) { Text($0).font(.body) }
                        .onDelete { offsets in
                            var values = tags; values.remove(atOffsets: offsets)
                            tagsText = values.joined(separator: ", ")
                        }
                    Button {
                        newTagsText = ""; addingTags = true
                    } label: { Label("Add more tags", systemImage: "plus.circle") }
                        .accessibilityIdentifier("addMoreTags")
                } footer: { if !tags.isEmpty { Text("Swipe a tag to remove it.") } }
            }
            .scrollContentBackground(.hidden).background(SupperStyle.canvas)
            .navigationTitle("Tags").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            guard householdID == store.activeHouseholdID,
                                  var latest = store.recipes.first(where: { $0.id == recipe.id }) else {
                                throw SupperError.invalid("Switch back to this recipe’s household before saving your tags.")
                            }
                            // Change only tags on the latest recipe, retaining reactions and every other field.
                            latest.tags = tags
                            try store.updateRecipe(latest)
                            dismiss()
                        } catch { self.error = "\(error.localizedDescription) Your tags are kept here; try Save again." }
                    }
                }
            }
            .onAppear { if householdID == nil { householdID = store.activeHouseholdID } }
            .supperError($error, title: "Couldn't save tags")
            .sheet(isPresented: $addingTags) {
                NavigationStack {
                    RecipeTagsEditor(tagsText: $newTagsText, draft: RecipeDraft(recipe: recipe), title: "Add Tags")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { addingTags = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") {
                                    tagsText = ([tagsText, newTagsText].filter { !$0.isEmpty }).joined(separator: ", ")
                                    addingTags = false
                                }.disabled(newTagsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .accessibilityIdentifier("confirmNewTags")
                            }
                        }
                }
            }
        }
    }
}
