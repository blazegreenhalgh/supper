import SwiftUI

struct RecipeCardView: View {
    let recipe: Recipe
    var transition: RecipeTransitionSource? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { RecipeImage(data: recipe.imageData) }
                .clipShape(.rect(cornerRadius: 22))
                .modifier(RecipeZoomSource(source: transition))
                .overlay(alignment: .bottomTrailing) {
                    if !recipe.reactions.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(recipe.reactions.prefix(3)) { reaction in
                                Text(reaction.emoji)
                                    .font(.caption)
                            }
                        }
                        .padding(6)
                        .supperGlassSurface()
                        .padding(8)
                    }
                }

            Text(recipe.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)

            // Reserve one caption line even for recipes saved with only a title.
            Text(" ")
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    HStack(spacing: 7) {
                        if let duration = recipe.durationMinutes {
                            Label("\(duration) min", systemImage: "clock")
                        }
                        if let firstTag = recipe.tags.first {
                            Text(firstTag)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // A horizontal lazy row can propose its first card's height to siblings.
        // Measure at the available width and natural height so covers stay square.
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
