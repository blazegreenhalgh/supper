import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject private var store: RecipeStore
    let recipeID: UUID
    @State private var showingIngredients = false

    private var recipe: Recipe? { store.recipes.first { $0.id == recipeID } }

    var body: some View {
        Group {
            if let recipe {
                ScrollView {
                    VStack(spacing: 0) {
                        RecipeImage(data: recipe.imageData)
                            .frame(height: 390)
                            .overlay(alignment: .bottom) {
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.56)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 180)
                            }
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(recipe.title)
                                        .font(.largeTitle.bold())
                                        .foregroundStyle(.white)
                                        .fixedSize(horizontal: false, vertical: true)

                                    HStack(spacing: 12) {
                                        if let duration = recipe.durationMinutes {
                                            Label("\(duration) min", systemImage: "clock")
                                        }
                                        if let servings = recipe.servings {
                                            Label("\(servings)", systemImage: "person.2")
                                        }
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                }
                                .padding(20)
                            }

                        VStack(alignment: .leading, spacing: 26) {
                            if !recipe.tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(recipe.tags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.subheadline.weight(.medium))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(.thinMaterial, in: .capsule)
                                        }
                                    }
                                }
                            }

                            ReactionRow(recipe: recipe)

                            if !recipe.ingredients.isEmpty {
                                RecipeSection(title: "Ingredients") {
                                    VStack(alignment: .leading, spacing: 13) {
                                        ForEach(recipe.ingredients) { ingredient in
                                            Text(ingredient.displayText)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }

                            if !recipe.steps.isEmpty {
                                RecipeSection(title: "Method") {
                                    VStack(alignment: .leading, spacing: 20) {
                                        ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                                            HStack(alignment: .top, spacing: 14) {
                                                Text("\(index + 1)")
                                                    .font(.caption.bold())
                                                    .frame(width: 26, height: 26)
                                                    .background(.thinMaterial, in: .circle)
                                                Text(step.text)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                            }

                            if !recipe.notes.isEmpty {
                                RecipeSection(title: "Notes") {
                                    Text(recipe.notes)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let url = recipe.sourceURL {
                                Link(destination: url) {
                                    Label("Open original recipe", systemImage: "safari")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(20)
                        .background(.regularMaterial)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .toolbar {
                    if !recipe.ingredients.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showingIngredients = true } label: {
                                Image(systemName: "cart.badge.plus")
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
}

private struct RecipeSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())
            content
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
            Text("Your reaction")
                .font(.headline)
            Spacer()
            Menu {
                ForEach(reactions, id: \.self) { emoji in
                    Button(emoji) { try? store.setReaction(emoji, for: recipe, personID: personID) }
                }
                if recipe.reactions.contains(where: { $0.personID == personID }) {
                    Divider()
                    Button("Remove", role: .destructive) {
                        try? store.setReaction(nil, for: recipe, personID: personID)
                    }
                }
            } label: {
                Text(recipe.reactions.first(where: { $0.personID == personID })?.emoji ?? "Add")
                    .font(.title3)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: .capsule)
            }
        }
    }
}
