import SwiftUI
import PhotosUI

struct RecipeCoverView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: RecipeDraft
    var initialMode: RecipePhotoKind = .generated
    var initialRequest: String = ""
    @ObservedObject private var settings = OpenAISettings.shared
    @State private var mode: RecipePhotoKind = .generated
    @State private var request = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var uploadedPhoto: Data?
    @State private var loadingPhoto = false
    @State private var photos: [RecipePhotoProposal] = []
    @State private var reviewing: RecipePhotoProposal?
    @State private var busy = false
    @State private var startedAt = Date()
    @State private var progress = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var photoTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var initialized = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Photo option", selection: $mode) {
                        ForEach(RecipePhotoKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("coverMode")
                    if mode == .enhanced { photoUpload }
                    TextField(mode == .online ? "Dish, style or a photo/page link" : "Style preferences (optional)", text: $request, axis: .vertical)
                        .lineLimit(2...4).accessibilityIdentifier("coverRequest")
                } header: { Text(draft.title.isEmpty ? "Recipe photo" : draft.title) } footer: {
                    Text(mode == .enhanced ? "Polish the lighting, colour and framing of your food photo. The selected image is sent to OpenAI for editing; compare the result with the original before using it." :
                         mode == .online ? "Find real photos on published recipe pages, or paste a public photo link. Source credits are kept with your recipe." :
                         "Create an editorial cover from your recipe title and ingredients. This produces an AI illustration of the dish.")
                }
                Section {
                    if busy {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 4) {
                                Text(progress)
                                if mode != .online {
                                    Text("This can take a few minutes.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 4) {
                                    Text("Elapsed")
                                    Text(startedAt, style: .timer).monospacedDigit()
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("recipePhotoProgress")
                        Button("Stop", role: .cancel, action: stop)
                    } else if settings.isConfigured {
                        Button(actionTitle, systemImage: mode == .online ? "photo.on.rectangle.angled" : "sparkles", action: prepare)
                            .disabled(loadingPhoto || request.count > 1200 || (mode == .enhanced && uploadedPhoto == nil && draft.imageData == nil) ||
                                      (mode != .enhanced && draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && request.isEmpty))
                            .accessibilityIdentifier("prepareRecipePhoto")
                    } else { NavigationLink("Set up OpenAI") { AISettingsView() } }
                } footer: { Text("Uses your OpenAI API key with separate API charges. Nothing replaces your recipe photo until you choose Use photo.") }
                if !photos.isEmpty {
                    Section("Choose a photo") {
                        ForEach(photos) { photo in
                            Button { reviewing = photo } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    RecipeImage(data: photo.image).frame(height: 210).clipShape(.rect(cornerRadius: 18))
                                    Text(photo.caption).font(.subheadline)
                                    Label("Preview photo", systemImage: "eye").font(.caption)
                                }.padding(.vertical, 6)
                            }.buttonStyle(.plain).accessibilityIdentifier("previewCoverPhoto")
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(SupperStyle.canvas)
                .navigationTitle("Recipe cover").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { stop(); dismiss() } } }
                .onAppear { if !initialized { mode = initialMode; request = initialRequest; initialized = true } }
                .onDisappear { stop(); photoTask?.cancel() }
                .onChange(of: mode) { _, _ in stop(); photos = []; error = nil }
                .onChange(of: photoItem) { _, item in loadPhoto(item) }
                .sheet(item: $reviewing) { photo in
                    RecipePhotoReviewView(proposal: photo, blocker: draft.imageData == photo.previousImage ? nil : "The recipe photo has changed. Prepare another photo before applying.") {
                        do { draft = try photo.applying(to: draft); reviewing = nil; dismiss() }
                        catch { self.error = error.localizedDescription; reviewing = nil }
                    }
                }
                .supperError($error, title: "Couldn’t prepare photo")
        }
    }

    @ViewBuilder private var photoUpload: some View {
        if let image = uploadedPhoto ?? draft.imageData {
            RecipeImage(data: image).frame(height: 180).clipShape(.rect(cornerRadius: 18))
            Text(uploadedPhoto == nil ? "Using the current recipe photo" : "Using your uploaded photo").font(.caption).foregroundStyle(.secondary)
        }
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label(uploadedPhoto == nil ? "Upload a food photo" : "Choose another photo", systemImage: "photo.badge.plus")
        }.disabled(busy).accessibilityIdentifier("uploadFoodPhoto")
        if loadingPhoto { ProgressView("Loading photo…") }
    }

    private var actionTitle: String { mode == .online ? "Find photos online" : mode == .generated ? "Generate cover" : "Polish this photo" }
    private func stop() { requestID = UUID(); task?.cancel(); task = nil; busy = false }
    private func loadPhoto(_ item: PhotosPickerItem?) {
        photoTask?.cancel(); stop(); photos = []; uploadedPhoto = nil; loadingPhoto = item != nil
        photoTask = Task {
            defer { if !Task.isCancelled { loadingPhoto = false } }
            do {
                guard let item, let data = try await item.loadTransferable(type: Data.self) else { return }
                try Task.checkCancellation()
                uploadedPhoto = try RecipePhotoImage.jpeg(data)
            } catch { if !Task.isCancelled { self.error = "Couldn’t load this photo. Choose it again." } }
        }
    }
    private func prepare() {
        guard !busy else { return }
        let snapshot = draft; let selectedMode = mode; let original = uploadedPhoto; let preferences = request
        busy = true; error = nil; photos = []; startedAt = Date(); progress = "Preparing your request…"
        let id = UUID(); requestID = id
        task = Task {
            defer { if requestID == id { busy = false; task = nil } }
            do {
                let result = try await RecipePhotoService().prepare(kind: selectedMode, draft: snapshot, request: preferences, originalPhoto: original) { status in
                    guard requestID == id else { return }; progress = status
                }
                try Task.checkCancellation()
                guard requestID == id else { return }
                photos = result
                if selectedMode != .online { reviewing = result.first }
            } catch { if requestID == id, !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
