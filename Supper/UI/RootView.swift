import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: RecipeStore
    @State private var filter = RecipeFilter()
    @State private var path: [UUID] = []
    var body: some View {
        TabView {
            // Search belongs to this persistent navigation container. It is never created/destroyed
            // by detail appearance, and no destination changes navigation/search material styling.
            NavigationStack(path: $path) {
                RecipeLibraryView(filter: $filter) { path.append($0) }
                    .navigationDestination(for: UUID.self) { RecipeDetailView(recipeID: $0) }
            }
            .searchable(text: $filter.query, prompt: "Recipes, ingredients, tags or collections")
            .tabItem { Label("Recipes", systemImage: "fork.knife") }
            NavigationStack { GroceryListView() }.tabItem { Label("Groceries", systemImage: "basket") }
        }
        .overlay {
            if !store.isReady && store.errorMessage == nil { ProgressView("Loading Supper…").padding(20).supperGlassSurface() }
        }
        .supperError($store.errorMessage, title: "Supper couldn't complete that")
        .sheet(isPresented: Binding(get: { store.pendingInvitation != nil }, set: { if !$0 { store.pendingInvitation = nil } })) { HouseholdInvitationView() }
        .onChange(of: store.activeHouseholdID) { _, _ in path.removeAll(); filter = RecipeFilter() }
    }
}
