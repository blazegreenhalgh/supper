import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let recipeID: UUID
    @State private var showingIngredients = false
    @State private var showingEditor = false
    @State private var showingCollections = false
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
                        VStack(alignment: .leading, spacing: 22) {
                            Text(recipe.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                            if let duration = recipe.durationMinutes { Label("\(duration) min", systemImage: "clock").font(.subheadline).foregroundStyle(.secondary) }
                            if !recipe.tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(recipe.tags, id: \.self) { tag in
                                            Text(tag).font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 6).background(SupperStyle.subtle, in: .capsule)
                                        }
                                    }
                                }
                            }
                            servings(recipe)
                            if !recipe.ingredients.isEmpty && !recipe.steps.isEmpty {
                                Picker("Recipe section", selection: $section) {
                                    Text("Ingredients").tag("Ingredients"); Text("Method").tag("Method")
                                }.pickerStyle(.segmented)
                            }
                            if !recipe.ingredients.isEmpty && (section == "Ingredients" || recipe.steps.isEmpty) { ingredients(recipe) }
                            if !recipe.steps.isEmpty && (section == "Method" || recipe.ingredients.isEmpty) { RecipeMethodView(steps: recipe.steps) }
                            if !recipe.notes.isEmpty {
                                DisclosureGroup("Notes") { Text(recipe.notes).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 10) }.tint(.primary)
                            }
                            if let url = recipe.sourceURL {
                                Link(destination: url) { Label("Original recipe", systemImage: "safari") }.supperGlassButton()
                            }
                        }
                        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 40)
                        .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                    }
                }
                .background(SupperStyle.canvas)
                .ignoresSafeArea(.container, edges: .top)
                .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Edit") { showingEditor = true }.accessibilityIdentifier("editRecipe") }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Recipe options", systemImage: "ellipsis") {
                            Button("Collections", systemImage: "folder") { showingCollections = true }
                            if !recipe.ingredients.isEmpty { Button("Add to groceries", systemImage: "cart.badge.plus") { showingIngredients = true } }
                            if let url = recipe.sourceURL { ShareLink(item: url) }
                        }
                    }
                }
                .sheet(isPresented: $showingEditor) { AddRecipeView(recipe: recipe) }
                .sheet(isPresented: $showingIngredients) { AddIngredientsToGroceryView(recipe: recipe, servings: selectedServings ?? recipe.servings) }
                .sheet(isPresented: $showingCollections) { CollectionMembershipView(recipe: recipe) }
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
                    if group.title != "Ingredients" { Text(group.title).font(.headline).accessibilityAddTraits(.isHeader) }
                    LazyVStack(spacing: 0) {
                        ForEach(group.ingredients) { ingredient in
                            IngredientLabel(ingredient: ingredient).padding(.horizontal, 14).padding(.vertical, 5)
                            if ingredient.id != group.ingredients.last?.id { Divider().padding(.leading, 51) }
                        }
                    }.background(SupperStyle.surface, in: .rect(cornerRadius: 20))
                }
            }
            Button { showingIngredients = true } label: { Label("Add to groceries", systemImage: "cart.badge.plus").frame(maxWidth: .infinity) }
                .supperGlassButton(prominent: true).controlSize(.large)
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
    @State private var selectedStep = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentIndex: Int { min(selectedStep, max(steps.count - 1, 0)) }

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Method")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(steps.count) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 18) {
                    Text("Step \(currentIndex + 1) of \(steps.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(currentIndex + 1), total: Double(steps.count))
                        .accessibilityLabel("Recipe step")
                    Text(steps[currentIndex].text)
                        .font(.title3)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(22)
                .background(SupperStyle.surface, in: .rect(cornerRadius: 24))

                SupperGlassGroup {
                    HStack {
                        Button("Previous", systemImage: "chevron.left") { moveStep(by: -1) }
                            .supperGlassButton()
                            .disabled(currentIndex == 0)
                        Spacer(minLength: 12)
                        Button("Next", systemImage: "chevron.right") { moveStep(by: 1) }
                            .supperGlassButton(prominent: true)
                            .disabled(currentIndex == steps.count - 1)
                    }
                    .controlSize(.large)
                }

                DisclosureGroup("All steps") {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Step \(index + 1)")
                                    .font(.subheadline.weight(.semibold))
                                Text(step.text)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 12)
                }
                .tint(.primary)
            }
        }
    }

    private func moveStep(by offset: Int) {
        withAnimation(reduceMotion ? nil : .snappy) {
            selectedStep = min(max(currentIndex + offset, 0), steps.count - 1)
        }
    }
}
