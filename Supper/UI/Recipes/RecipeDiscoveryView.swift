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
        busy = true; error = nil; progress = "Searching for recipes…"
        task = Task {
            defer { if requestID == token { busy = false; task = nil } }
            do {
                let result: RecipeDiscoveryResult
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--discovery-ui-testing") {
                    if ProcessInfo.processInfo.arguments.contains("--discovery-loading-ui-testing") {
                        try await Task.sleep(for: .seconds(30))
                    }
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
                try store.saveToExplore(suggestion.recipe)
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
                steps: [RecipeStep(text: "Prepare the ingredients."), RecipeStep(text: "Cook and serve.", order: 1)]), mode: .online)
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
    @ObservedObject private var aiSettings = OpenAISettings.shared
    private var canSearch: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--discovery-ui-testing") { return true }
        #endif
        return aiSettings.isConfigured
    }
    @AppStorage("discoveryGridView") private var gridView = false
    @State private var path: [UUID] = []
    @State private var showingStartOver = false
    @State private var feedback = 0
    @State private var swipingRecipe = false
    @State private var showingSourceInfo = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.busy { loading }
                else if model.hasResults { results }
                else { requestForm }
            }
            .background(SupperStyle.canvas)
            .navigationTitle(model.hasResults && !model.busy ? "Recipes to try" : "Find Recipes")
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
                            Button("New request", systemImage: "magnifyingglass") {
                                if model.review.pending.isEmpty { model.startOver() } else { showingStartOver = true }
                            }
                            Button("Undo last discard", systemImage: "arrow.uturn.backward") { model.undoDiscard() }
                                .disabled(model.review.discardedIDs.isEmpty)
                            Button("About these recipes", systemImage: "info.circle") { showingSourceInfo = true }
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
            } message: { Text("Recipes you kept are saved in Explore. The remaining ideas will be discarded.") }
            .supperError($model.error, title: "Couldn’t finish that")
            .alert("From the web", isPresented: $showingSourceInfo) {
                Button("OK", role: .cancel) { }
            } message: { Text(model.notice ?? "Published recipes, with a source link on each card. Only recipes you keep are saved.") }
            .sensoryFeedback(.success, trigger: feedback)
        }
        .presentationDragIndicator(.visible)
        .onDisappear { model.cancel() }
    }

    private var requestForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DiscoveryFoodScene(searching: false)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 150 : 210)
                VStack(alignment: .leading, spacing: 12) {
                    Text("What are you craving?")
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Something comforting. Something fresh. Something you haven’t tried yet.")
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Chicken, a little spice, ready in 30 minutes…", text: $model.prompt, axis: .vertical)
                        .lineLimit(3...8).focused($promptFocused)
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .supperGlassPanel()
                        .accessibilityIdentifier("discoveryPrompt")
                        .accessibilityLabel("What are you craving?")
                    if model.prompt.count > 600 {
                        Text("Keep your request under 600 characters.").font(.footnote).foregroundStyle(.red)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("A little inspiration").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    inspiration
                }
                if !canSearch {
                    NavigationLink("Set up OpenAI", destination: AISettingsView())
                    Text("Connect your account to find recipes.").font(.footnote).foregroundStyle(.secondary)
                }
                Text("Find published recipes, then save the ones you want to try to Explore.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background { DiscoveryAtmosphere() }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("discoveryRequest")
        .safeAreaInset(edge: .bottom) {
            Button {
                promptFocused = false
                model.search(in: store)
            } label: {
                Label("Find recipes", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
            }
            .supperGlassButton(prominent: true).controlSize(.large)
            .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.prompt.count > 600 || !canSearch)
            .accessibilityIdentifier("findDiscoveryRecipes")
            .frame(maxWidth: 572).padding(.horizontal, 24).padding(.vertical, 12)
        }
    }

    private var inspiration: some View {
        VStack(spacing: 8) {
            ForEach(["A cosy one-pot dinner", "Quick chicken with a bit of spice", "Something fresh and vegetarian"], id: \.self) { idea in
                Button { model.prompt = idea; promptFocused = false } label: {
                    HStack(spacing: 12) {
                        Text(idea).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5).foregroundStyle(.primary)
                }
                .supperGlassButton().controlSize(.regular)
            }
        }
    }

    private var loading: some View {
        ScrollView {
            VStack(spacing: 28) {
                DiscoveryFoodScene(searching: true).frame(height: 260)
                VStack(spacing: 12) {
                    Text("A little kitchen inspiration")
                        .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    Text(model.progress).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.progress)
                        .accessibilityIdentifier("discoveryProgress")
                    ProgressView().padding(.top, 4).accessibilityLabel("Finding recipes")
                }
                Button("Cancel") { model.cancel() }
                    .supperGlassButton().accessibilityIdentifier("cancelDiscoverySearch")
            }
            .padding(28).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background { DiscoveryAtmosphere() }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("\(model.review.pending.count) to try").foregroundStyle(.secondary)
                    Spacer()
                    Label("\(model.review.keptIDs.count) kept", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityIdentifier("discoveryKeptCount")
                }.font(.subheadline).contentTransition(.numericText())
                if model.review.pending.isEmpty { finished }
                else if gridView { grid }
                else {
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
            Text(model.review.keptIDs.isEmpty ? "Try another craving to find something you'll love." : "Your recipes are saved in Explore, ready to try. Move your favourites to My Recipes whenever you like.")
        } actions: {
            Button("Find more recipes", systemImage: "magnifyingglass") { model.startOver() }.supperGlassButton(prominent: true)
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
    @State private var keepingDirection = true
    @GestureState private var gestureActive = false

    private var decisionColor: Color { keepingDirection ? .green : .red }
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
            .padding(.bottom, 24)
            if let top = suggestions.first {
                SupperGlassGroup {
                    HStack(spacing: 24) {
                        Button("Discard", systemImage: "xmark") { decide(top, keeping: false) }.supperGlassButton()
                            .accessibilityIdentifier("discardDiscoveryRecipe")
                        Button("Keep recipe", systemImage: "checkmark") { decide(top, keeping: true) }.supperGlassButton(prominent: true)
                            .accessibilityIdentifier("keepDiscoveryRecipe")
                    }.labelStyle(.iconOnly).buttonBorderShape(.circle).controlSize(.large)
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
            .overlay(alignment: keepingDirection ? .topLeading : .topTrailing) {
                Label(keepingDirection ? "KEEP" : "DISCARD", systemImage: keepingDirection ? "checkmark" : "xmark")
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
                            if value.translation.width != 0 { keepingDirection = value.translation.width > 0 }
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


/// Decorative photography is bundled for offline use and never represents a search result.
private struct DiscoveryFoodScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let searching: Bool
    @State private var began = Date()
    private static let photos: [UIImage] = {
        guard let image = UIImage(named: "DiscoveryFood")?.cgImage else { return [] }
        let side = min(image.width / 3, image.height)
        return (0..<3).compactMap { index in
            image.cropping(to: CGRect(x: index * image.width / 3, y: (image.height - side) / 2, width: side, height: side)).map { UIImage(cgImage: $0) }
        }
    }()

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSince(began)
                let width = min(geometry.size.width, 560)
                ZStack {
                    ForEach(Self.photos.indices, id: \.self) { index in
                        let phase = Double(index) * 2.1
                        let motion = reduceMotion ? 0 : sin(time * (searching ? 0.7 : 0.45) + phase)
                        let size = width * (index == 1 ? 0.44 : 0.32)
                        Image(uiImage: Self.photos[index])
                            .resizable().scaledToFill()
                            .frame(width: size, height: size).clipShape(.circle)
                            .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                            .shadow(color: Color(red: 0.24, green: 0.18, blue: 0.08).opacity(0.18), radius: 18, y: 12)
                            .rotationEffect(.degrees(Double(index - 1) * 9 + motion * 2))
                            .offset(x: CGFloat(index - 1) * width * 0.31,
                                    y: CGFloat(index == 1 ? 16 : -20) + CGFloat(motion) * (searching ? 12 : 7))
                            .zIndex(index == 1 ? 2 : 1)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct DiscoveryAtmosphere: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                SupperStyle.canvas
                if !reduceTransparency {
                    Ellipse().fill(Color(red: 0.80, green: 0.52, blue: 0.20).opacity(colorScheme == .dark ? 0.19 : 0.16))
                        .frame(width: geometry.size.width * 0.95, height: 310)
                        .blur(radius: 65).offset(x: -70, y: -60)
                    Ellipse().fill(Color(red: 0.43, green: 0.51, blue: 0.25).opacity(colorScheme == .dark ? 0.17 : 0.12))
                        .frame(width: geometry.size.width * 0.7, height: 240)
                        .blur(radius: 60).offset(x: 120, y: 170)
                }
            }
        }
        .clipped().ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
