import SwiftUI

@main
struct SupperApp: App {
    @StateObject private var store = RecipeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.load() }
        }
    }
}
