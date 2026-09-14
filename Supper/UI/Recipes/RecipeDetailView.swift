import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recipeID: UUID
    @State private var showingIngredients = false
    @State private var showingEditor = false
    @State private var showingCollections = false
    @State private var showingTags = false
    @State private var selectedServings: Int?
    @State private var section = "Ingredients"
    @State private var byShoppingCategory = false
    private var recipe: Recipe? { store.recipes.first { $0.id == recipeID } }

    var body: some View {
        Group {
            if let recipe {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(recipe)
                        VStack(alignment: .leading, spacing: 26) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(recipe.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                                HStack(spacing: 20) {
                                    if let duration = recipe.durationMinutes {
                                        Label("\(duration) min", systemImage: "clock").foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Button { showingTags = true } label: {
                                        Label(recipe.tags.isEmpty ? "Add tags" : "Tags · \(recipe.tags.count)", systemImage: "tag")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("recipeTags")
                                }.font(.subheadline)
                            }
                            servings(recipe)
                            if !recipe.ingredients.isEmpty && !recipe.steps.isEmpty {
                                Picker("Recipe section", selection: $section) {
                                    Text("Ingredients").tag("Ingredients"); Text("Method").tag("Method")
                                }.pickerStyle(.segmented)
                            }
                            if !recipe.ingredients.isEmpty && (section == "Ingredients" || recipe.steps.isEmpty) { ingredients(recipe) }
                            if !recipe.steps.isEmpty && (section == "Method" || recipe.ingredients.isEmpty) { RecipeMethodView(steps: recipe.steps, ingredients: recipe.ingredients, baseServings: recipe.servings, selectedServings: selectedServings) }
                            if !recipe.notes.isEmpty {
                                DisclosureGroup("Notes") { Text(recipe.notes).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 10) }.tint(.primary)
                            }
                            if !recipe.ingredients.isEmpty {
                                Button { showingIngredients = true } label: {
                                    Label("Add to groceries", systemImage: "cart.badge.plus").frame(maxWidth: .infinity)
                                }.supperGlassButton(prominent: true).controlSize(.large)
                            }
                            if let url = recipe.sourceURL {
                                Link("Original recipe", destination: url)
                                    .font(.subheadline).buttonStyle(.plain).foregroundStyle(.tint)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 6)
                            }
                        }
                        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 40)
                        .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                    }
                }
                .background(SupperStyle.canvas)
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: section)
                .ignoresSafeArea(.container, edges: .top)
                .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Edit") { showingEditor = true }.accessibilityIdentifier("editRecipe") }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Recipe options", systemImage: "ellipsis") {
                            Button("Collections", systemImage: "folder") { showingCollections = true }
                            if !recipe.ingredients.isEmpty {
                                Button("Add to groceries", systemImage: "cart.badge.plus") { showingIngredients = true }
                                    .accessibilityIdentifier("recipeMenuAddToGroceries")
                            }
                            if let url = recipe.sourceURL { ShareLink(item: url) }
                        }
                    }
                }
                .sheet(isPresented: $showingEditor) { AddRecipeView(recipe: recipe) }
                .sheet(isPresented: $showingIngredients) { AddIngredientsToGroceryView(recipe: recipe, servings: selectedServings ?? recipe.servings) }
                .sheet(isPresented: $showingCollections) { CollectionMembershipView(recipe: recipe) }
                .sheet(isPresented: $showingTags) { RecipeTagsSheet(recipe: recipe).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
                .onAppear { if selectedServings == nil { selectedServings = recipe.servings } }
                .onChange(of: recipe.servings) { _, value in selectedServings = value }
            } else { ContentUnavailableView("Recipe unavailable", systemImage: "fork.knife") }
        }
    }
    private func hero(_ recipe: Recipe) -> some View {
        Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay { RecipeImage(data: recipe.imageData) }
            .overlay(alignment: .bottom) {
                if !reduceTransparency {
                    LinearGradient(colors: [SupperStyle.canvas.opacity(0), SupperStyle.canvas], startPoint: .top, endPoint: .bottom)
                        .frame(height: 85).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) { RecipeReactionControl(recipe: recipe).padding(.trailing, 20).padding(.bottom, 40) }
            .accessibilityIdentifier("recipeHero")
    }
    @ViewBuilder private func servings(_ recipe: Recipe) -> some View {
        if let base = recipe.servings, base > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: Binding(get: { selectedServings ?? base }, set: { selectedServings = $0 }), in: 1...100) {
                    Label("\(selectedServings ?? base) servings", systemImage: "person.2")
                }
                if (selectedServings ?? base) != base {
                    Button("Reset to recipe’s \(base) servings") { selectedServings = base }.font(.caption)
                }
            }
        } else {
            Button("Set base servings", systemImage: "person.2.badge.plus") { showingEditor = true }.supperGlassButton()
        }
    }
    private func ingredients(_ recipe: Recipe) -> some View {
        let scaled = recipe.ingredients.map { $0.scaled(from: recipe.servings, to: selectedServings) }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Ingredients").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Menu {
                    Picker("Group ingredients by", selection: $byShoppingCategory) {
                        Text("Recipe groups").tag(false); Text("Shopping categories").tag(true)
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("Ingredient grouping")
            }
            ForEach(IngredientSection.sections(scaled, byShoppingCategory: byShoppingCategory)) { group in
                VStack(alignment: .leading, spacing: 8) {
                    if group.title != "Ingredients" { Text(group.title).font(.subheadline.weight(.semibold)).textCase(.uppercase).padding(.top, 12).accessibilityAddTraits(.isHeader) }
                    LazyVStack(spacing: 4) {
                        ForEach(group.ingredients) { ingredient in
                            IngredientLabel(ingredient: ingredient)
                        }
                    }
                }
            }
        }
    }
}

