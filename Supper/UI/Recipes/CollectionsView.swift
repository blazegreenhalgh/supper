import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: RecipeCollection?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.collectionSections) { collection in
                        VStack(alignment: .leading, spacing: 10) {
                            if collection.id == RecipeCollection.allRecipesID {
                                Label("My recipes", systemImage: "square.grid.2x2").font(.headline)
                                Text("Always on homepage").font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Button { editing = collection } label: { Label(collection.name, systemImage: "folder").font(.headline) }.buttonStyle(.borderless)
                                Toggle("Show on homepage", isOn: Binding(get: { collection.isOnHome }, set: { on in
                                    var changed = collection; changed.isOnHome = on
                                    do { try store.saveCollection(changed) } catch { self.error = error.localizedDescription }
                                })).font(.subheadline).tint(Color(uiColor: .systemBlue))
                            }
                        }.padding(.vertical, 4)
                            .deleteDisabled(collection.id == RecipeCollection.allRecipesID)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.collectionSections[$0].id }.filter { $0 != RecipeCollection.allRecipesID }
                        do { for id in ids { try store.deleteCollection(id) } } catch { self.error = error.localizedDescription }
                    }
                    .onMove { offsets, destination in
                        var ids = store.collectionSections.map(\.id); ids.move(fromOffsets: offsets, toOffset: destination)
                        do { try store.reorderCollections(ids) } catch { self.error = error.localizedDescription }
                    }
                } footer: { Text("Tap Edit to reorder homepage sections, or tap a collection to rename it. Hiding a section keeps its collection. Deleting a collection keeps all its recipes.") }
                Button("New collection", systemImage: "folder.badge.plus") { editing = RecipeCollection(name: "", order: (store.collectionSections.filter { $0.order != Int.max }.map(\.order).max() ?? -1) + 1) }
                Section {
                    Label("Explore", systemImage: "safari")
                } footer: {
                    Text("Recipes saved for later have their own Explore tab. Move them to My Recipes when you want them in your regular rotation.")
                }
            }.navigationTitle("Collections").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }; ToolbarItem(placement: .primaryAction) { EditButton() } }
                .sheet(item: $editing) { CollectionEditorView(collection: $0) }
                .supperError($error, title: "Couldn't update collection")
        }
    }
}

struct RecipeLocationButton: View {
    @EnvironmentObject private var store: RecipeStore
    let recipe: Recipe

    var body: some View {
        Button(recipe.isInExplore ? "Move to My Recipes" : "Move to Explore", systemImage: recipe.isInExplore ? "fork.knife" : "safari") {
            do { try store.setExplore(!recipe.isInExplore, recipeID: recipe.id) }
            catch { store.errorMessage = error.localizedDescription }
        }
        .accessibilityIdentifier("moveRecipeLocation")
        .accessibilityHint(recipe.isInExplore ? "Moves this recipe from Explore to your regular recipes" : "Saves this recipe for later in Explore")
    }
}
private struct CollectionEditorView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    @State var collection: RecipeCollection
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form { TextField("Collection name", text: $collection.name); Toggle("Show on homepage", isOn: $collection.isOnHome).tint(Color(uiColor: .systemBlue)) }
                .navigationTitle("Collection").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { do { try store.saveCollection(collection); dismiss() } catch { self.error = error.localizedDescription } } }
                }.supperError($error, title: "Couldn't save collection")
        }
    }
}
struct CollectionMembershipView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State private var selected: Set<UUID>
    @State private var error: String?
    @State private var householdID: UUID?
    init(recipe: Recipe) { self.recipe = recipe; _selected = State(initialValue: recipe.collectionIDs) }
    var body: some View {
        NavigationStack {
            List {
                Text("Explore keeps this recipe saved for later, separate from My Recipes. Other collections can be used in either place.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(store.collections) { collection in
                    Toggle(collection.name, isOn: Binding(get: { selected.contains(collection.id) }, set: { on in if on { selected.insert(collection.id) } else { selected.remove(collection.id) } })).tint(Color(uiColor: .systemBlue))
                }
            }.navigationTitle("Collections").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        do {
                            guard householdID == store.activeHouseholdID else { throw SupperError.invalid("The household changed. Reopen collections for this recipe.") }
                            try store.setMemberships(selected, recipeID: recipe.id); dismiss()
                        } catch { self.error = error.localizedDescription }
                    } }
                }.onAppear { if householdID == nil { householdID = store.activeHouseholdID } }.supperError($error, title: "Couldn't update collections")
        }
    }
}
