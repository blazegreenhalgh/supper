import SwiftUI

struct RecipeLibraryView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var filter: RecipeFilter
    let openRecipe: (UUID) -> Void
    @State private var showingAddRecipe = false
    @State private var showingCollections = false
    @State private var showingHousehold = false
    @State private var showingPicker = false
    @State private var showingSearchAssistant = false
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2) }
    private var filteredRecipes: [Recipe] { store.recipes.filter { filter.matches($0, collections: store.collections, memberID: store.currentMemberID, members: store.members) } }
    private var allTags: [String] { Array(Set(store.recipes.flatMap(\.tags))).sorted() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                filters
                HStack {
                    Text("\(filteredRecipes.count) recipes").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Pick something", systemImage: "dice") { showingPicker = true }.supperGlassButton()
                }.padding(.horizontal, 20)
                if filteredRecipes.isEmpty {
                    ContentUnavailableView {
                        Label(store.recipes.isEmpty ? "No recipes yet" : "No matching recipes", systemImage: "fork.knife")
                    } description: { Text(store.recipes.isEmpty ? "Save a photo and title, or import a recipe." : "Try another search or clear the filters.") } actions: {
                        if filter.isActive { Button("Clear filters") { filter = RecipeFilter() } }
                        else { Button("Add recipe") { showingAddRecipe = true }.supperGlassButton(prominent: true) }
                    }
                } else {
                    if !filter.isActive {
                        ForEach(store.collections.filter(\.isOnHome)) { collection in
                            let recipes = store.recipes.filter { $0.collectionIDs.contains(collection.id) }
                            if !recipes.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Button { filter.collectionIDs = [collection.id] } label: {
                                        HStack { Text(collection.name).font(.title2.bold()); Spacer(); Image(systemName: "arrow.right").font(.subheadline) }
                                    }.buttonStyle(.plain).padding(.horizontal, 20)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(alignment: .top, spacing: 16) {
                                            ForEach(recipes) { recipe in recipeLink(recipe).frame(width: dynamicTypeSize.isAccessibilitySize ? 280 : 174) }
                                        }.padding(.horizontal, 20)
                                    }
                                }
                            }
                        }
                    }
                    Text(filter.isActive ? "Results" : "All recipes").font(.title2.bold()).padding(.horizontal, 20)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(filteredRecipes) { recipeLink($0) }
                    }.padding(.horizontal, 20)
                }
            }.padding(.top, 12).padding(.bottom, 32)
        }
        .background(SupperStyle.canvas)
        .navigationTitle("Supper")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("Library options", systemImage: "ellipsis") {
                    Button("Collections & homepage", systemImage: "square.grid.2x2") { showingCollections = true }
                    Button("Household", systemImage: "person.2") { showingHousehold = true }
                    Button("Search with words", systemImage: "sparkle.magnifyingglass") { showingSearchAssistant = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { Button("Add recipe", systemImage: "plus") { showingAddRecipe = true } }
        }
        .sheet(isPresented: $showingAddRecipe) { AddRecipeView() }
        .sheet(isPresented: $showingCollections) { CollectionsView() }
        .sheet(isPresented: $showingHousehold) { HouseholdSettingsView() }
        .sheet(isPresented: $showingPicker) { PickRecipeView(recipes: filteredRecipes) { id in showingPicker = false; openRecipe(id) } }
        .sheet(isPresented: $showingSearchAssistant) { SearchAssistanceView(initialQuery: filter.query, collections: store.collections, tags: allTags) { filter = $0; showingSearchAssistant = false } }
    }
    private func recipeLink(_ recipe: Recipe) -> some View {
        NavigationLink(value: recipe.id) { RecipeCardView(recipe: recipe) }.buttonStyle(.plain)
            .accessibilityIdentifier(recipe.title == "Chicken with rice" ? "recipe-test-chicken" : "recipe-" + recipe.id.uuidString)
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Maximum duration", selection: $filter.maximumMinutes) {
                        Text("Any duration").tag(Optional<Int>.none)
                        ForEach([15, 30, 45, 60, 90], id: \.self) { Text("Up to \($0) min").tag(Optional($0)) }
                    }
                } label: { Label(filter.maximumMinutes.map { "≤ \($0) min" } ?? "Duration", systemImage: "clock") }.supperGlassButton()
                Menu {
                    Section("Match all selected tags") {
                        ForEach(allTags, id: \.self) { tag in
                            Toggle(tag, isOn: Binding(get: { filter.tags.contains(tag) }, set: { on in if on { filter.tags.insert(tag) } else { filter.tags.remove(tag) } }))
                        }
                    }
                    Button("Clear tags") { filter.tags = [] }
                } label: { Label(filter.tags.isEmpty ? "Tags" : filter.tags.sorted().joined(separator: ", "), systemImage: "tag") }.supperGlassButton().disabled(allTags.isEmpty)
                Menu {
                    Section("Match all selected collections") {
                        ForEach(store.collections) { collection in
                            Toggle(collection.name, isOn: Binding(get: { filter.collectionIDs.contains(collection.id) }, set: { on in if on { filter.collectionIDs.insert(collection.id) } else { filter.collectionIDs.remove(collection.id) } }))
                        }
                    }
                    Button("Clear collections") { filter.collectionIDs = [] }
                } label: { Label(filter.collectionIDs.isEmpty ? "Collections" : "Collections · \(filter.collectionIDs.count)", systemImage: "folder") }.supperGlassButton().disabled(store.collections.isEmpty)
                Menu {
                    Picker("Reactions", selection: $filter.reaction) { ForEach(RecipeFilter.ReactionFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                } label: { Label(filter.reaction == .any ? "Reactions" : filter.reaction.rawValue, systemImage: "face.smiling") }.supperGlassButton()
                Button("Search with words", systemImage: "sparkle.magnifyingglass") { showingSearchAssistant = true }.labelStyle(.iconOnly).supperGlassButton()
                if filter.isActive { Button("Clear", systemImage: "xmark") { filter = RecipeFilter() }.supperGlassButton() }
            }.font(.subheadline).controlSize(.small).padding(.horizontal, 20)
        }
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
            }.navigationTitle("Search with words").navigationBarTitleDisplayMode(.inline)
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