struct RecipeReactionControl: View {
    @EnvironmentObject private var store: RecipeStore
    let recipe: Recipe
    private var own: RecipeReaction? { recipe.reactions.first { ReactionIdentity.canonical($0.personID, members: store.members) == store.currentMemberID } }
    var body: some View {
        Menu {
            Section("Your reaction") {
                ForEach(["❤️", "😍", "👍", "😐", "👎"], id: \.self) { emoji in
                    Button { react(own?.emoji == emoji ? nil : emoji) } label: {
                        if own?.emoji == emoji { Label(emoji, systemImage: "checkmark") } else { Text(emoji) }
                    }
                }
                if own != nil { Button("Remove my reaction", role: .destructive) { react(nil) } }
            }
            if !recipe.reactions.isEmpty {
                Section("Household reactions") {
                    ForEach(recipe.reactions) { reaction in Text("\(reaction.emoji)  \(store.memberName(reaction.personID))") }
                }
            }
        } label: {
            if recipe.reactions.isEmpty { Image(systemName: "face.smiling").font(.subheadline).padding(3) }
            else {
                HStack(spacing: 3) {
                    ForEach(recipe.reactions.prefix(3)) { Text($0.emoji).font(.subheadline) }
                    if recipe.reactions.count > 3 { Text("+\(recipe.reactions.count - 3)").font(.caption) }
                }.padding(3)
            }
        }
        .supperGlassButton().controlSize(.small)
        .accessibilityLabel("Household reactions").accessibilityValue(own.map { "Your reaction: \($0.emoji)" } ?? "Add your reaction")
    }
    private func react(_ emoji: String?) {
        do { try store.setReaction(emoji, for: recipe) } catch { store.errorMessage = error.localizedDescription }
    }
}
private struct RecipeMethodView: View {
    let steps: [RecipeStep]
    let ingredients: [Ingredient]
    let baseServings: Int?
    let selectedServings: Int?
    @State private var ingredientMatches: StepIngredientMatches?
    @State private var selectedStep = 0
    @State private var showingFullScreen = false
    @State private var showingAllSteps = true

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack { heading; Spacer(minLength: 16); stepByStepButton }
                    VStack(alignment: .leading, spacing: 12) { heading; stepByStepButton }
                }
                DisclosureGroup("All steps", isExpanded: $showingAllSteps) {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Step \(index + 1)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .accessibilityAddTraits(.isHeader)
                                Text(step.text)
                                    .font(.callout).foregroundStyle(.primary)
                                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 16)
                }.font(.subheadline)
            }
            .fullScreenCover(isPresented: $showingFullScreen) {
                FullScreenMethodView(steps: steps, ingredients: ingredients, baseServings: baseServings, selectedServings: selectedServings, selectedStep: $selectedStep, matches: $ingredientMatches)
            }
        }
    }
    private var heading: some View {
        Text("Method").font(.title2.bold()).accessibilityAddTraits(.isHeader)
    }
    private var stepByStepButton: some View {
        Button("Step by step", systemImage: "arrow.up.left.and.arrow.down.right") { showingFullScreen = true }
            .font(.subheadline).accessibilityIdentifier("fullScreenMethod")
    }
}

