import SwiftUI

struct RecipeChatMessage: Identifiable {
    let id = UUID()
    let text: String
    var isUser = false
    var sources: [RecipeAssistantSource] = []
    var assumptions: [String] = []
    var adaptations: [String] = []
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
    private let recipeSession = RecipeEditSession()
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
        let history = messages.suffix(6).map { ($0.isUser ? "You: " : "Assistant: ") + String($0.text.prefix(1200)) }.joined(separator: "\n")
        let isRetry = retryRequest == text && messages.last?.isUser == true && messages.last?.text == text
        let userInput = (messages.filter(\.isUser).map(\.text) + (isRetry ? [] : [text])).joined(separator: "\n")
        if !isRetry { messages.append(RecipeChatMessage(text: text, isUser: true)) }
        input = ""; error = nil; retryRequest = nil; activeRequest = text
        busy = true; progress = "Understanding your request…"
        let id = UUID(); requestID = id
        task = Task { [weak self] in
            guard let self else { return }
            defer { if requestID == id { busy = false; task = nil; requestID = nil } }
            do {
                let response: RecipeChatReply
                if let explicitAction {
                    recipeSession.reset()
                    response = .action(explicitAction)
                } else {
                    response = try await RecipeEditorAssistant().respond(to: text, draft: working,
                        conversation: history, userInput: userInput, session: recipeSession) { [weak self] status in
                        guard self?.requestID == id else { return }
                        self?.progress = status
                    }
                }
                try Task.checkCancellation()
                guard requestID == id else { return }
                choosingPhoto = false; needsPhotoUpload = false
                let action: RecipeChatAction
                switch response {
                case .recipe(let reply):
                    let sources = reply.source.map { [$0] } ?? []
                    if let changed = reply.draft {
                        let proposal = RecipeAssistantProposal(base: draft, suggested: changed, sources: (previous?.sources ?? []) + sources,
                            adaptations: (previous?.adaptations ?? []) + reply.adaptations,
                            assumptions: (previous?.assumptions ?? []) + reply.assumptions)
                        pending = proposal.changes.isEmpty ? nil : proposal
                    }
                    // Clarifications and declined adaptations leave any earlier proposal intact.
                    messages.append(RecipeChatMessage(text: reply.message, sources: sources, assumptions: reply.assumptions, adaptations: reply.adaptations))
                    return
                case .action(let routed): action = routed
                }
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
                    messages.append(RecipeChatMessage(text: "Would you like a photo from online, a generated cover, or a new cookbook photo using your own food as the reference?"))
                    return
                }
                if action != .recipe {
                    if action == .enhancePhoto, draft.imageData == nil {
                        needsPhotoUpload = true
                        messages.append(RecipeChatMessage(text: "Upload your food photo, then I can create a new top-down cookbook photograph using it as the food reference. You’ll be able to compare it with the original."))
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
            recipeSession.reset()
            messages.append(RecipeChatMessage(text: "Applied to your draft. Tap Save in the recipe editor when you’re ready."))
        } catch { self.error = error.localizedDescription }
    }

    func discard() {
        guard !busy else { return }
        pending = nil; error = nil; retryRequest = nil
        recipeSession.reset()
        messages.append(RecipeChatMessage(text: "Suggestion discarded. Your recipe hasn’t changed."))
    }

    func undo(in draft: inout RecipeDraft) {
        guard !busy, editingField == nil, let last = undoStack.last else { return }
        do {
            draft = try last.restoring(draft); undoStack.removeLast(); pending = nil; pendingCollections = nil; photos = []; error = nil
            recipeSession.reset()
            messages.append(RecipeChatMessage(text: "Undid the last AI edit."))
        } catch { self.error = error.localizedDescription }
    }

    #if DEBUG
    /// Deterministic UI coverage without a key, network request or production fallback.
    func loadUITestProposal(draft: RecipeDraft, collections: [RecipeCollection], householdID: UUID?) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"), arguments.contains("--collection-chat-ui-testing"), messages.isEmpty,
           let collection = collections.first(where: { $0.id != RecipeCollection.exploreID && !draft.collectionIDs.contains($0.id) }) {
            pendingCollections = RecipeCollectionProposal(base: draft.collectionIDs, edit: RecipeCollectionEdit(add: [collection.id], remove: []), householdID: householdID)
            messages.append(RecipeChatMessage(text: "Review the collection changes below, then apply them to your draft."))
            return
        }
        if arguments.contains("--ui-testing"), arguments.contains("--recipe-photo-ui-testing"), messages.isEmpty {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 640)).pngData { context in
                UIColor.systemOrange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 640, height: 640))
            }
            // A tall original reproduces scaled-to-fill content extending over
            // the comparison picker despite the preview's square clipping.
            let original = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 640)).pngData { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 320, height: 640))
            }
            photos = RecipePhotoKind.allCases.map { kind in
                RecipePhotoProposal(image: image, previousImage: draft.imageData, originalPhoto: kind == .enhanced ? original : nil,
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var draft: RecipeDraft
    @ObservedObject var session: RecipeChatSession
    @FocusState private var inputFocused: Bool
    @State private var detent: PresentationDetent = .large
    @State private var sendButtonHeight: CGFloat = 50
    @State private var reviewing: RecipeAssistantProposal?
    @State private var reviewingPhoto: RecipePhotoProposal?
    @State private var showingPhotoTools = false
    @ObservedObject private var aiSettings = OpenAISettings.shared
    @State private var showingAISettings = false

    var body: some View {
        NavigationStack {
            conversation
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer
                }
                .toolbar {
                    if hasReviewAction {
                        ToolbarItem(placement: .topBarLeading) { reviewActions }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close chat", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly).tint(.primary)
                            .accessibilityIdentifier("closeRecipeChat")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") {
                            inputFocused = false
                        }.accessibilityIdentifier("hideRecipeChatKeyboard")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        // Let the presentation controller own the surface, grabber, keyboard
        // avoidance and interactive transitions between both resting heights.
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .onChange(of: inputFocused) { _, focused in
            if focused { withAnimation(reduceMotion ? nil : .default) { detent = .large } }
        }
        .task { inputFocused = session.messages.isEmpty || !session.input.isEmpty }
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

    private var conversation: some View {
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
                                .textSelection(.enabled)
                                .contextMenu { Button("Copy error details", systemImage: "doc.on.doc") { UIPasteboard.general.string = error } }
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
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("recipeChatMessages")
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .onChange(of: session.messages.count) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
            .onChange(of: session.busy) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
            .onAppear { if !session.messages.isEmpty { proxy.scrollTo("chatBottom", anchor: .bottom) } }
        }
    }

    private var hasReviewAction: Bool {
        !session.photos.isEmpty || session.pending != nil ||
        (session.undoStack.last?.after == draft && !session.busy)
    }

    private var reviewActions: some View {
        HStack(spacing: 8) {
            if let photo = session.photos.first {
                Button("Preview") { inputFocused = false; reviewingPhoto = photo }
                    .accessibilityIdentifier("reviewChatPhoto")
            } else if let proposal = session.pending {
                Button("Preview") { inputFocused = false; reviewing = proposal }
                    .accessibilityIdentifier("reviewRecipeAIEdit")
            } else if let last = session.undoStack.last, last.after == draft, !session.busy {
                Button("Undo") { session.undo(in: &draft) }
                    .disabled(session.editingField != nil)
                    .accessibilityLabel("Undo last AI edit").accessibilityIdentifier("undoRecipeAIEdit")
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            if aiSettings.isConfigured {
                if session.messages.isEmpty {
                    Text("A little help with your recipe")
                        .font(.title3.weight(.semibold))
                    Text("Find a method, adjust part of a recipe or organise it into sections.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(suggestions, id: \.self) { text in
                            Button { session.input = text; inputFocused = true } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(text).multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.up.left").foregroundStyle(.secondary)
                                }.font(.subheadline).padding(.vertical, 14)
                            }.buttonStyle(.plain)
                            if text != suggestions.last { Divider() }
                        }
                    }
                }
            } else {
                Text("Get help with this recipe").font(.title3.weight(.semibold))
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
            Text(message.text).font(.body).textSelection(.enabled)
            if !message.adaptations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Adaptations from the base recipe").font(.caption.weight(.semibold))
                    Text(RecipeAssistantProposal.adaptationNotice).font(.caption)
                    ForEach(Array(message.adaptations.enumerated()), id: \.offset) { _, adaptation in
                        Text(adaptation).font(.subheadline)
                    }
                }.foregroundStyle(.secondary)
            }
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
            if !proposal.adaptations.isEmpty {
                Text(RecipeAssistantProposal.adaptationNotice).font(.caption).foregroundStyle(.secondary)
            }
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
            if session.input.count > 1200 {
                Text("Keep your request under 1,200 characters.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu("Photo options", systemImage: "photo.badge.plus") {
                    Button("Find a photo online") { photoRequest(.findPhoto) }
                    Button("Generate a cover") { photoRequest(.generatePhoto) }
                    Button("Create from my food photo") { inputFocused = false; showingPhotoTools = true }
                }
                .labelStyle(.iconOnly).supperGlassButton().tint(.primary)
                .controlSize(.large).buttonBorderShape(.circle)
                .disabled(session.busy).accessibilityIdentifier("chatPhotoOptions")

                TextField(session.pending?.base == draft ? "Refine this suggestion…" : "Ask about this recipe…", text: $session.input, axis: .vertical)
                    .font(.body).lineLimit(1...6)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(minHeight: sendButtonHeight)
                    .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: sendButtonHeight / 2))
                    .focused($inputFocused)
                    .accessibilityIdentifier("recipeChatInput")
                    .accessibilityLabel("Ask about this recipe")

                // Measure the native button itself. An outer frame only resizes
                // its hit area, leaving the visible glass smaller than the field.
                Group {
                    if session.busy {
                        Button("Stop", systemImage: "stop.fill") { session.stop() }
                            .supperGlassButton().accessibilityIdentifier("stopRecipeChat")
                    } else {
                        Button("Send", systemImage: "arrow.up") { send() }
                            .supperGlassButton(prominent: true)
                            .disabled(!aiSettings.isConfigured || session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.input.count > 1200)
                            .accessibilityIdentifier("sendRecipeChat")
                    }
                }
                .labelStyle(.iconOnly).controlSize(.large).buttonBorderShape(.circle)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sendButtonHeight = $0 }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: 680).frame(maxWidth: .infinity)
    }

    private func send() {
        session.send(draft: draft, collections: store.collections, householdID: store.activeHouseholdID)
    }

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
            Button("Create from a food photo", systemImage: "photo.badge.plus") { inputFocused = false; showingPhotoTools = true }
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
