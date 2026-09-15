import SwiftUI

struct GroceryListView: View {
    @EnvironmentObject private var store: RecipeStore
    @State private var newItem = ""
    @State private var showingRecipes = true
    @FocusState private var isAddingItem: Bool

    private var checked: [GroceryItem] { store.groceryItems.filter(\.isChecked) }
    private var canAddItem: Bool { !newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var shoppingRecipes: [Recipe] {
        let ids = Set(store.groceryItems.flatMap(\.sourceRecipeIDs))
        return store.recipes.filter { ids.contains($0.id) }
    }

    var body: some View {
        List {
            if !shoppingRecipes.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showingRecipes) {
                        EmptyView()
                    } label: {
                        HStack {
                            Text("Shopping for").font(.headline)
                            Spacer()
                            Text("\(shoppingRecipes.count)").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                    .tint(.primary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))
                    if showingRecipes {
                        ForEach(shoppingRecipes) { recipe in
                            NavigationLink { RecipeDetailView(recipeID: recipe.id) } label: {
                                shoppingRecipeLabel(recipe)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                        }
                    }
                }
                .listSectionSeparator(.hidden)
            }

            ForEach(GroceryAisle.allCases, id: \.self) { aisle in
                // Keep the stored order within each aisle, including checked items.
                let items = store.groceryItems.filter { $0.category == aisle }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            GroceryRow(item: item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
                        }
                        .onDelete { delete($0, from: items) }
                    } header: {
                        Text(aisle.rawValue.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SupperStyle.canvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Groceries")
        .toolbar {
            if !checked.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Grocery options", systemImage: "ellipsis") {
                        Button("Clear checked items", systemImage: "checkmark.circle", role: .destructive) {
                            delete(IndexSet(checked.indices), from: checked)
                        }
                    }
                }
            }
        }
        .overlay {
            if store.groceryItems.isEmpty {
                ContentUnavailableView(
                    "Your grocery list is empty",
                    systemImage: "basket",
                    description: Text("Add an item below, or choose ingredients from a recipe.")
                )
                .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addItemBar
        }
    }

    private var addItemBar: some View {
        SupperGlassGroup {
            HStack(spacing: 10) {
                TextField("Add an item", text: $newItem)
                    .focused($isAddingItem)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 52)
                    .supperGlassSurface()
                    .accessibilityLabel("New grocery item")

                Button(action: addItem) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 28, minHeight: 32)
                }
                .supperGlassButton(prominent: true)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(!canAddItem)
                .accessibilityLabel("Add grocery item")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func shoppingRecipeLabel(_ recipe: Recipe) -> some View {
        let items = store.groceryItems.filter { $0.sourceRecipeIDs.contains(recipe.id) }
        let remaining = items.filter { !$0.isChecked }.count
        return HStack(spacing: 14) {
            RecipeImage(data: recipe.imageData)
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(remaining == 0 ? "All in your basket" : "\(remaining) of \(items.count) items to buy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private func addItem() {
        guard canAddItem else { return }
        do {
            try store.addGroceryItem(name: newItem)
            newItem = ""
            isAddingItem = true
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func delete(_ offsets: IndexSet, from items: [GroceryItem]) {
        let ids = Set(offsets.compactMap { items.indices.contains($0) ? items[$0].id : nil })
        let sourceOffsets = IndexSet(store.groceryItems.indices.filter { ids.contains(store.groceryItems[$0].id) })
        do { try store.deleteGroceryItems(at: sourceOffsets) }
        catch { store.errorMessage = error.localizedDescription }
    }
}

private struct GroceryRow: View {
    @EnvironmentObject private var store: RecipeStore
    let item: GroceryItem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recipeNames: String {
        store.recipes.filter { item.sourceRecipeIDs.contains($0.id) }.map(\.title).joined(separator: ", ")
    }

    var body: some View {
        Button {
            do { try store.toggleGroceryItem(item) }
            catch { store.errorMessage = error.localizedDescription }
        } label: {
            HStack(spacing: 12) {
                IngredientLineItem(
                    name: item.name,
                    amount: [item.quantity, item.unit].filter { !$0.isEmpty }.joined(separator: " "),
                    detail: recipeNames,
                    isChecked: item.isChecked
                )
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Color.primary : Color.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: item.isChecked)
        .contextMenu {
            Menu("Shopping category") {
                Button("Automatic") { category(nil) }
                ForEach(GroceryAisle.allCases, id: \.self) { aisle in Button(aisle.rawValue) { category(aisle) } }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isChecked ? "In basket" : "To buy")
        .accessibilityHint(item.isChecked ? "Double tap to put back on your list" : "Double tap to mark as in your basket")
    }
    private func category(_ aisle: GroceryAisle?) {
        do { try store.setGroceryCategory(aisle, item: item) } catch { store.errorMessage = error.localizedDescription }
    }

}