private struct FullScreenMethodView: View {
    @Environment(\.dismiss) private var dismiss
    let steps: [RecipeStep]
    let ingredients: [Ingredient]
    let baseServings: Int?
    let selectedServings: Int?
    @Binding var selectedStep: Int
    @Binding var matches: StepIngredientMatches?
    @State private var isMatching = false
    @State private var retry = 0
    private struct MatchingRequest: Hashable { let input: StepIngredientInput; let retry: Int }
    private var input: StepIngredientInput { StepIngredientInput(ingredients: ingredients, steps: steps) }
    private var displayedMatches: StepIngredientMatches {
        if let matches, matches.input == input { return matches }
        return StepIngredientMatching.explicitMatches(input)
    }
    private var currentIndex: Int { min(max(selectedStep, 0), max(steps.count - 1, 0)) }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 24) {
                        Color.clear.frame(height: 0).id("stepTop")
                        ProgressView(value: Double(currentIndex + 1), total: Double(steps.count))
                            .accessibilityLabel("Recipe step")
                        Text(steps[currentIndex].text)
                            .font(.title2).lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("fullScreenStepText")
                        if !ingredients.isEmpty { stepIngredients }
                    }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
            }
            .onChange(of: currentIndex) { _, _ in proxy.scrollTo("stepTop", anchor: .top) }
            }
            .task(id: MatchingRequest(input: input, retry: retry)) { await matchIngredients(force: retry > 0) }
            .background(SupperStyle.canvas)
            .navigationTitle("Step \(currentIndex + 1) of \(steps.count)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeFullScreenMethod")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Previous", systemImage: "chevron.left") { selectedStep = currentIndex - 1 }
                        .supperGlassButton().disabled(currentIndex == 0)
                        .accessibilityIdentifier("previousFullScreenStep")
                    Spacer(minLength: 12)
                    Button("Next", systemImage: "chevron.right") { selectedStep = currentIndex + 1 }
                        .supperGlassButton(prominent: true).disabled(currentIndex >= steps.count - 1)
                        .accessibilityIdentifier("nextFullScreenStep")
                }.controlSize(.large).padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                    .background(SupperStyle.canvas)
            }
        }
    }
    private var stepIngredients: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("For this step").font(.headline).accessibilityAddTraits(.isHeader)
            if isMatching {
                ProgressView("Matching ingredients on device…").font(.caption)
            }
            let relevant = displayedMatches.ingredients(for: steps[currentIndex].id,
                baseServings: baseServings, selectedServings: selectedServings)
            if relevant.isEmpty {
                Text("No ingredients identified for this step.").font(.callout).foregroundStyle(.secondary)
            } else {
                ingredientRows(relevant, prefix: "stepIngredient")
            }
            Text(amountsNote).font(.caption).foregroundStyle(.secondary)
            if !isMatching, let notice = displayedMatches.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
                Button("Retry matching") { retry += 1 }.font(.caption).disabled(isMatching)
            }
            DisclosureGroup("All ingredients") {
                ingredientRows(ingredients.map { $0.scaled(from: baseServings, to: selectedServings) }, prefix: "allIngredient")
            }.font(.subheadline).padding(.top, 8)
        }
    }
    private var amountsNote: String {
        if let baseServings, baseServings > 0, let selectedServings, selectedServings > 0 {
            return "Recipe amounts for \(selectedServings) servings. Follow any split amounts in the step."
        }
        return "Recipe amounts. Follow any split amounts in the step."
    }
    private func ingredientRows(_ items: [Ingredient], prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(IngredientSection.sections(items, byShoppingCategory: false)) { section in
                if section.title != "Ingredients" {
                    Text(section.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                }
                ForEach(section.ingredients) { ingredient in
                    IngredientLabel(ingredient: ingredient)
                        .accessibilityIdentifier("\(prefix)-\(ingredient.name)")
                }
            }
        }
    }
    @MainActor private func matchIngredients(force: Bool = false) async {
        guard !ingredients.isEmpty, force || matches?.input != input else { return }
        isMatching = true
        defer { isMatching = false }
        do {
            let result = try await OnDeviceRecipeAssistant().ingredientsByStep(input)
            try Task.checkCancellation()
            matches = result
        } catch { /* Closing the sheet cancels assistance without changing the recipe. */ }
    }

}
