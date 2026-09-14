import SwiftUI
import PhotosUI

struct AddRecipeView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = RecipeDraft()
    @State private var photoItem: PhotosPickerItem?
    @State private var showingURLImport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack {
                            if let data = draft.imageData {
                                RecipeImage(data: data)
                                    .frame(height: 220)
                                    .clipShape(.rect(cornerRadius: 18))
                            } else {
                                VStack(spacing: 10) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.largeTitle)
                                    Text("Add a photo")
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .background(.quaternary, in: .rect(cornerRadius: 18))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)

                    TextField("Recipe name", text: $draft.title)
                        .font(.title3.weight(.semibold))

                    HStack {
                        Text("Duration")
                        Spacer()
                        TextField("Minutes", value: $draft.durationMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("min")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Optional") {
                    TextField("Tags, comma separated", text: Binding(
                        get: { draft.tags.joined(separator: ", ") },
                        set: { draft.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                    ))
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button {
                        showingURLImport = true
                    } label: {
                        Label("Import from URL", systemImage: "link")
                    }
                } footer: {
                    Text("Quick Add only needs a photo and title. Everything else can be added later.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SupperStyle.canvas)
            .navigationTitle("New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        try? store.addRecipe(draft.makeRecipe())
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    draft.imageData = try? await newValue.loadTransferable(type: Data.self)
                }
            }
            .sheet(isPresented: $showingURLImport) {
                URLImportView { imported in
                    draft = imported
                    showingURLImport = false
                }
            }
        }
    }
}
