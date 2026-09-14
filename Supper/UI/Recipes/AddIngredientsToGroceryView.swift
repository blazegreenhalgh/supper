import SwiftUI

struct AddIngredientsToGroceryView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State private var selected: Set<UUID>
    @State private var errorMessage: String?

    init(recipe: Recipe) {
        self.recipe = recipe
        _selected = State(initialValue: Set(recipe.ingredients.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("\(selected.count) of \(recipe.ingredients.count) ingredients selected", systemImage: "basket")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(SupperStyle.subtle)
                } header: {
                    Text(recipe.title)
                        .textCase(nil)
                        .font(.title3.weight(.semibold))
                }
                Section {
                    ForEach(recipe.ingredients) { ingredient in
                        Button {
                            if selected.contains(ingredient.id) { selected.remove(ingredient.id) }
                            else { selected.insert(ingredient.id) }
                        } label: {
                            HStack {
                                IngredientLabel(ingredient: ingredient)
                                Spacer()
                                Image(systemName: selected.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(ingredient.id) ? .primary : .tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(SupperStyle.surface)
                        .accessibilityValue(selected.contains(ingredient.id) ? "Selected" : "Not selected")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SupperStyle.canvas)
            .navigationTitle("Add to Groceries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let ingredients = recipe.ingredients.filter { selected.contains($0.id) }
                        do {
                            try store.addIngredientsToGroceryList(from: recipe, ingredients: ingredients)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .alert("Couldn't add ingredients", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
}
