import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let supperRecipeCard = UTType(exportedAs: "app.supper.recipe-card", conformingTo: .data)
}

struct RecipeLibraryView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var filter: RecipeFilter
    var isSearch = false
    let transition: Namespace.ID
    let openRecipe: (RecipeRoute) -> Void
    @State private var showingAddRecipe = false
    @State private var showingCollections = false
    @State private var showingTags = false
    @State private var showingHousehold = false
    @State private var showingPicker = false
    @State private var showingSearchAssistant = false
    @State private var showingDiscovery = false
    @State private var editingRecipe: Recipe?
    @State private var groceryRecipe: Recipe?
    @State private var deletingRecipe: Recipe?
    @State private var dropTarget: UUID?
    @StateObject private var discovery = RecipeDiscoveryModel()
    private var columnCount: Int { dynamicTypeSize.isAccessibilitySize ? 1 : 2 }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top), count: columnCount) }
    private var filteredRecipes: [Recipe] { store.recipes.filter { filter.matches($0, collections: store.collections, memberID: store.currentMemberID, members: store.members) } }
    private var allTags: [String] { Array(Set(store.recipes.flatMap(\.tags))).sorted() }
    private var libraryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 14) {
                    if !isSearch {
                        Button { showingDiscovery = true } label: {
                            Label("What are you craving?", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }.supperGlassButton().controlSize(.large).padding(.horizontal, 20)
                            .accessibilityIdentifier("openRecipeDiscovery")
                    }
                    RecipeFilterChips(filter: $filter)
                }
                if isSearch && !filter.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Interpret this search", systemImage: "sparkle.magnifyingglass") { showingSearchAssistant = true }
                        .font(.subheadline).padding(.horizontal, 20)
                }
                if isSearch && !filter.isActive {
                    Text("Search titles, ingredients, tags, notes and collections. You can also describe what you want, such as easy chicken under 30 minutes.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
                }
                if filteredRecipes.isEmpty {
                    ContentUnavailableView {
                        Label(store.recipes.isEmpty ? "No recipes yet" : "No matching recipes", systemImage: "fork.knife")
                    } description: { Text(store.recipes.isEmpty ? "Save a photo and title, or import a recipe." : "Try another search or clear the filters.") } actions: {
                        if filter.isActive { Button("Clear filters") { filter = RecipeFilter() } }
                        else { Button("Add recipe") { showingAddRecipe = true }.supperGlassButton(prominent: true) }
                    }
                } else {
                    if !filter.isActive && !isSearch {
                        ForEach(store.collectionSections.filter(\.isOnHome)) { collection in
                            if collection.id == RecipeCollection.allRecipesID { allRecipesGrid }
                            else { collectionCarousel(collection) }
                        }
                    } else { allRecipesGrid }
                }
            }.padding(.top, 12).padding(.bottom, 32)
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: filter)
        }
    }

    private var allRecipesGrid: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(filter.isActive ? "Results" : "All recipes").font(.title2.bold()).padding(.horizontal, 20)
                .contentTransition(.opacity)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(filteredRecipes) { recipeLink($0) }
            }.padding(.horizontal, 20)
        }
    }

    private func collectionCarousel(_ collection: RecipeCollection) -> some View {
        let recipes = store.recipes.filter { $0.collectionIDs.contains(collection.id) }
        return VStack(alignment: .leading, spacing: 12) {
            Button { filter.collectionIDs = [collection.id] } label: {
                HStack { Text(collection.name).font(.title2.bold()); Spacer(); Image(systemName: "arrow.right").font(.subheadline) }
            }.buttonStyle(.plain).padding(.horizontal, 20)
            if recipes.isEmpty {
                Label("Drop a recipe here", systemImage: "tray.and.arrow.down")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64).padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(recipes) { recipe in
                            recipeLink(recipe, section: collection.id.uuidString)
                                .containerRelativeFrame(.horizontal, count: columnCount, spacing: 16)
                        }
                    }
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
            }
        }
        .padding(.vertical, 6)
        .background(dropTarget == collection.id ? Color.accentColor.opacity(0.1) : .clear, in: .rect(cornerRadius: 20))
        .contentShape(.rect)
        .onDrop(of: [.supperRecipeCard], isTargeted: Binding(get: { dropTarget == collection.id }, set: { targeted in
            if targeted { dropTarget = collection.id }
            else if dropTarget == collection.id { dropTarget = nil }
        })) { providers in receiveDrop(providers, into: collection.id) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("collectionDrop-" + collection.name)
    }

    var body: some View {
        libraryContent
        .background(SupperStyle.canvas)
        .navigationTitle(isSearch ? "Search" : "Supper")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("Library options", systemImage: "ellipsis") {
                    Button("Find new recipes", systemImage: "sparkles") {
                        if isSearch && !discovery.hasResults { discovery.prompt = filter.query }
                        showingDiscovery = true
                    }
                    Button("Pick something", systemImage: "dice") { showingPicker = true }
                    Button("Manage tags", systemImage: "tag") { showingTags = true }.accessibilityIdentifier("manageTags")
                    if !isSearch { Button("Household", systemImage: "person.2") { showingHousehold = true } }
                }
            }
            if !isSearch {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Collections", systemImage: "rectangle.stack") { showingCollections = true }.accessibilityIdentifier("editCollections")
                        .accessibilityHint("Create collections and arrange homepage sections")
                    Button("Add recipe", systemImage: "plus") { showingAddRecipe = true }.accessibilityIdentifier("addRecipe")
                }
            }
        }
        .sheet(isPresented: $showingAddRecipe) { AddRecipeView() }
        .sheet(item: $editingRecipe) { AddRecipeView(recipe: $0) }
        .sheet(item: $groceryRecipe) { AddIngredientsToGroceryView(recipe: $0, servings: $0.servings) }
        .alert("Delete recipe?", isPresented: Binding(get: { deletingRecipe != nil }, set: { if !$0 { deletingRecipe = nil } }), presenting: deletingRecipe) { recipe in
            Button("Delete recipe", role: .destructive) {
                do { try store.deleteRecipe(recipe); deletingRecipe = nil }
                catch { store.errorMessage = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) { deletingRecipe = nil }
        } message: { recipe in Text("Delete \(recipe.title) from the household library?") }
        .sheet(isPresented: $showingDiscovery) { RecipeDiscoveryView(model: discovery) }
        .sheet(isPresented: $showingCollections) { CollectionsView() }
        .sheet(isPresented: $showingTags) { TagsView() }
        .sheet(isPresented: $showingHousehold) { HouseholdSettingsView() }
        .sheet(isPresented: $showingPicker) { PickRecipeView(recipes: filteredRecipes) { id in showingPicker = false; openRecipe(RecipeRoute(recipeID: id)) } }
        .sheet(isPresented: $showingSearchAssistant) { SearchAssistanceView(initialQuery: filter.query, collections: store.collections, tags: allTags) { filter = $0; showingSearchAssistant = false } }
    }
    @ViewBuilder private func recipeLink(_ recipe: Recipe, section: String = "all") -> some View {
        let route = RecipeRoute(recipeID: recipe.id, section: section)
        NavigationLink(value: route) {
            draggableCard(recipe, route: route, section: section)
        }.buttonStyle(.plain)
            .contextMenu {
                Button("Open recipe", systemImage: "arrow.up.right") { openRecipe(route) }
                Menu("Collection", systemImage: "folder") {
                    ForEach(store.collections) { collection in
                        Toggle(collection.name, isOn: Binding(get: {
                            store.recipes.first(where: { $0.id == recipe.id })?.collectionIDs.contains(collection.id) ?? false
                        }, set: { selected in
                            guard let current = store.recipes.first(where: { $0.id == recipe.id }) else { return }
                            var ids = current.collectionIDs
                            if selected { ids.insert(collection.id) } else { ids.remove(collection.id) }
                            do { try store.setMemberships(ids, recipeID: recipe.id) }
                            catch { store.errorMessage = error.localizedDescription }
                        })).accessibilityIdentifier("cardCollection-" + collection.name)
                    }
                    Button("Manage collections…", systemImage: "folder.badge.plus") { showingCollections = true }
                }
                Button("Add to groceries", systemImage: "cart.badge.plus") { groceryRecipe = recipe }
                    .disabled(recipe.ingredients.isEmpty).accessibilityIdentifier("cardAddToGroceries")
                Button("Edit", systemImage: "pencil") { editingRecipe = recipe }.accessibilityIdentifier("cardEditRecipe")
                if let url = recipe.sourceURL { ShareLink(item: url) }
                Button("Delete", systemImage: "trash", role: .destructive) { deletingRecipe = recipe }.accessibilityIdentifier("cardDeleteRecipe")
            } preview: {
                VStack(alignment: .leading, spacing: 12) {
                    RecipeCardView(recipe: recipe)
                    Text("\(recipe.ingredients.count) ingredients · \(recipe.steps.count) steps")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(18).frame(width: 300).background(SupperStyle.canvas)
            }
            .transition(.opacity)
            .accessibilityIdentifier(recipe.title == "Chicken with rice" ? "recipe-test-chicken" : "recipe-" + recipe.id.uuidString)
    }

    @ViewBuilder private func draggableCard(_ recipe: Recipe, route: RecipeRoute, section: String) -> some View {
        let card = RecipeCardView(recipe: recipe, transition: RecipeTransitionSource(id: route.sourceID, namespace: transition))
        if let householdID = store.activeHouseholdID {
            card.onDrag {
                let item = RecipeDragItem(recipeID: recipe.id, householdID: householdID, sourceCollectionID: UUID(uuidString: section))
                guard let data = try? JSONEncoder().encode(item) else { return NSItemProvider() }
                return NSItemProvider(item: data as NSData, typeIdentifier: UTType.supperRecipeCard.identifier)
            } preview: {
                RecipeCardView(recipe: recipe).padding(12).frame(width: 180).background(SupperStyle.canvas, in: .rect(cornerRadius: 20))
            }
        } else { card }
    }

    private func receiveDrop(_ providers: [NSItemProvider], into collectionID: UUID) -> Bool {
        guard providers.count == 1, let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.supperRecipeCard.identifier) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.supperRecipeCard.identifier) { data, _ in
            Task { @MainActor in
                do {
                    guard let data else { throw SupperError.invalid("Couldn't read that recipe card. Try dragging it again.") }
                    let item = try JSONDecoder().decode(RecipeDragItem.self, from: data)
                    try store.moveRecipe(item, to: collectionID)
                } catch { store.errorMessage = error.localizedDescription }
            }
        }
        return true
    }

}

