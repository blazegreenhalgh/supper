import SwiftUI

/// A read-only recipe page. Its proposal is a snapshot, so an incoming chat
/// response cannot change what the user is reviewing or what Apply targets.
struct RecipeAssistantReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let proposal: RecipeAssistantProposal
    let blocker: String?
    let apply: () -> Void
    @State private var showChanges = true

    private var changes: [RecipeAssistantChange] { proposal.changes }
    private var recipe: RecipeDraft { (try? proposal.applying(to: proposal.base)) ?? proposal.suggested }
    private var removedIngredients: [RecipeAssistantChange] {
        changes.filter { $0.kind == .removed && $0.label == "Ingredient" }
    }
    private var removedSteps: [RecipeAssistantChange] {
        changes.filter { $0.kind == .removed && $0.label == "Method" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Preview mode", selection: $showChanges) {
                        Text("Changes").tag(true)
                        Text("Recipe").tag(false)
                    }.pickerStyle(.segmented).accessibilityIdentifier("recipeAIPreviewMode")
                    if showChanges { summary }
                    if let image = recipe.imageData {
                        RecipeImage(data: image).frame(height: 200).clipShape(.rect(cornerRadius: 20))
                    }
                    recipeHeading
                    ingredients
                    method
                    if !recipe.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            heading("Notes")
                            Text(recipe.notes).font(.callout).textSelection(.enabled)
                        }
                    }
                    if !proposal.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            heading("Online sources")
                            ForEach(proposal.sources) { source in
                                Link(destination: source.url) { Label(source.title, systemImage: "link") }
                            }
                        }
                    }
                    Text("This is a preview. Apply updates your draft; Save in the recipe editor keeps it. Source links will be added to Notes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(SupperStyle.canvas)
            .accessibilityIdentifier("recipeAIPreview")
            .navigationTitle("Recipe Preview").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }.accessibilityIdentifier("closeRecipeAIPreview")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: apply).disabled(blocker != nil)
                        .accessibilityIdentifier("applyRecipeAIPreview")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let blocker {
                    Text(blocker).font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                        .background(.regularMaterial).accessibilityIdentifier("recipeAIPreviewBlocker")
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested changes").font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { counts }
                VStack(alignment: .leading, spacing: 8) { counts }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(SupperStyle.surface, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder private var counts: some View {
        ForEach([RecipeAssistantChange.Kind.added, .changed, .removed], id: \.rawValue) { kind in
            badge(kind, title: "\(changes.filter { $0.kind == kind }.count) \(kind.rawValue.lowercased())")
        }
    }

    private var recipeHeading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            if let duration = recipe.durationMinutes { Label("\(duration) min", systemImage: "clock").font(.subheadline) }
            if let servings = recipe.servings { Label("\(servings) servings", systemImage: "person.2").font(.subheadline) }
            if !recipe.tags.isEmpty { Text(recipe.tags.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) }
            if showChanges {
                ForEach(changes.filter { ["Title", "Servings", "Duration (min)"].contains($0.id) }) { change in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(change.label).font(.caption.weight(.semibold))
                        comparison(change)
                    }
                }
            }
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Ingredients")
            if recipe.ingredients.isEmpty { Text("No ingredients yet").foregroundStyle(.secondary) }
            ForEach(IngredientSection.sections(recipe.ingredients, byShoppingCategory: false)) { group in
                if group.title != "Ingredients" { Text(group.title).font(.subheadline.weight(.semibold)).padding(.top, 8) }
                ForEach(group.ingredients) { ingredient in
                    VStack(alignment: .leading, spacing: 6) {
                        IngredientLabel(ingredient: ingredient)
                        if showChanges, let change = changes.first(where: { $0.id == ingredient.id.uuidString }) {
                            comparison(change, includesAfter: false)
                        }
                    }
                    Divider()
                }
            }
            if showChanges, !removedIngredients.isEmpty {
                Text("Removed ingredients").font(.headline).padding(.top, 8)
                ForEach(removedIngredients) { comparison($0) }
            }
        }
    }

    private var method: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Method")
            if recipe.steps.isEmpty { Text("No method yet").foregroundStyle(.secondary) }
            ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                VStack(alignment: .leading, spacing: 8) {
                    Text(step.group.isEmpty ? "Step \(index + 1)" : "\(step.group) · Step \(index + 1)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text(step.text).lineSpacing(4).textSelection(.enabled)
                    if showChanges, let change = changes.first(where: { $0.id == step.id.uuidString }) {
                        comparison(change, includesAfter: false)
                    }
                }
                Divider()
            }
            if showChanges, !removedSteps.isEmpty {
                Text("Removed steps").font(.headline).padding(.top, 8)
                ForEach(removedSteps) { comparison($0) }
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.title2.bold()).accessibilityAddTraits(.isHeader)
    }

    private func comparison(_ change: RecipeAssistantChange, includesAfter: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            badge(change.kind)
            if let before = change.before {
                Text(before).strikethrough().foregroundStyle(.secondary)
                    .accessibilityLabel("\(change.kind == .removed ? "Removed" : "Previously"): \(before)")
            }
            if includesAfter, let after = change.after { Text(after) }
        }.font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(SupperStyle.surface, in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recipeAIChange-\(change.id)")
    }

    private func badge(_ kind: RecipeAssistantChange.Kind, title: String? = nil) -> some View {
        let symbol = kind == .added ? "plus.circle" : (kind == .removed ? "minus.circle" : "pencil.circle")
        let color: Color = kind == .added ? .green : (kind == .removed ? .red : .blue)
        return Label(title ?? kind.rawValue, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(color)
    }
}
