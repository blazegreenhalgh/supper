import SwiftUI

struct RecipeChatMessage: Identifiable {
    let id = UUID()
    let text: String
    var isUser = false
    var sources: [RecipeAssistantSource] = []
    var assumptions: [String] = []
}

/// Owned by the editor, so dismissing and reopening the chat retains its review,
/// conversation and undo stack for the lifetime of this unsaved recipe draft.
@MainActor final class RecipeChatSession: ObservableObject {
    @Published var input = ""
    @Published private(set) var messages: [RecipeChatMessage] = []
    @Published private(set) var pending: RecipeAssistantProposal?
    @Published private(set) var pendingCollections: RecipeCollectionProposal?
    @Published private(set) var photos: [RecipePhotoProposal] = []
    @Published private(set) var choosingPhoto = false
    @Published private(set) var needsPhotoUpload = false
    @Published private(set) var undoStack: [RecipeAssistantUndo] = []
    @Published private(set) var busy = false
    @Published private(set) var progress = ""
    @Published private(set) var error: String?
    @Published private(set) var retryRequest: String?
    @Published var editingField: String?
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var activeRequest = ""
    var photoPreferences: String { choosingPhoto || needsPhotoUpload ? activeRequest : "" }

    func applyBlocker(for proposal: RecipeAssistantProposal, draft: RecipeDraft) -> String? {
        if busy { return "Wait for the current request to finish." }
        if pending?.id != proposal.id { return "A newer suggestion is available. Reopen the preview to review it." }
        if let editingField { return "Finish your \(editingField) edit before applying this suggestion." }
        if proposal.base != draft { return "Your recipe has changed. Send another message to update this suggestion using your latest edits." }
        return nil
    }

