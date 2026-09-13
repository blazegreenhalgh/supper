import SwiftUI

struct GroceryListView: View {
    @EnvironmentObject private var store: RecipeStore
    @State private var newItem = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add item", text: $newItem)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                    Button(action: addItem) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if !unchecked.isEmpty {
                Section("Grocery List") {
                    ForEach(unchecked) { item in
                        GroceryRow(item: item)
                    }
                    .onDelete(perform: deleteFromDisplayedItems)
                }
            }

            if !checked.isEmpty {
                Section("Done") {
                    ForEach(checked) { item in
                        GroceryRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Grocery")
        .overlay {
            if store.groceryItems.isEmpty {
                ContentUnavailableView(
                    "Your grocery list is empty",
                    systemImage: "cart",
                    description: Text("Add items manually or add ingredients from a recipe.")
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var unchecked: [GroceryItem] { store.groceryItems.filter { !$0.isChecked } }
    private var checked: [GroceryItem] { store.groceryItems.filter(\.isChecked) }

    private func addItem() {
        try? store.addGroceryItem(name: newItem)
        newItem = ""
    }

    private func deleteFromDisplayedItems(at offsets: IndexSet) {
        let ids = offsets.compactMap { unchecked.indices.contains($0) ? unchecked[$0].id : nil }
        let sourceOffsets = IndexSet(store.groceryItems.enumerated().compactMap { ids.contains($0.element.id) ? $0.offset : nil })
        try? store.deleteGroceryItems(at: sourceOffsets)
    }
}

private struct GroceryRow: View {
    @EnvironmentObject private var store: RecipeStore
    let item: GroceryItem

    var body: some View {
        Button {
            try? store.toggleGroceryItem(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text([item.quantity, item.unit, item.name].filter { !$0.isEmpty }.joined(separator: " "))
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    if !item.sourceRecipeIDs.isEmpty {
                        Text("From recipe")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
