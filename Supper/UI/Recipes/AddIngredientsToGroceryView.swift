import SwiftUI

struct AddIngredientsToGroceryView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State private var selected: Set<UUID>

    init(recipe: Recipe) {
        self.recipe = recipe
        _selected = State(initialValue: Set(recipe.ingredients.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List(recipe.ingredients) { ingredient in
                Button {
                    if selected.contains(ingredient.id) { selected.remove(ingredient.id) }
                    else { selected.insert(ingredient.id) }
                } label: {
                    HStack {
                        Text(ingredient.displayText)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: selected.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(ingredient.id) ? .primary : .tertiary)
                    }
                }
            }
            .navigationTitle("Add to Grocery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let ingredients = recipe.ingredients.filter { selected.contains($0.id) }
                        try? store.addIngredientsToGroceryList(from: recipe, ingredients: ingredients)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