    func send(draft: RecipeDraft, collections: [RecipeCollection], householdID: UUID?, action explicitAction: RecipeChatAction? = nil) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty, text.count <= 1200 else { return }
        // A stale suggestion stays available for review, but never becomes the
        // starting point of another request after the user edits the recipe.
        let previous = pending.flatMap { $0.base == draft ? $0 : nil }
        let working = previous?.suggested ?? draft
        let history = messages.suffix(6).map { ($0.isUser ? "You: " : "Assistant: ") + String($0.text.prefix(400)) }.joined(separator: "\n")
        messages.append(RecipeChatMessage(text: text, isUser: true))
        input = ""; error = nil; retryRequest = nil; activeRequest = text
        busy = true; progress = "Understanding your request…"
        let id = UUID(); requestID = id
        task = Task { [weak self] in
            guard let self else { return }
            defer { if requestID == id { busy = false; task = nil; requestID = nil } }
            do {
                let action: RecipeChatAction
                if let explicitAction { action = explicitAction }
                else { action = try await OpenAIKeyStore.client().recipeChatAction(request: text, conversation: history) }
                try Task.checkCancellation()
                guard requestID == id else { return }
                choosingPhoto = false; needsPhotoUpload = false
                if action == .collections {
                    progress = "Checking your collections…"
                    let edit = try await RecipeEditorAssistant().collections(for: text, draft: draft, available: collections, conversation: history)
                    try Task.checkCancellation()
                    guard requestID == id else { return }
                    let selected = try edit.applying(to: draft.collectionIDs, available: Set(collections.map(\.id)))
                    pendingCollections = selected == draft.collectionIDs ? nil : RecipeCollectionProposal(base: draft.collectionIDs, edit: edit, householdID: householdID)
                    messages.append(RecipeChatMessage(text: pendingCollections != nil ? "Review the collection changes below, then apply them to your draft." : "No collection changes made." + (edit.question.isEmpty ? " The recipe already has that selection." : " " + edit.question)))
                    return
                }
                if action == .choosePhoto {
                    choosingPhoto = true
                    messages.append(RecipeChatMessage(text: "Would you like a photo from online, a generated cover, or an editorial edit of your own food photo?"))
                    return
                }
                if action != .recipe {
                    if action == .enhancePhoto, draft.imageData == nil {
                        needsPhotoUpload = true
                        messages.append(RecipeChatMessage(text: "Upload your food photo, then I can polish its lighting and presentation. You’ll be able to compare it with the original."))
                        return
                    }
                    let kind: RecipePhotoKind = action == .findPhoto ? .online : action == .generatePhoto ? .generated : .enhanced
                    let found = try await RecipePhotoService().prepare(kind: kind, draft: draft, request: text) { [weak self] status in
                        guard self?.requestID == id else { return }; self?.progress = status
                    }
                    try Task.checkCancellation()
                    guard requestID == id else { return }
                    photos = found
                    messages.append(RecipeChatMessage(text: kind == .online ? "Found \(found.count) online photo option\(found.count == 1 ? "" : "s"). Preview one, then choose Use photo to set it on your draft." : "Your photo is ready to preview. Choose Use photo when you’re happy with it.", sources: found.compactMap(\.source)))
                    return
                }
                let reply = try await RecipeEditorAssistant().respond(to: text, draft: working, conversation: history) { [weak self] status in
                    guard self?.requestID == id else { return }
                    self?.progress = status
                }
                try Task.checkCancellation()
                guard requestID == id else { return }
                let proposal = RecipeAssistantProposal(base: draft, suggested: reply.draft, sources: (previous?.sources ?? []) + [reply.source])
                pending = proposal.changes.isEmpty ? nil : proposal
                messages.append(RecipeChatMessage(text: reply.message, sources: [reply.source], assumptions: reply.assumptions))
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                retryRequest = text
            }
        }
    }

    func photoBlocker(_ photo: RecipePhotoProposal, draft: RecipeDraft) -> String? {
        if busy { return "Wait for the current request to finish." }
        if !photos.contains(where: { $0.id == photo.id }) { return "New photos are available. Open a new preview." }
        if draft.imageData != photo.previousImage { return "The recipe photo has changed. Request another photo to keep your newer choice safe." }
        return nil
    }

    func applyPhoto(_ photo: RecipePhotoProposal, to draft: inout RecipeDraft) {
        guard photoBlocker(photo, draft: draft) == nil else { return }
        do {
            let changed = try photo.applying(to: draft)
            undoStack.append(RecipeAssistantUndo(before: draft, after: changed))
            draft = changed; photos = []; error = nil; retryRequest = nil
            messages.append(RecipeChatMessage(text: "Photo set on your draft. Save the recipe to keep it."))
        } catch { self.error = error.localizedDescription }
    }

    func discardPhotos() { guard !busy else { return }; photos = [] }

    func collectionBlocker(draft: RecipeDraft, collections: [RecipeCollection], householdID: UUID?) -> String? {
        if busy { return "Wait for the current request to finish." }
        guard let pendingCollections else { return "Ask again to prepare collection changes." }
        do { _ = try pendingCollections.applying(to: draft, collections: collections, householdID: householdID); return nil }
        catch { return error.localizedDescription }
    }

    func applyCollections(to draft: inout RecipeDraft, collections: [RecipeCollection], householdID: UUID?) {
        guard !busy, let proposal = pendingCollections else { return }
        do {
            let changed = try proposal.applying(to: draft, collections: collections, householdID: householdID)
            undoStack.append(RecipeAssistantUndo(before: draft, after: changed))
            draft = changed; pendingCollections = nil; error = nil; retryRequest = nil
            let names = collections.filter { changed.collectionIDs.contains($0.id) }.map(\.name).joined(separator: ", ")
            messages.append(RecipeChatMessage(text: "Collections updated on your draft: \(names.isEmpty ? "none" : names). Tap Save to keep this selection."))
        } catch { self.error = error.localizedDescription }
    }

    func discardCollections() { guard !busy else { return }; pendingCollections = nil }

    func stop() {
        guard busy else { return }
        task?.cancel(); task = nil; requestID = nil; busy = false
        if input.isEmpty { input = activeRequest }
        messages.append(RecipeChatMessage(text: "Stopped. Your recipe hasn’t changed."))
    }

    func apply(to draft: inout RecipeDraft, proposalID: UUID) {
        guard let pending, pending.id == proposalID, applyBlocker(for: pending, draft: draft) == nil else { return }
        do {
            let changed = try pending.applying(to: draft)
            undoStack.append(RecipeAssistantUndo(before: draft, after: changed))
            draft = changed; self.pending = nil; error = nil; retryRequest = nil
            messages.append(RecipeChatMessage(text: "Applied to your draft. Tap Save in the recipe editor when you’re ready."))
        } catch { self.error = error.localizedDescription }
    }

    func discard() {
        guard !busy else { return }
        pending = nil; error = nil; retryRequest = nil
        messages.append(RecipeChatMessage(text: "Suggestion discarded. Your recipe hasn’t changed."))
    }

    func undo(in draft: inout RecipeDraft) {
        guard !busy, editingField == nil, let last = undoStack.last else { return }
        do {
            draft = try last.restoring(draft); undoStack.removeLast(); pending = nil; pendingCollections = nil; photos = []; error = nil
            messages.append(RecipeChatMessage(text: "Undid the last AI edit."))
        } catch { self.error = error.localizedDescription }
    }

    #if DEBUG
    /// Deterministic UI coverage without a key, network request or production fallback.
    func loadUITestProposal(draft: RecipeDraft, collections: [RecipeCollection], householdID: UUID?) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"), arguments.contains("--collection-chat-ui-testing"), messages.isEmpty,
           let collection = collections.first(where: { !draft.collectionIDs.contains($0.id) }) {
            pendingCollections = RecipeCollectionProposal(base: draft.collectionIDs, edit: RecipeCollectionEdit(add: [collection.id], remove: []), householdID: householdID)
            messages.append(RecipeChatMessage(text: "Review the collection changes below, then apply them to your draft."))
            return
        }
        if arguments.contains("--ui-testing"), arguments.contains("--recipe-photo-ui-testing"), messages.isEmpty,
           let image = UIImage(systemName: "fork.knife.circle.fill")?.pngData() {
            photos = RecipePhotoKind.allCases.map { kind in
                RecipePhotoProposal(image: image, previousImage: draft.imageData, originalPhoto: kind == .enhanced ? image : nil,
                                    kind: kind, source: kind == .online ? RecipeAssistantSource(title: "UI test photo source", url: URL(string: "https://example.com/recipe")!) : nil,
                                    imageURL: kind == .online ? URL(string: "https://example.com/photo.jpg")! : nil)
            }
            messages.append(RecipeChatMessage(text: "Photo options ready to preview."))
            return
        }
        guard arguments.contains("--ui-testing"), arguments.contains("--recipe-chat-ui-testing"), messages.isEmpty else { return }
        var suggested = draft
        suggested.servings = 6
        if !suggested.ingredients.isEmpty { suggested.ingredients[0].quantity = "750" }
        if suggested.ingredients.count > 1 { suggested.ingredients.removeLast() }
        suggested.ingredients.append(Ingredient(name: "Lime wedges", quantity: "2", group: "To serve"))
        if !suggested.steps.isEmpty { suggested.steps.removeLast() }
        suggested.steps.append(RecipeStep(text: "Serve with lime wedges.", group: "To serve"))
        pending = RecipeAssistantProposal(base: draft, suggested: suggested, sources: [
            RecipeAssistantSource(title: "UI test source", url: URL(string: "https://example.com/recipe-ui-fixture")!)
        ])
        messages.append(RecipeChatMessage(text: "Review the suggested ingredient and method changes."))
    }
    #endif
}

