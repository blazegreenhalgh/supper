import SwiftUI

struct URLImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    let onImported: (RecipeDraft) -> Void
    private let importer = RecipeImportService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Recipe URL")
                } footer: {
                    Text("Supper reads structured recipe data from the page and turns it into a clean recipe.")
                }

                Section {
                    Button {
                        importRecipe()
                    } label: {
                        HStack {
                            if isImporting { ProgressView() }
                            Text(isImporting ? "Importing…" : "Import Recipe")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(parsedURL == nil || isImporting)
                }
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Couldn't import recipe", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var parsedURL: URL? {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func importRecipe() {
        guard let url = parsedURL else { return }
        isImporting = true
        Task {
            do {
                let draft = try await importer.importRecipe(from: url)
                await MainActor.run {
                    isImporting = false
                    onImported(draft)
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
