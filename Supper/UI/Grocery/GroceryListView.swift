import SwiftUI

struct GroceryListView: View {
    @EnvironmentObject private var store: RecipeStore
    @State private var newItem = ""
    @State private var showingRecipes = true
    @FocusState private var isAddingItem: Bool

    private var unchecked: [GroceryItem] { store.groceryItems.filter { !$0.isChecked } }
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
                        ForEach(shoppingRecipes) { recipe in
                            NavigationLink {
                                RecipeDetailView(recipeID: recipe.id)
                            } label: {
                                shoppingRecipeLabel(recipe)
                            }
                            .listRowBackground(SupperStyle.surface)
                        }
                    } label: {
                        HStack {
                            Text("Shopping for").font(.headline)
                            Text("\(shoppingRecipes.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                    .listRowBackground(SupperStyle.subtle)
                }
            }

            ForEach(GroceryAisle.allCases, id: \.self) { aisle in
                let items = unchecked.filter { $0.category == aisle }
                if !items.isEmpty {
                    Section(aisle.rawValue) {
                        ForEach(items) { item in
                            GroceryRow(item: item)
                                .listRowBackground(SupperStyle.surface)
                        }
                        .onDelete { delete($0, from: items) }
                    }
                }
            }

            if !checked.isEmpty {
                Section("In basket · \(checked.count)") {
                    ForEach(checked) { item in
                        GroceryRow(item: item)
                            .listRowBackground(SupperStyle.surface)
                    }
                    .onDelete { delete($0, from: checked) }
                }
            }
        }
        .listStyle(.insetGrouped)
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

    private var recipeNames: String {
        store.recipes.filter { item.sourceRecipeIDs.contains($0.id) }.map(\.title).joined(separator: ", ")
    }

    var body: some View {
        Button {
            do { try store.toggleGroceryItem(item) }
            catch { store.errorMessage = error.localizedDescription }
        } label: {
            HStack(spacing: 20) {
                IngredientIcon(name: item.name)
                    .opacity(item.isChecked ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    let amount = [item.quantity, item.unit].filter { !$0.isEmpty }.joined(separator: " ")
                    Text("\(Text(amount).bold())\(amount.isEmpty ? "" : " ")\(item.name)")
                        .font(.callout).lineSpacing(3)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !recipeNames.isEmpty {
                        Text(recipeNames)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isChecked ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
