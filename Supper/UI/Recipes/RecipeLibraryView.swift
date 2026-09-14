import SwiftUI

struct RecipeLibraryView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingAddRecipe = false
    @State private var searchText = ""

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

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
                            .supperGlassButton(prominent: true)
                    }
                }
                .padding(.top, 90)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(filteredRecipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeCardView(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .background(SupperStyle.canvas)
        .navigationTitle("Supper")
        .navigationDestination(for: Recipe.self) { recipe in
            RecipeDetailView(recipeID: recipe.id)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Recipes, ingredients or tags")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddRecipe = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add recipe")
            }
        }
        .sheet(isPresented: $showingAddRecipe) {
            AddRecipeView()
        }
    }
}
