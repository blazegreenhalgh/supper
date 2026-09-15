import SwiftUI

/// A review of a snapshot; Apply edits only the parent draft, never saves the recipe.
struct IngredientFormattingView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var ingredients: [Ingredient]
    @State private var result: IngredientFormattingResult?
    @State private var editedChanges: [IngredientFormatChange] = []
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
                        ForEach($editedChanges) { $change in
                            Section {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Original").font(.caption).foregroundStyle(.secondary)
                                    Text(change.original.displayText).font(.callout).foregroundStyle(.secondary)
                                }
                                Toggle("Apply this change", isOn: Binding(get: { selected.contains(change.id) }, set: { on in
                                    if on { selected.insert(change.id) } else { selected.remove(change.id) }
                                }))
                                .tint(Color(uiColor: .systemBlue))
                                .accessibilityIdentifier("formatChange-" + change.id.uuidString)
                                TextField("Ingredient name", text: $change.proposed.name, axis: .vertical)
                                    .accessibilityIdentifier("formattedName-" + change.id.uuidString)
                                LabeledContent("Quantity") {
                                    TextField("Optional", text: $change.proposed.quantity)
                                        .multilineTextAlignment(.trailing)
                                        .accessibilityIdentifier("formattedQuantity-" + change.id.uuidString)
                                }
                                LabeledContent("Unit") {
                                    TextField("Optional", text: $change.proposed.unit)
                                        .multilineTextAlignment(.trailing)
                                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                                        .accessibilityIdentifier("formattedUnit-" + change.id.uuidString)
                                }
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
                        ingredients = IngredientFormatting.applying(editedChanges, selected: selected, to: ingredients)
                        dismiss()
                    }.disabled(result == nil || selected.isEmpty || editedChanges.contains { selected.contains($0.id) && $0.proposed.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).accessibilityIdentifier("applyIngredientFormatting")
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
                    editedChanges = value.changes
                    selected = Set(value.changes.filter { $0.original != $0.proposed }.map(\.id))
                } catch {
                    if !(error is CancellationError) { self.error = "\(error.localizedDescription) Cancel to keep editing, or open Auto format to try again." }
                }
            }
        }
    }
}