struct RecipeEditorChatView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var draft: RecipeDraft
    @ObservedObject var session: RecipeChatSession
    @Binding var expanded: Bool
    @FocusState private var inputFocused: Bool
    @State private var collapseOffset: CGFloat = 0
    @GestureState private var draggingHandle = false
    @State private var reviewing: RecipeAssistantProposal?
    @State private var reviewingPhoto: RecipePhotoProposal?
    @State private var showingPhotoTools = false
    @ObservedObject private var aiSettings = OpenAISettings.shared
    @State private var showingAISettings = false

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
            grabber
            if !session.photos.isEmpty || session.pending != nil || !session.undoStack.isEmpty {
                reviewActions.fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 16)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if session.messages.isEmpty || !aiSettings.isConfigured { introduction }
                        ForEach(session.messages) { message in messageView(message) }
                        if session.busy {
                            ProgressView(session.progress).font(.subheadline)
                                .accessibilityIdentifier("recipeChatProgress")
                        }
                        if let error = session.error {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error).font(.callout).foregroundStyle(.secondary)
                                if let request = session.retryRequest, !session.busy {
                                    Button("Try again", systemImage: "arrow.clockwise") {
                                        session.input = request; send()
                                    }
                                }
                            }.accessibilityIdentifier("recipeChatError")
                        }
                        if let proposal = session.pending { proposalCard(proposal) }
                        if let proposal = session.pendingCollections { collectionCard(proposal) }
                        if session.choosingPhoto || session.needsPhotoUpload { photoChoices }
                        if !session.photos.isEmpty { photoCards }
                        Color.clear.frame(height: 1).id("chatBottom")
                    }.padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("recipeChatMessages")
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.messages.count) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
                .onChange(of: session.busy) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
                .onAppear { proxy.scrollTo("chatBottom", anchor: .bottom) }
            }
            }
            composer.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
        }
        .supperGlassPanel()
        .offset(y: collapseOffset)
        .onChange(of: inputFocused) { _, focused in
            if focused && !expanded { withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { expanded = true } }
        }
        .onChange(of: expanded) { _, value in if !value { inputFocused = false } }
        .onChange(of: draggingHandle) { _, active in
            if !active { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { collapseOffset = 0 } }
        }
        .sheet(isPresented: $showingAISettings) {
            NavigationStack { AISettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAISettings = false } } } }
        }
        .sheet(item: $reviewing) { proposal in
            RecipeAssistantReviewView(proposal: proposal, blocker: session.applyBlocker(for: proposal, draft: draft)) {
                session.apply(to: &draft, proposalID: proposal.id); reviewing = nil
            }
        }
        .sheet(item: $reviewingPhoto) { photo in
            RecipePhotoReviewView(proposal: photo, blocker: session.photoBlocker(photo, draft: draft)) {
                session.applyPhoto(photo, to: &draft); reviewingPhoto = nil
            }
        }
        .sheet(isPresented: $showingPhotoTools) { RecipeCoverView(draft: $draft, initialMode: .enhanced, initialRequest: session.photoPreferences) }
    }

    private var grabber: some View {
        Button(action: collapse) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity).frame(height: 28).contentShape(.rect)
        }.buttonStyle(.plain).accessibilityLabel("Collapse chat")
            .accessibilityIdentifier("toggleRecipeChat")
            .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .updating($draggingHandle) { _, active, _ in active = true }
                .onChanged { value in
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { collapseOffset = max(0, min(value.translation.height, 120)) }
                }
                .onEnded { value in
                    if value.translation.height > 20 || value.predictedEndTranslation.height > 60 { collapse() }
                })
    }

    private func collapse() {
        inputFocused = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { expanded = false; collapseOffset = 0 }
    }

    private var reviewActions: some View {
        HStack(spacing: 8) {
            if let photo = session.photos.first {
                Button("Preview") { inputFocused = false; reviewingPhoto = photo }
                    .supperGlassButton().accessibilityIdentifier("reviewChatPhoto")
            } else if let proposal = session.pending {
                Button("Preview") { inputFocused = false; reviewing = proposal }
                    .supperGlassButton().accessibilityIdentifier("reviewRecipeAIEdit")
            } else if let last = session.undoStack.last, last.after == draft, !session.busy {
                Button("Undo") { session.undo(in: &draft) }
                    .supperGlassButton().disabled(session.editingField != nil)
                    .accessibilityLabel("Undo last AI edit").accessibilityIdentifier("undoRecipeAIEdit")
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            if aiSettings.isConfigured {
                if session.messages.isEmpty {
                    ForEach(suggestions, id: \.self) { text in
                        Button(text) { session.input = text; inputFocused = true }
                            .font(.subheadline).buttonStyle(.bordered).tint(.primary)
                    }
                }
            } else {
                Button("Set up OpenAI", systemImage: "key") { showingAISettings = true }
            }
        }
    }

    private var suggestions: [String] {
        if draft.ingredients.isEmpty && draft.steps.isEmpty {
            return ["Find ingredients and a method for this recipe", "Help me with just one part of this recipe"]
        }
        if draft.steps.isEmpty { return ["Find a method for these ingredients", "Help me add another part of this recipe"] }
        return ["Help me add another part of this recipe", "Find a published alternative for…", "Organise this recipe into sections"]
    }

    private func messageView(_ message: RecipeChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.isUser ? "You" : "Supper").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(message.text).font(.body).textSelection(.enabled)
            if !message.assumptions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assumptions to review").font(.caption.weight(.semibold))
                    ForEach(Array(message.assumptions.enumerated()), id: \.offset) { _, assumption in
                        Text(assumption).font(.subheadline)
                    }
                }.foregroundStyle(.secondary)
            }
            ForEach(message.sources) { source in
                Link(destination: source.url) { Label(source.title, systemImage: "link").font(.caption) }
            }
        }
        .padding(message.isUser ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.isUser ? Color.primary.opacity(0.05) : .clear, in: .rect(cornerRadius: 18))
    }

    private func proposalCard(_ proposal: RecipeAssistantProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Suggested changes", systemImage: "square.and.pencil").font(.headline)
            if !session.photos.isEmpty {
                Button("Preview recipe changes") { reviewing = proposal }
            }
            Text("\(proposal.changes.count) changes ready to review").font(.subheadline).foregroundStyle(.secondary)
            if let blocker = session.applyBlocker(for: proposal, draft: draft) {
                Text(blocker).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("recipeAIApplyBlocker")
            }
            Button("Apply to draft") { session.apply(to: &draft, proposalID: proposal.id) }
                .supperGlassButton(prominent: true)
                .disabled(session.applyBlocker(for: proposal, draft: draft) != nil)
                .accessibilityIdentifier("applyRecipeAIEdit")
            Button("Discard suggestion", role: .destructive) { session.discard() }
                .font(.caption).disabled(session.busy).accessibilityIdentifier("discardRecipeAIEdit")
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 20))
            .accessibilityIdentifier("recipeAIProposal")
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if expanded && session.input.count > 1200 { Text("Keep your request under 1,200 characters.").font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .bottom, spacing: 10) {
                if expanded {
                Menu("Photo options", systemImage: "photo.badge.plus") {
                    Button("Find a photo online") { photoRequest(.findPhoto) }
                    Button("Generate a cover") { photoRequest(.generatePhoto) }
                    Button("Polish my food photo") { inputFocused = false; showingPhotoTools = true }
                }.labelStyle(.iconOnly).tint(.primary).frame(width: 36, height: 44)
                    .disabled(session.busy).accessibilityIdentifier("chatPhotoOptions")
                }
                TextField(session.pending?.base == draft ? "Refine this suggestion…" : "Ask about this recipe…", text: $session.input, axis: .vertical)
                    .lineLimit(expanded ? 1...3 : 1...1).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
                    .background(expanded ? Color.primary.opacity(0.05) : .clear, in: .capsule).focused($inputFocused)
                    .accessibilityIdentifier("recipeChatInput")
                    .accessibilityLabel("Ask about this recipe")
                    .accessibilityHint(expanded ? "" : "Opens recipe chat")
                if expanded {
                if session.busy {
                    Button("Stop", systemImage: "stop.fill") { session.stop() }
                        .labelStyle(.iconOnly).supperGlassButton().controlSize(.regular).buttonBorderShape(.circle).frame(width: 44, height: 44)
                } else {
                    Button("Send", systemImage: "arrow.up") { send() }
                        .labelStyle(.iconOnly).supperGlassButton(prominent: true).controlSize(.regular).buttonBorderShape(.circle).frame(width: 44, height: 44)
                        .disabled(!aiSettings.isConfigured || session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.input.count > 1200)
                        .accessibilityIdentifier("sendRecipeChat")
                }
                }
            }
        }.padding(.horizontal, expanded ? 12 : 4).padding(.vertical, 6)
    }

    private func send() { inputFocused = false; session.send(draft: draft, collections: store.collections, householdID: store.activeHouseholdID) }

    private func collectionCard(_ proposal: RecipeCollectionProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Collection changes", systemImage: "folder").font(.headline)
            ForEach(store.collections.filter { proposal.edit.add.contains($0.id) && !proposal.base.contains($0.id) }) { collection in
                Label(collection.name, systemImage: "plus.circle").accessibilityLabel("Add to \(collection.name)")
            }
            ForEach(store.collections.filter { proposal.edit.remove.contains($0.id) && proposal.base.contains($0.id) }) { collection in
                Label(collection.name, systemImage: "minus.circle").strikethrough().accessibilityLabel("Remove from \(collection.name)")
            }
            if let blocker = session.collectionBlocker(draft: draft, collections: store.collections, householdID: store.activeHouseholdID) {
                Text(blocker).font(.caption).foregroundStyle(.secondary)
            }
            Button("Apply to draft") {
                session.applyCollections(to: &draft, collections: store.collections, householdID: store.activeHouseholdID)
            }.supperGlassButton(prominent: true).accessibilityIdentifier("applyChatCollections")
                .disabled(session.collectionBlocker(draft: draft, collections: store.collections, householdID: store.activeHouseholdID) != nil)
            Button("Discard", role: .destructive) { session.discardCollections() }.disabled(session.busy)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 20))
    }

    private var photoChoices: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.choosingPhoto {
                Button("Find a photo online", systemImage: "globe") { photoRequest(.findPhoto) }
                Button("Generate a cover", systemImage: "sparkles") { photoRequest(.generatePhoto) }
            }
            Button("Upload and polish a food photo", systemImage: "photo.badge.plus") { inputFocused = false; showingPhotoTools = true }
        }.font(.subheadline).disabled(session.busy)
    }

    private var photoCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photo options").font(.headline)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(session.photos.enumerated()), id: \.element.id) { index, photo in
                        Button { inputFocused = false; reviewingPhoto = photo } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                RecipeImage(data: photo.image).frame(width: 170, height: 120).clipShape(.rect(cornerRadius: 14))
                                Text(photo.caption).font(.caption).lineLimit(2)
                                Label("Preview", systemImage: "eye").font(.caption.weight(.semibold))
                            }.frame(width: 170, alignment: .leading)
                        }.buttonStyle(.plain).accessibilityIdentifier("previewChatPhoto-\(index)")
                    }
                }
            }.accessibilityIdentifier("chatPhotoCarousel")
            Button("Discard photo options", role: .destructive) { session.discardPhotos() }.font(.caption).disabled(session.busy)
        }
    }

    private func photoRequest(_ action: RecipeChatAction) {
        guard aiSettings.isConfigured else { showingAISettings = true; return }
        let preferences = session.photoPreferences
        session.input = preferences.isEmpty ? (action == .findPhoto ? "Find a photo online for this recipe" : "Generate an editorial cover for this recipe") : preferences
        inputFocused = false; session.send(draft: draft, collections: store.collections, householdID: store.activeHouseholdID, action: action)
    }
}
