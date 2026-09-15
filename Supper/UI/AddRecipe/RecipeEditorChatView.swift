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
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var activeRequest = ""

    func reconcile(with current: RecipeDraft) {
        if let pending, pending.base != current {
            self.pending = nil
            messages.append(RecipeChatMessage(text: "The recipe has changed. Your next request will use the latest draft."))
        }
    }

    func send(draft: RecipeDraft) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty, text.count <= 1200 else { return }
        reconcile(with: draft)
        let previous = pending
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

    func apply(to draft: inout RecipeDraft) {
        guard !busy, let pending else { return }
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
        guard !busy, let last = undoStack.last else { return }
        do {
            draft = try last.restoring(draft); undoStack.removeLast(); pending = nil; error = nil
            messages.append(RecipeChatMessage(text: "Undid the last AI edit."))
        } catch { self.error = error.localizedDescription }
    }
}

struct RecipeEditorChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: RecipeDraft
    @ObservedObject var session: RecipeChatSession
    @FocusState private var inputFocused: Bool
    @State private var reviewing = false
    @ObservedObject private var aiSettings = OpenAISettings.shared
    @State private var showingAISettings = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        introduction
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
                        if let last = session.undoStack.last, last.after == draft, !session.busy {
                            Button("Undo last AI edit", systemImage: "arrow.uturn.backward") {
                                session.undo(in: &draft)
                            }.font(.subheadline).accessibilityIdentifier("undoRecipeAIEdit")
                        }
                        Color.clear.frame(height: 1).id("chatBottom")
                    }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.messages.count) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
                .onChange(of: session.busy) { _, _ in proxy.scrollTo("chatBottom", anchor: .bottom) }
            }
            .background(SupperStyle.canvas)
            .navigationTitle("Ask AI").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { session.stop(); dismiss() }.accessibilityIdentifier("closeRecipeChat")
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .onAppear { session.reconcile(with: draft) }
            .onDisappear { session.stop() }
            .sheet(isPresented: $showingAISettings) {
                NavigationStack { AISettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAISettings = false } } } }
            }
            .sheet(isPresented: $reviewing) {
                if let proposal = session.pending {
                    RecipeAssistantReviewView(proposal: proposal, canApply: !session.busy && proposal.base == draft) {
                        session.apply(to: &draft); reviewing = false
                    }
                }
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(draft.title.isEmpty ? "Build your recipe" : draft.title, systemImage: "sparkles")
                .font(.title3.weight(.semibold))
            if aiSettings.isConfigured {
                Text("Tell me what to add or change. I’ll consult online recipes and let you review the changes first.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if session.messages.isEmpty {
                    ForEach(suggestions, id: \.self) { text in
                        Button(text) { session.input = text; inputFocused = true }
                            .font(.subheadline).buttonStyle(.bordered).tint(.primary)
                    }
                }
            } else {
                Text("Connect your OpenAI API key to search published recipes and edit this draft. Your request and relevant recipe content will be sent to OpenAI. Manual editing and URL import still work without a key.")
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
            if session.busy { Text("Refining this suggestion…").font(.caption).foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                HStack { proposalActions }
                VStack(alignment: .leading) { proposalActions }
            }
            Button("Discard suggestion", role: .destructive) { session.discard() }
                .font(.caption).disabled(session.busy).accessibilityIdentifier("discardRecipeAIEdit")
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(SupperStyle.surface, in: .rect(cornerRadius: 20))
            .accessibilityIdentifier("recipeAIProposal")
    }

    @ViewBuilder private var proposalActions: some View {
        Button("Review changes") { reviewing = true }
            .supperGlassButton().disabled(session.busy).accessibilityIdentifier("reviewRecipeAIEdit")
        Button("Apply") { session.apply(to: &draft) }
            .supperGlassButton(prominent: true).disabled(session.busy || session.pending?.base != draft)
            .accessibilityIdentifier("applyRecipeAIEdit")
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if session.input.count > 1200 { Text("Keep your request under 1,200 characters.").font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(session.pending == nil ? "Ask about this recipe…" : "Refine this suggestion…", text: $session.input, axis: .vertical)
                    .lineLimit(1...5).padding(.horizontal, 16).padding(.vertical, 13)
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
            if session.messages.isEmpty {
                Text("Type or use your keyboard’s dictation microphone.").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func send() { inputFocused = false; session.send(draft: draft) }
}

private struct RecipeAssistantReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let proposal: RecipeAssistantProposal
    let canApply: Bool
    let apply: () -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(proposal.changes) { change in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(change.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            if let before = change.before {
                                Label { Text(before).strikethrough() } icon: { Image(systemName: "minus.circle") }
                                    .foregroundStyle(.secondary).accessibilityLabel("Before: \(before)")
                            }
                            if let after = change.after {
                                Label { Text(after) } icon: { Image(systemName: "plus.circle") }
                                    .accessibilityLabel("After: \(after)")
                            }
                        }.padding(.vertical, 5)
                    }
                } footer: { Text("Applies to your draft. Save the recipe to keep these changes. Source links are added to Notes.") }
                Section("Online sources") {
                    ForEach(proposal.sources) { source in Link(source.title, destination: source.url) }
                }
            }.navigationTitle("Review Changes").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply", action: apply).disabled(!canApply) }
                }
        }
    }
}
