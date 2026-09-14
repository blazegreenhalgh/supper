import SwiftUI

struct AddIngredientsToGroceryView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let servings: Int?
    @State private var operationID = UUID()
    @State private var householdID: UUID?
    private var scaledIngredients: [Ingredient] { recipe.ingredients.map { $0.scaled(from: recipe.servings, to: servings) } }
    @State private var selected: Set<UUID>
    @State private var errorMessage: String?

    init(recipe: Recipe, servings: Int? = nil) {
        self.recipe = recipe
        self.servings = servings
        _selected = State(initialValue: Set(recipe.ingredients.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(IngredientSection.sections(scaledIngredients)) { group in
                  Section(group.title) {
                    ForEach(group.ingredients) { ingredient in
                        Button {
                            if selected.contains(ingredient.id) { selected.remove(ingredient.id) }
                            else { selected.insert(ingredient.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(ingredient.id) ? Color.accentColor : Color.secondary)
                                    .font(.title3).accessibilityHidden(true)
                                IngredientLabel(ingredient: ingredient)
                            }.contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("groceryIngredient-" + ingredient.id.uuidString)
                        .accessibilityValue(selected.contains(ingredient.id) ? "Selected" : "Not selected")
                    }
                }
                  }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(SupperStyle.canvas)
            .navigationTitle("Add to Groceries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") {
                        let ingredients = scaledIngredients.filter { selected.contains($0.id) }
                        do {
                            guard householdID == store.activeHouseholdID else { throw SupperError.invalid("The household changed. Reopen Add to Groceries in the intended household.") }
                            try store.addIngredientsToGroceryList(from: recipe, ingredients: ingredients, operationID: operationID)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .onAppear { if householdID == nil { householdID = store.activeHouseholdID } }
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
