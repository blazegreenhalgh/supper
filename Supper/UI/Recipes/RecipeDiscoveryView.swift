import SwiftUI

@MainActor
final class RecipeDiscoveryModel: ObservableObject {
    @Published var prompt = ""
    @Published var mode: RecipeDiscoveryMode = .online
    @Published private(set) var review = RecipeDiscoveryReview()
    @Published private(set) var hasResults = false
    @Published private(set) var busy = false
    @Published private(set) var progress = ""
    @Published var error: String?
    @Published private(set) var notice: String?
    private var householdID: UUID?
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    func search(in store: RecipeStore) {
        guard !busy else { return }
        cancel()
        let token = UUID(); requestID = token
        householdID = store.activeHouseholdID
        let text = prompt, mode = mode
        let existing = Set(store.recipes.map(RecipeDiscoveryReview.key))
        busy = true; error = nil; progress = "Setting the table…"
        task = Task {
            defer { if requestID == token { busy = false; task = nil } }
            do {
                let result: RecipeDiscoveryResult
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--discovery-ui-testing") {
                    result = Self.fixture
                } else {
                    result = try await RecipeDiscoveryService().discover(text, mode: mode) { [weak self] message in
                        if self?.requestID == token { self?.progress = message }
                    }
                }
                #else
                result = try await RecipeDiscoveryService().discover(text, mode: mode) { [weak self] message in
                    if self?.requestID == token { self?.progress = message }
                }
                #endif
                try Task.checkCancellation()
                guard requestID == token else { return }
                let new = result.suggestions.filter { !existing.contains(RecipeDiscoveryReview.key($0.recipe)) }
                guard !new.isEmpty else { throw SupperError.invalid("These recipes are already in your library. Try a different craving to find something new.") }
                review = RecipeDiscoveryReview(suggestions: new)
                notice = result.notice; hasResults = true
            } catch {
                if !Task.isCancelled, requestID == token { self.error = error.localizedDescription }
            }
        }
    }
    func cancel() { requestID = UUID(); task?.cancel(); task = nil; busy = false }
    func startOver() { cancel(); review = RecipeDiscoveryReview(); hasResults = false; notice = nil; error = nil }
    func edit(_ recipe: Recipe) { review.edit(recipe) }
    @discardableResult func keep(_ suggestion: RecipeSuggestion, in store: RecipeStore) -> Bool {
        guard review.pending.contains(where: { $0.id == suggestion.id }) else { return false }
        do {
            guard householdID == store.activeHouseholdID else { throw SupperError.invalid("The active household changed. Switch back before keeping these recipes.") }
            if !store.recipes.contains(where: { RecipeDiscoveryReview.key($0) == RecipeDiscoveryReview.key(suggestion.recipe) }) {
                try store.addRecipe(suggestion.recipe)
            }
            review.didKeep(suggestion.id)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func discard(_ id: UUID) { review.discard(id) }
    func undoDiscard() { review.undoDiscard() }

    #if DEBUG
    private static var fixture: RecipeDiscoveryResult {
        RecipeDiscoveryResult(suggestions: ["Lemon chicken bowls", "Creamy mushroom pasta", "Crispy chickpea wraps"].map { title in
            RecipeSuggestion(recipe: Recipe(title: title, durationMinutes: 25, servings: 4, tags: ["Dinner"],
                ingredients: [Ingredient(name: "rice", quantity: "200", unit: "g"), Ingredient(name: "lemon", quantity: "1")],
                steps: [RecipeStep(text: "Prepare the ingredients."), RecipeStep(text: "Cook and serve.", order: 1)]), mode: .create)
        }, notice: "Preview recipes for UI testing.")
    }
    #endif
}

struct RecipeDiscoveryView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model: RecipeDiscoveryModel
    @AppStorage("discoveryGridView") private var gridView = false
    @State private var path: [UUID] = []
    @State private var showingStartOver = false
    @State private var feedback = 0
    @State private var swipingRecipe = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.busy { loading }
                else if model.hasResults { results }
                else { requestForm }
            }
            .background(SupperStyle.canvas)
            .navigationTitle(model.hasResults ? "Fresh ideas" : "What are you craving?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { model.cancel(); dismiss() }.accessibilityIdentifier("closeDiscovery")
                }
                if model.hasResults {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(gridView ? "Stack view" : "Grid view", systemImage: gridView ? "rectangle.stack" : "square.grid.2x2") {
                            withAnimation(reduceMotion ? nil : .snappy) { gridView.toggle() }
                        }.accessibilityIdentifier("discoveryLayout")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Discovery options", systemImage: "ellipsis") {
                            Button("New request", systemImage: "sparkles") {
                                if model.review.pending.isEmpty { model.startOver() } else { showingStartOver = true }
                            }
                            Button("Undo last discard", systemImage: "arrow.uturn.backward") { model.undoDiscard() }
                                .disabled(model.review.discardedIDs.isEmpty)
                        }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let suggestion = model.review.suggestions.first(where: { $0.id == id }) {
                    RecipeDetailView(preview: Binding(
                        get: { model.review.suggestions.first(where: { $0.id == id })?.recipe ?? suggestion.recipe },
                        set: { model.edit($0) }
                    ))
                }
            }
            .confirmationDialog("Start a new request?", isPresented: $showingStartOver, titleVisibility: .visible) {
                Button("Discard remaining ideas", role: .destructive) { model.startOver() }
            } message: { Text("Recipes you kept are already saved. The remaining ideas will be discarded.") }
            .supperError($model.error, title: "Couldn’t finish that")
            .sensoryFeedback(.success, trigger: feedback)
        }
        .presentationDragIndicator(.visible)
        .onDisappear { model.cancel() }
    }

    private var requestForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.tint)
                    Text("Let’s find your next favourite.").font(.largeTitle.bold())
                    Text("A dish, a mood, a few ingredients. Tell Supper what sounds good.")
                        .foregroundStyle(.secondary)
                }
                TextField("Something cosy with chicken, under 30 minutes…", text: $model.prompt, axis: .vertical)
                    .lineLimit(3...6).padding(16).background(SupperStyle.surface, in: .rect(cornerRadius: 20))
                    .focused($promptFocused).accessibilityIdentifier("discoveryPrompt")
                Picker("Recipe source", selection: $model.mode) {
                    ForEach(RecipeDiscoveryMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text(model.mode == .online ? "Search RecipeTin Eats, Budget Bytes and Skinnytaste, with photos, ingredients and method filled in. Only recipes you keep join your library." : "Create three original recipes with Apple Intelligence on your device. You can edit every detail before keeping them.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !RecipeDiscoveryService.canUseAI {
                    Text("Apple Intelligence isn’t available on this device right now. Online keyword search still works.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button { promptFocused = false; model.search(in: store) } label: {
                    Label(model.mode == .online ? "Find my recipes" : "Make me a stack", systemImage: "sparkles").frame(maxWidth: .infinity)
                }.supperGlassButton(prominent: true).controlSize(.large)
                    .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.prompt.count > 600 || (model.mode == .create && !RecipeDiscoveryService.canUseAI))
                    .accessibilityIdentifier("findDiscoveryRecipes")
                if model.prompt.count > 600 { Text("Keep your request under 600 characters.").font(.footnote).foregroundStyle(.red) }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Need a little inspiration?").font(.headline)
                    ForEach(["A cosy one-pot dinner", "Quick chicken with a bit of spice", "Something fresh and vegetarian"], id: \.self) { idea in
                        Button { model.prompt = idea; promptFocused = false } label: {
                            Label(idea, systemImage: "arrow.up.left").frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.borderless).font(.subheadline)
                    }
                }
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
    }

    private var loading: some View {
        VStack(spacing: 22) {
            Image(systemName: "fork.knife.circle").font(.system(size: 70, weight: .light)).foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            ProgressView(model.progress).accessibilityIdentifier("discoveryProgress")
            Text(model.mode == .online ? "Checking the ingredients, finding the good stuff." : "A little inspiration is on its way.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Cancel") { model.cancel() }.supperGlassButton()
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.prompt).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("\(model.review.pending.count) to explore").foregroundStyle(.secondary)
                        Spacer()
                        Label("\(model.review.keptIDs.count) kept", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            .accessibilityIdentifier("discoveryKeptCount")
                    }.font(.subheadline).contentTransition(.numericText())
                    if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }
                if model.review.pending.isEmpty { finished }
                else if gridView { grid }
                else {
                    Text("Tap to explore. Swipe left to pass, right to keep.")
                        .font(.footnote).foregroundStyle(.secondary)
                    RecipeDiscoveryStack(suggestions: Array(model.review.pending.prefix(3)), isSwiping: $swipingRecipe, open: { path.append($0) }, keep: keep, discard: discard)
                    if !model.review.discardedIDs.isEmpty {
                        Button("Undo last discard", systemImage: "arrow.uturn.backward") { model.undoDiscard() }
                            .font(.subheadline).frame(maxWidth: .infinity).accessibilityIdentifier("undoDiscoveryDiscard")
                    }
                }
            }.padding(20).padding(.bottom, 24).frame(maxWidth: gridView ? 1000 : 600).frame(maxWidth: .infinity)
        }
        .scrollDisabled(swipingRecipe)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 24) {
            ForEach(model.review.pending) { suggestion in
                VStack(alignment: .leading, spacing: 12) {
                    Button { path.append(suggestion.id) } label: { RecipeCardView(recipe: suggestion.recipe) }.buttonStyle(.plain)
                    Text(suggestion.sourceLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    ViewThatFits(in: .horizontal) {
                        HStack { decisionButtons(suggestion) }
                        VStack(alignment: .leading) { decisionButtons(suggestion) }
                    }
                }.accessibilityIdentifier("discoveryGridCard-" + suggestion.recipe.title)
            }
        }.accessibilityIdentifier("discoveryGrid")
    }
    @ViewBuilder private func decisionButtons(_ suggestion: RecipeSuggestion) -> some View {
        Button("Discard", systemImage: "xmark") { discard(suggestion.id) }.supperGlassButton()
            .accessibilityLabel("Discard \(suggestion.recipe.title)")
        Button("Keep", systemImage: "checkmark") { _ = keep(suggestion) }.supperGlassButton(prominent: true)
            .accessibilityLabel("Keep \(suggestion.recipe.title)")
    }
    private var finished: some View {
        ContentUnavailableView {
            Label(model.review.keptIDs.isEmpty ? "Not quite your flavour?" : "Good taste.", systemImage: model.review.keptIDs.isEmpty ? "fork.knife" : "checkmark.seal")
        } description: {
            Text(model.review.keptIDs.isEmpty ? "Try another craving for a fresh stack of ideas." : "\(model.review.keptIDs.count) recipes are now in your shared library.")
        } actions: {
            Button("Find more ideas", systemImage: "sparkles") { model.startOver() }.supperGlassButton(prominent: true)
            if !model.review.discardedIDs.isEmpty { Button("Undo last discard", systemImage: "arrow.uturn.backward") { model.undoDiscard() } }
        }
    }
    private func keep(_ suggestion: RecipeSuggestion) -> Bool {
        let saved = model.keep(suggestion, in: store)
        if saved { feedback += 1 }
        return saved
    }
    private func discard(_ id: UUID) {
        withAnimation(reduceMotion ? nil : .snappy) { model.discard(id) }
    }
}

