import SwiftUI

/// A review of a snapshot; Apply edits only the parent draft, never saves the recipe.
struct IngredientFormattingView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var ingredients: [Ingredient]
    @State private var result: IngredientFormattingResult?
    @State private var selected: Set<UUID> = []
    @State private var completed = 0
    @State private var total = 0
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    List {
                        Section {
                            Text(result.notice).font(.footnote).foregroundStyle(.secondary)
                        }
                        if result.changes.isEmpty {
                            Text("Your ingredients are already formatted.").foregroundStyle(.secondary)
                        }
                        ForEach(result.changes) { change in
                            Section {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Original").font(.caption).foregroundStyle(.secondary)
                                    Text(change.original.displayText).font(.callout).foregroundStyle(.secondary)
                                }
                                Toggle(isOn: Binding(get: { selected.contains(change.id) }, set: { on in
                                    if on { selected.insert(change.id) } else { selected.remove(change.id) }
                                })) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Formatted").font(.caption).foregroundStyle(.secondary)
                                        IngredientLabel(ingredient: change.proposed)
                                    }
                                }
                                .accessibilityIdentifier("formatChange-" + change.id.uuidString)
                            } footer: {
                                if let notice = change.notice { Text(notice) }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                } else if let error {
                    ContentUnavailableView("Couldn't format ingredients", systemImage: "sparkles", description: Text(error))
                } else {
                    VStack(spacing: 16) {
                        ProgressView("Formatting ingredients…")
                        if total > 0 { Text("\(completed) of \(total)").font(.footnote).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(SupperStyle.canvas)
            .navigationTitle("Review Formatting").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let result else { return }
                        ingredients = IngredientFormatting.applying(result.changes, selected: selected, to: ingredients)
                        dismiss()
                    }.disabled(result == nil || selected.isEmpty).accessibilityIdentifier("applyIngredientFormatting")
                }
            }
            // SwiftUI cancels this task if the sheet is dismissed, including a swipe down.
            .task {
                do {
                    let value = try await OnDeviceRecipeAssistant().formatIngredients(ingredients) { count, total in
                        completed = count; self.total = total
                    }
                    try Task.checkCancellation()
                    result = value
                    selected = Set(value.changes.filter { $0.original != $0.proposed }.map(\.id))
                } catch {
                    if !(error is CancellationError) { self.error = "\(error.localizedDescription) Cancel to keep editing, or open Auto format to try again." }
                }
            }
        }
    }
}
