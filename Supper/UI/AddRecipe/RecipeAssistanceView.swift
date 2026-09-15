import SwiftUI
import PhotosUI

struct RecipeAssistanceView: View {
    @Environment(\.dismiss) private var dismiss
    let onImported: (RecipeDraft) -> Void
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var result: RecipeAssistanceResult?
    @State private var progress: String?
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 200).accessibilityLabel("Recipe text")
                    PhotosPicker(selection: $photo, matching: .images) { Label("Read screenshot or cookbook photo", systemImage: "text.viewfinder") }.disabled(progress != nil)
                } header: { Text("Paste recipe text") } footer: { Text("A meal photo can be added directly in the recipe editor. Supper won't guess ingredients from its appearance.") }
                Section {
                    Text("Text recognition stays on-device. Assisted extraction sends the recipe text to OpenAI using your API key; without a key, a basic local draft is available.").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("AI settings") { AISettingsView() }
                    if let progress { ProgressView(progress); Button("Cancel processing", role: .cancel) { task?.cancel(); self.progress = nil } }
                    else { Button("Create editable draft", action: structure).disabled(text.isEmpty) }
                }
                if let result {
                    Section("Review") {
                        Text(result.notice).font(.subheadline)
                        Text(result.draft.title).font(.headline)
                        Text("\(result.draft.ingredients.count) ingredients · \(result.draft.steps.count) steps")
                        Button("Review in editor") { onImported(result.draft) }
                    }
                }
            }
            .navigationTitle("Recipe assistance").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } } }
            .onDisappear { task?.cancel() }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                task?.cancel(); result = nil; progress = "Reading text on this device…"
                task = Task {
                    defer { progress = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw SupperError.invalid("Choose the image again.") }
                        let recognized = try await OnDeviceRecipeAssistant().recognizeText(in: data)
                        try Task.checkCancellation(); text = recognized
                    } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
                }
            }
            .supperError($error, title: "Couldn't read recipe")
        }
    }
    private func structure() {
        task?.cancel(); result = nil; progress = "Extracting recipe details…"
        task = Task {
            defer { progress = nil }
            do { let value = try await CloudRecipeAssistant().structure(text); try Task.checkCancellation(); result = value }
            catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
        }
    }
}

struct GroupRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var ingredients: [Ingredient]
    let sourceURL: URL?
    @State private var proposals: [UUID: String] = [:]
    @State private var selected: Set<UUID> = []
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Review source headings before applying them. Ingredient names, quantities and units stay as edited. Ingredients move into their recovered sections.")
                    if loading { ProgressView("Reading source headings…") }
                    else { Button(loaded ? "Try again" : "Find source sections", action: recover) }
                    if loaded && proposals.isEmpty { Text("No unambiguous sections found. Add sections in the ingredient editor.").foregroundStyle(.secondary) }
                }
                ForEach(ingredients.filter { proposals[$0.id] != nil }) { item in
                    Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { on in
                        if on { selected.insert(item.id) } else { selected.remove(item.id) }
                    })) {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text("\(item.group.isEmpty ? "Main section" : item.group) → \(proposals[item.id] ?? "")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Recover sections").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") {
                    ingredients = ingredients.map { item in
                        var item = item
                        if selected.contains(item.id) { item.group = proposals[item.id] ?? item.group }
                        return item
                    }
                    dismiss()
                }.disabled(selected.isEmpty || loading) }
            }
            .onDisappear { task?.cancel() }
            .supperError($error, title: "Couldn't recover sections")
        }
    }
    private func recover() {
        guard let sourceURL else { return }
        loading = true
        task = Task {
            defer { loading = false }
            do {
                let recovered = try await RecipeImportService().importRecipe(from: sourceURL)
                try Task.checkCancellation(); proposals = GroupRecovery.suggestions(for: ingredients, recovered: recovered.ingredients)
                selected = Set(proposals.keys); loaded = true
            } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
        }
    }
}
