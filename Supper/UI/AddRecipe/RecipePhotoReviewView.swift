import SwiftUI

struct RecipePhotoReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let proposal: RecipePhotoProposal
    let blocker: String?
    let apply: () -> Void
    @State private var showingOriginal = false

    private var comparisonImage: Data? { proposal.originalPhoto ?? proposal.previousImage }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if comparisonImage != nil {
                        Picker("Photo comparison", selection: $showingOriginal) {
                            Text(proposal.kind == .enhanced ? "Original" : "Current").tag(true)
                            Text(proposal.kind == .enhanced ? "Edited" : "Proposed").tag(false)
                        }.pickerStyle(.segmented).accessibilityIdentifier("photoComparison")
                    }
                    RecipeImage(data: showingOriginal ? comparisonImage : proposal.image)
                        .aspectRatio(1, contentMode: .fit).clipShape(.rect(cornerRadius: 24))
                    Text(proposal.caption).font(.headline).accessibilityIdentifier("recipePhotoCaption")
                    if let source = proposal.source {
                        Link(destination: source.url) { Label(source.title, systemImage: "link") }
                        Text("The source credit is saved in Notes with this photo.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if proposal.kind == .enhanced {
                        Text("Compare with your original to check the food details before using the edit.").font(.footnote).foregroundStyle(.secondary)
                    } else if proposal.kind == .generated {
                        Text("AI-generated artwork illustrating the dish.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let blocker { Text(blocker).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("recipePhotoBlocker") }
                    Text("Use photo updates your draft. Save the recipe to keep it.").font(.footnote).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(SupperStyle.canvas)
                .navigationTitle("Photo Preview").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() }.accessibilityIdentifier("closePhotoPreview") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use photo", action: apply).disabled(blocker != nil).accessibilityIdentifier("applyRecipePhoto")
                    }
                }
        }
    }
}
