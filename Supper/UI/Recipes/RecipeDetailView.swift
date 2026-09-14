import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject private var store: RecipeStore
    let recipeID: UUID
    @State private var showingIngredients = false
    @State private var selectedSection: DetailSection = .ingredients

    private enum DetailSection: String, CaseIterable {
        case ingredients = "Ingredients"
        case method = "Method"
    }

    private var recipe: Recipe? { store.recipes.first { $0.id == recipeID } }

    var body: some View {
        Group {
            if let recipe {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(recipe)
                        ReactionRow(recipe: recipe)

                        if !recipe.ingredients.isEmpty && !recipe.steps.isEmpty {
                            Picker("Recipe section", selection: $selectedSection) {
                                ForEach(DetailSection.allCases, id: \.self) { section in
                                    Text(section.rawValue).tag(section)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if !recipe.ingredients.isEmpty && (selectedSection == .ingredients || recipe.steps.isEmpty) {
                            ingredients(recipe)
                        }
                        if !recipe.steps.isEmpty && (selectedSection == .method || recipe.ingredients.isEmpty) {
                            RecipeMethodView(steps: recipe.steps)
                        }

                        if !recipe.notes.isEmpty {
                            DisclosureGroup {
                                Text(recipe.notes)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 10)
                                    .textSelection(.enabled)
                            } label: {
                                Label("Notes", systemImage: "note.text")
                                    .font(.headline)
                            }
                            .tint(.primary)
                        }

                        if let url = recipe.sourceURL {
                            Link(destination: url) {
                                Label("Open original recipe", systemImage: "safari")
                                    .frame(maxWidth: .infinity)
                            }
                            .supperGlassButton()
                            .controlSize(.large)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .background(SupperStyle.canvas)
                .navigationTitle("Recipe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let url = recipe.sourceURL {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: url)
                        }
                    }
                    if !recipe.ingredients.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Add to groceries", systemImage: "cart.badge.plus") {
                                showingIngredients = true
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingIngredients) {
                    AddIngredientsToGroceryView(recipe: recipe)
                }
            } else {
                ContentUnavailableView("Recipe unavailable", systemImage: "fork.knife")
            }
        }
    }

    private func header(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { RecipeImage(data: recipe.imageData) }
                .clipShape(.rect(cornerRadius: 28))

            Text(recipe.title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { metadata(recipe) }
                VStack(alignment: .leading, spacing: 10) { metadata(recipe) }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)

            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recipe.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(SupperStyle.subtle, in: .capsule)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metadata(_ recipe: Recipe) -> some View {
        if let duration = recipe.durationMinutes {
            Label("\(duration) min", systemImage: "clock")
        }
        if let servings = recipe.servings {
            Label("\(servings) servings", systemImage: "person.2")
        }
    }

    private func ingredients(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingredients")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(recipe.ingredients.count) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(recipe.ingredients) { ingredient in
                    IngredientLabel(ingredient: ingredient)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    if ingredient.id != recipe.ingredients.last?.id {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .background(SupperStyle.surface, in: .rect(cornerRadius: 24))

            Button {
                showingIngredients = true
            } label: {
                Label("Add to groceries", systemImage: "cart.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .supperGlassButton(prominent: true)
            .controlSize(.large)
        }
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

private struct ReactionRow: View {
    @EnvironmentObject private var store: RecipeStore
    let recipe: Recipe
    private let personID = "me"
    private let reactions = ["❤️", "😍", "👍", "😐", "👎"]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your reaction").font(.headline)
                if !recipe.reactions.isEmpty {
                    Text(recipe.reactions.map(\.emoji).joined(separator: " "))
                        .font(.subheadline)
                }
            }
            Spacer()
            Menu {
                ForEach(reactions, id: \.self) { emoji in
                    Button(emoji) { saveReaction(emoji) }
                }
                if recipe.reactions.contains(where: { $0.personID == personID }) {
                    Divider()
                    Button("Remove", role: .destructive) { saveReaction(nil) }
                }
            } label: {
                Text(recipe.reactions.first(where: { $0.personID == personID })?.emoji ?? "React")
                    .font(.body.weight(.medium))
            }
            .supperGlassButton()
            .controlSize(.large)
            .accessibilityLabel("Change your reaction")
        }
    }

    private func saveReaction(_ emoji: String?) {
        do { try store.setReaction(emoji, for: recipe, personID: personID) }
        catch { store.errorMessage = error.localizedDescription }
    }
}