private struct PickRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    let recipes: [Recipe]
    let open: (UUID) -> Void
    @State private var selected: Recipe?
    var body: some View {
        NavigationStack {
            ScrollView {
                if let selected {
                    VStack(alignment: .leading, spacing: 22) {
                        RecipeCardView(recipe: selected)
                        Button("Open recipe") { open(selected.id) }.supperGlassButton(prominent: true).controlSize(.large)
                        if recipes.count > 1 { Button("Choose another", systemImage: "dice") { pick() }.supperGlassButton() }
                        else { Text("This is the only recipe matching your filters.").font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(24)
                } else { ContentUnavailableView("No matching recipes", systemImage: "dice", description: Text("Clear a filter or add a recipe to get started.")) }
            }.background(SupperStyle.canvas).navigationTitle("Pick something").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .onAppear { if selected == nil { pick() } }
        }
    }
    private func pick() { selected = RecipePicker.pick(from: recipes, excluding: selected?.id) }
}

private struct SearchAssistanceView: View {
    @Environment(\.dismiss) private var dismiss
    let collections: [RecipeCollection]
    let tags: [String]
    let apply: (RecipeFilter) -> Void
    @State private var text: String
    @State private var result: RecipeFilter?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    init(initialQuery: String, collections: [RecipeCollection], tags: [String], apply: @escaping (RecipeFilter) -> Void) {
        self.collections = collections; self.tags = tags; self.apply = apply; _text = State(initialValue: initialQuery)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Easy chicken under 30 minutes", text: $text, axis: .vertical)
                    Text(OnDeviceRecipeAssistant.availabilityDescription).font(.footnote).foregroundStyle(.secondary)
                    if busy { ProgressView("Interpreting…"); Button("Cancel") { task?.cancel(); busy = false } }
                    else { Button("Interpret search", action: interpret).disabled(text.isEmpty) }
                }
                if let result {
                    Section("Review filters") {
                        if !result.query.isEmpty { LabeledContent("Keywords", value: result.query) }
                        if let duration = result.maximumMinutes { LabeledContent("Maximum duration", value: "\(duration) min") }
                        if !result.tags.isEmpty { LabeledContent("Tags", value: result.tags.sorted().joined(separator: ", ")) }
                        ForEach(collections.filter { result.collectionIDs.contains($0.id) }) { Text($0.name) }
                        Button("Use these filters") { apply(result) }
                    }
                }
            }.navigationTitle("Interpret search").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { task?.cancel(); dismiss() } } }
                .onDisappear { task?.cancel() }.supperError($error, title: "Couldn't interpret search")
        }
    }
    private func interpret() {
        task?.cancel(); busy = true; result = nil
        task = Task {
            defer { busy = false }
            do { let value = try await OnDeviceRecipeAssistant().interpretSearch(text, collections: collections, tags: tags); try Task.checkCancellation(); result = value }
            catch { if !(error is CancellationError) { self.error = "\(error.localizedDescription) You can still use the search field and filter chips." } }
        }
    }
}
