import SwiftUI

struct RecipeRoute: Hashable {
    let recipeID: UUID
    let sourceID: String
    init(recipeID: UUID, section: String = "all") {
        self.recipeID = recipeID
        self.sourceID = section + "-" + recipeID.uuidString
    }
}

struct RootView: View {
    @EnvironmentObject private var store: RecipeStore
    @State private var filter = RecipeFilter()
    @State private var path: [RecipeRoute] = []
    @Namespace private var recipeTransition
    @Namespace private var searchTransition
    @Namespace private var exploreTransition
    @State private var exploreFilter = RecipeFilter()
    @State private var explorePath: [RecipeRoute] = []
    @State private var searchFilter = RecipeFilter()
    @State private var searchPath: [RecipeRoute] = []
    var body: some View {
        TabView {
            Tab("Recipes", systemImage: "fork.knife") {
                NavigationStack(path: $path) {
                    RecipeLibraryView(filter: $filter, transition: recipeTransition) { path.append($0) }
                        .navigationDestination(for: RecipeRoute.self) { route in
                            RecipeDetailView(recipeID: route.recipeID)
                                .supperRecipeZoom(sourceID: route.sourceID, in: recipeTransition)
                        }
                }
            }
            Tab("Groceries", systemImage: "basket") {
                NavigationStack { GroceryListView() }
            }
            Tab("Explore", systemImage: "safari") {
                NavigationStack(path: $explorePath) {
                    RecipeLibraryView(filter: $exploreFilter, isExplore: true, transition: exploreTransition) { explorePath.append($0) }
                        .navigationDestination(for: RecipeRoute.self) { route in
                            RecipeDetailView(recipeID: route.recipeID)
                                .supperRecipeZoom(sourceID: route.sourceID, in: exploreTransition)
                        }
                }
            }
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                // Keep search attached to a stable stack throughout pushes and interactive pops.
                NavigationStack(path: $searchPath) {
                    RecipeLibraryView(filter: $searchFilter, isSearch: true, transition: searchTransition) { searchPath.append($0) }
                        .navigationDestination(for: RecipeRoute.self) { route in
                            RecipeDetailView(recipeID: route.recipeID)
                                .supperRecipeZoom(sourceID: route.sourceID, in: searchTransition)
                        }
                }
                .searchable(text: $searchFilter.query, prompt: "Recipes, ingredients, tags or collections")
                .searchPresentationToolbarBehavior(.avoidHidingContent)
            }
        }
        .overlay {
            if !store.isReady && store.errorMessage == nil { ProgressView("Loading Supper…").padding(20).supperGlassSurface() }
        }
        .supperError($store.errorMessage, title: "Supper couldn't complete that")
        .sheet(isPresented: Binding(get: { store.pendingInvitation != nil }, set: { if !$0 { store.pendingInvitation = nil } })) { HouseholdInvitationView() }
        .onChange(of: store.activeHouseholdID) { _, _ in
            path.removeAll(); searchPath.removeAll(); explorePath.removeAll()
            filter = RecipeFilter(); searchFilter = RecipeFilter(); exploreFilter = RecipeFilter()
        }
    }
}
