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
                    ForEach(store.collections) { collection in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { editing = collection } label: { Label(collection.name, systemImage: "folder").font(.headline) }.buttonStyle(.plain)
                            Toggle("Show on homepage", isOn: Binding(get: { collection.isOnHome }, set: { on in
                                var changed = collection; changed.isOnHome = on
                                do { try store.saveCollection(changed) } catch { self.error = error.localizedDescription }
                            })).font(.subheadline)
                        }.padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.collections[$0].id }
                        do { for id in ids { try store.deleteCollection(id) } } catch { self.error = error.localizedDescription }
                    }
                    .onMove { offsets, destination in
                        var ids = store.collections.map(\.id); ids.move(fromOffsets: offsets, toOffset: destination)
                        do { try store.reorderCollections(ids) } catch { self.error = error.localizedDescription }
                    }
                } footer: { Text("Drag to arrange homepage sections. Hiding a section keeps its collection. Deleting a collection keeps all its recipes.") }
                Button("New collection", systemImage: "folder.badge.plus") { editing = RecipeCollection(name: "", order: store.collections.count) }
            }.navigationTitle("Collections & home").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }; ToolbarItem(placement: .primaryAction) { EditButton() } }
                .sheet(item: $editing) { CollectionEditorView(collection: $0) }
                .supperError($error, title: "Couldn't update collection")
        }
    }
}
private struct CollectionEditorView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    @State var collection: RecipeCollection
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form { TextField("Collection name", text: $collection.name); Toggle("Show on homepage", isOn: $collection.isOnHome) }
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
                if store.collections.isEmpty { Text("Create a collection from Collections & homepage in the library menu.").foregroundStyle(.secondary) }
                ForEach(store.collections) { collection in
                    Toggle(collection.name, isOn: Binding(get: { selected.contains(collection.id) }, set: { on in if on { selected.insert(collection.id) } else { selected.remove(collection.id) } }))
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