private struct RecipeDiscoveryStack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let suggestions: [RecipeSuggestion]
    @Binding var isSwiping: Bool
    let open: (UUID) -> Void
    let keep: (RecipeSuggestion) -> Bool
    let discard: (UUID) -> Void
    @State private var drag: CGSize = .zero
    @State private var horizontalDrag: Bool?
    @GestureState private var gestureActive = false

    private var decisionColor: Color { drag.width >= 0 ? .green : .red }
    private var decisionProgress: Double { min(Double(abs(drag.width) / 100), 1) }

    var body: some View {
        VStack(spacing: 28) {
            ZStack(alignment: .top) {
                ForEach(Array(suggestions.enumerated().reversed()), id: \.element.id) { index, suggestion in
                    card(suggestion, index: index)
                        .scaleEffect(1 - CGFloat(index) * 0.045, anchor: .bottom)
                        .rotationEffect(.degrees(reduceMotion ? 0 : (index == 0 ? Double(drag.width / 28) : Double(index == 1 ? -2 : 2))))
                        .offset(x: index == 0 ? drag.width : 0, y: CGFloat(index) * 12)
                        .zIndex(Double(3 - index))
                        .allowsHitTesting(index == 0)
                        .accessibilityHidden(index != 0)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 36)
                    .fill(decisionColor.opacity(decisionProgress * 0.25))
                    .padding(-10)
                    .allowsHitTesting(false)
            }
            .padding(.bottom, 24)
            if let top = suggestions.first {
                SupperGlassGroup {
                    HStack(spacing: 24) {
                        Button("Discard", systemImage: "xmark") { decide(top, keeping: false) }.supperGlassButton()
                            .accessibilityIdentifier("discardDiscoveryRecipe")
                        Button("Keep recipe", systemImage: "checkmark") { decide(top, keeping: true) }.supperGlassButton(prominent: true)
                            .accessibilityIdentifier("keepDiscoveryRecipe")
                    }.controlSize(.large)
                }
            }
        }
        // Measure from the stationary stack, never the translated/rotated card.
        .coordinateSpace(name: "discoverySwipeArea")
        .onChange(of: suggestions.first?.id) { _, _ in drag = .zero }
        .onChange(of: gestureActive) { _, active in
            if !active { resetDrag() }
        }
        .onDisappear { isSwiping = false }
    }

    private func card(_ suggestion: RecipeSuggestion, index: Int) -> some View {
        RecipeDiscoveryCardContent(recipe: suggestion.recipe, mode: suggestion.mode, sourceLabel: suggestion.sourceLabel)
            .equatable()
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 32).fill(SupperStyle.surface)
                RoundedRectangle(cornerRadius: 32)
                    .fill(decisionColor.opacity(index == 0 ? decisionProgress * 0.4 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 32)
                    .strokeBorder(decisionColor.opacity(index == 0 ? decisionProgress : 0), lineWidth: 3)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: drag.width >= 0 ? .topLeading : .topTrailing) {
                Label(drag.width >= 0 ? "KEEP" : "DISCARD", systemImage: drag.width >= 0 ? "checkmark" : "xmark")
                    .font(.title3.bold()).foregroundStyle(decisionColor)
                    .padding(12).background(.regularMaterial, in: .capsule).padding(28)
                    .opacity(index == 0 ? decisionProgress : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(suggestion.recipe.title)
            .accessibilityHint("Opens the full recipe. Swipe right to keep or left to discard.")
            .accessibilityIdentifier(index == 0 ? "discoveryTopCard" : "discoveryBackCard")
            .accessibilityAction { open(suggestion.id) }
            .accessibilityAction(named: "Keep recipe") { decide(suggestion, keeping: true) }
            .accessibilityAction(named: "Discard recipe") { decide(suggestion, keeping: false) }
            .simultaneousGesture(DragGesture(minimumDistance: 10, coordinateSpace: .named("discoverySwipeArea"))
                .updating($gestureActive) { _, active, _ in active = true }
                .onChanged { value in
                    // Lock the axis once and follow the finger without implicit animation.
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if horizontalDrag == nil {
                            horizontalDrag = abs(value.translation.width) > abs(value.translation.height)
                        }
                        if horizontalDrag == true {
                            if !isSwiping { isSwiping = true }
                            drag = CGSize(width: value.translation.width, height: 0)
                        }
                    }
                }
                .onEnded { value in
                    let sameDirection = value.translation.width * value.predictedEndTranslation.width > 0
                    let committed = abs(value.translation.width) > 100 || (abs(value.translation.width) > 45 && sameDirection && abs(value.predictedEndTranslation.width) > 220)
                    if horizontalDrag == true && committed { decide(suggestion, keeping: value.translation.width > 0) }
                    else { resetDrag() }
                }.exclusively(before: TapGesture().onEnded { open(suggestion.id) }))
    }
    private func resetDrag() {
        horizontalDrag = nil
        isSwiping = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { drag = .zero }
    }
    private func decide(_ suggestion: RecipeSuggestion, keeping: Bool) {
        horizontalDrag = nil
        isSwiping = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
            if keeping { _ = keep(suggestion) } else { discard(suggestion.id) }
            drag = .zero
        }
    }
}

/// Keep recipe/image rendering independent of per-frame drag and colour updates.
private struct RecipeDiscoveryCardContent: View, Equatable {
    let recipe: Recipe
    let mode: RecipeDiscoveryMode
    let sourceLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RecipeCardView(recipe: recipe)
            HStack(spacing: 6) {
                Image(systemName: mode == .online ? "globe" : "sparkles")
                Text(sourceLabel).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.right")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
