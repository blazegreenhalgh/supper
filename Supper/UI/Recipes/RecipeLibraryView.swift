import SwiftUI

struct RecipeLibraryView: View {
    @EnvironmentObject private var store: RecipeStore
    @State private var showingAddRecipe = false
    @State private var searchText = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var filteredRecipes: [Recipe] {
        guard !searchText.isEmpty else { return store.recipes }
        return store.recipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(searchText)
            || recipe.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        ScrollView {
            if filteredRecipes.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "No recipes yet" : "No recipes found", systemImage: "fork.knife")
                } description: {
                    Text(searchText.isEmpty ? "Add something you already make, or import a recipe from a URL." : "Try another search or tag.")
                } actions: {
                    if searchText.isEmpty {
                        Button("Add Recipe") { showingAddRecipe = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 90)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(filteredRecipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeCardView(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Supper")
        .navigationDestination(for: Recipe.self) { recipe in
            RecipeDetailView(recipeID: recipe.id)
        }
        .searchable(text: $searchText, prompt: "Recipes, ingredients or tags")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddRecipe = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRecipe) {
            AddRecipeView()
        }
    }
}
