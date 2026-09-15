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
    @Published private(set) var undoStack: [RecipeAssistantUndo] = []
    @Published private(set) var busy = false
    @Published private(set) var progress = ""
    @Published private(set) var error: String?
    @Published private(set) var retryRequest: String?
    @Published var editingField: String?
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var activeRequest = ""

    func applyBlocker(for proposal: RecipeAssistantProposal, draft: RecipeDraft) -> String? {
        if busy { return "Wait for the current request to finish." }
        if pending?.id != proposal.id { return "A newer suggestion is available. Reopen the preview to review it." }
        if let editingField { return "Finish your \(editingField) edit before applying this suggestion." }
        if proposal.base != draft { return "Your recipe has changed. Send another message to update this suggestion using your latest edits." }
        return nil
    }

    func send(draft: RecipeDraft) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty, text.count <= 1200 else { return }
        // A stale suggestion stays available for review, but never becomes the
        // starting point of another request after the user edits the recipe.
        let previous = pending.flatMap { $0.base == draft ? $0 : nil }
        let working = previous?.suggested ?? draft
        let history = messages.suffix(6).map { ($0.isUser ? "You: " : "Assistant: ") + String($0.text.prefix(400)) }.joined(separator: "\n")
        messages.append(RecipeChatMessage(text: text, isUser: true))
        input = ""; error = nil; retryRequest = nil; activeRequest = text
        busy = true; progress = "Finding online sources…"
        let id = UUID(); requestID = id
        task = Task { [weak self] in
            guard let self else { return }
            defer { if requestID == id { busy = false; task = nil; requestID = nil } }
            do {
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
            draft = try last.restoring(draft); undoStack.removeLast(); pending = nil; error = nil
            messages.append(RecipeChatMessage(text: "Undid the last AI edit."))
        } catch { self.error = error.localizedDescription }
    }

    #if DEBUG
    /// Deterministic UI coverage without a key, network request or production fallback.
    func loadUITestProposal(draft: RecipeDraft) {
        let arguments = ProcessInfo.processInfo.arguments
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
    @Binding var draft: RecipeDraft
    @ObservedObject var session: RecipeChatSession
    @Binding var expanded: Bool
    let close: () -> Void
    @FocusState private var inputFocused: Bool
    @State private var reviewing: RecipeAssistantProposal?
    @ObservedObject private var aiSettings = OpenAISettings.shared
    @State private var showingAISettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if session.messages.isEmpty { introduction }
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
                        Color.clear.frame(height: 1).id("chatBottom")
                    }.padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("recipeChatMessages")
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.messages.count) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
                .onChange(of: session.busy) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
            }
            composer
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .sheet(isPresented: $showingAISettings) {
            NavigationStack { AISettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAISettings = false } } } }
        }
        .sheet(item: $reviewing) { proposal in
            RecipeAssistantReviewView(proposal: proposal, blocker: session.applyBlocker(for: proposal, draft: draft)) {
                session.apply(to: &draft, proposalID: proposal.id); reviewing = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                inputFocused = false; expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask AI").font(.subheadline.weight(.semibold))
                        if session.busy { Text("Working…").font(.caption2).foregroundStyle(.secondary) }
                        else if let pending = session.pending { Text("\(pending.changes.count) suggested changes").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Image(systemName: expanded ? "chevron.down" : "chevron.up").font(.caption)
                }.frame(minHeight: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Minimise Ask AI" : "Expand Ask AI")
                .accessibilityIdentifier("toggleRecipeChat")
            Spacer(minLength: 0)
            if let proposal = session.pending {
                Button("Preview") { inputFocused = false; reviewing = proposal }
                    .supperGlassButton().accessibilityIdentifier("reviewRecipeAIEdit")
            } else if let last = session.undoStack.last, last.after == draft, !session.busy {
                Button("Undo") { session.undo(in: &draft) }
                    .supperGlassButton().disabled(session.editingField != nil)
                    .accessibilityLabel("Undo last AI edit").accessibilityIdentifier("undoRecipeAIEdit")
            }
            Button("Close chat", systemImage: "xmark") { inputFocused = false; close() }
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
                .accessibilityIdentifier("closeRecipeChat")
        }.padding(.horizontal, 16).padding(.vertical, 7)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            if aiSettings.isConfigured {
                Text("Ask me to add or change something. I’ll find online sources and suggest edits for you to preview.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if session.messages.isEmpty {
                    ForEach(suggestions, id: \.self) { text in
                        Button(text) { session.input = text; inputFocused = true }
                            .font(.subheadline).buttonStyle(.bordered).tint(.primary)
                    }
                }
            } else {
                Text("Connect your OpenAI API key to search published recipes and suggest edits. Requests and relevant recipe content are sent to OpenAI.")
                    .font(.subheadline).foregroundStyle(.secondary)
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
        .background(message.isUser ? SupperStyle.surface : .clear, in: .rect(cornerRadius: 18))
    }

    private func proposalCard(_ proposal: RecipeAssistantProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Suggested changes", systemImage: "square.and.pencil").font(.headline)
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
            .background(SupperStyle.surface, in: .rect(cornerRadius: 20))
            .accessibilityIdentifier("recipeAIProposal")
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if session.input.count > 1200 { Text("Keep your request under 1,200 characters.").font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(session.pending?.base == draft ? "Refine this suggestion…" : "Ask about this recipe…", text: $session.input, axis: .vertical)
                    .lineLimit(1...3).padding(.horizontal, 16).padding(.vertical, 10)
                    .supperGlassSurface().focused($inputFocused)
                    .accessibilityIdentifier("recipeChatInput")
                if session.busy {
                    Button("Stop", systemImage: "stop.fill") { session.stop() }
                        .labelStyle(.iconOnly).supperGlassButton().controlSize(.large)
                } else {
                    Button("Send", systemImage: "arrow.up") { send() }
                        .labelStyle(.iconOnly).supperGlassButton(prominent: true).controlSize(.large)
                        .disabled(!aiSettings.isConfigured || session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.input.count > 1200)
                        .accessibilityIdentifier("sendRecipeChat")
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func send() { inputFocused = false; session.send(draft: draft) }
}
