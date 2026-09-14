import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: RecipeStore

    var body: some View {
        TabView {
            NavigationStack {
                RecipeLibraryView()
            }
            .tabItem { Label("Recipes", systemImage: "fork.knife") }

            NavigationStack {
                GroceryListView()
            }
            .tabItem { Label("Groceries", systemImage: "basket") }
        }
        .overlay {
            if !store.isReady && store.errorMessage == nil {
                ProgressView("Loading Supper…")
                    .padding(20)
                    .supperGlassSurface()
            }
        }
        .alert("Supper couldn't complete that", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }
}
