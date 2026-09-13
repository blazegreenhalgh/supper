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
            .tabItem { Label("Grocery", systemImage: "cart") }
        }
        .overlay {
            if !store.isReady && store.errorMessage == nil {
                ProgressView("Loading Supper…")
                    .padding(20)
                    .background(.regularMaterial, in: .rect(cornerRadius: 20))
            }
        }
        .alert("Supper couldn't load", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }
}
