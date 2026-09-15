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
            .background {
                SupperStyle.canvas
                if !model.hasResults || model.busy { DiscoveryAtmosphere() }
            }
            .navigationTitle(model.hasResults && !model.busy ? "Fresh ideas" : "")
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
            } message: { Text("Recipes you kept are already saved. The remaining ideas will be discarded.") }
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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    DiscoveryKitchen(searching: false).frame(width: 180, height: 145)
                    Text("What are you\ncraving?")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold)).multilineTextAlignment(.center)
                    VStack(spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            TextField("A dish or a mood…", text: $model.prompt, axis: .vertical)
                                .lineLimit(1...4).font(.title3).multilineTextAlignment(.center)
                                .focused($promptFocused).accessibilityIdentifier("discoveryPrompt")
                                .accessibilityLabel("What are you craving?")
                            Button { promptFocused = false; model.search(in: store) } label: {
                                Image(systemName: "arrow.up").font(.headline).frame(minWidth: 24, minHeight: 28)
                            }.buttonStyle(.borderedProminent).tint(KitchenPalette.clay).buttonBorderShape(.circle).controlSize(.regular)
                                .accessibilityLabel("Find recipes").accessibilityIdentifier("findDiscoveryRecipes")
                                .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.prompt.count > 600 || !canSearch)
                        }
                        .padding(14).padding(.leading, 6).frame(minHeight: 84)
                        .supperGlassPanel()
                        .overlay {
                            RoundedRectangle(cornerRadius: 28)
                                .strokeBorder(KitchenPalette.honey.opacity(0.25), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                        if model.prompt.count > 600 { Text("600 characters max.").font(.caption).foregroundStyle(.red) }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { inspiration }
                            VStack(spacing: 10) { inspiration }
                        }
                    }
                    if !canSearch {
                        NavigationLink("Set up OpenAI", destination: AISettingsView()).font(.subheadline)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 28)
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("discoveryRequest")
        }
    }

    private var inspiration: some View {
        ForEach(Array(zip(["Cosy", "Quick", "Fresh"], ["A cosy one-pot dinner", "Quick chicken with a bit of spice", "Something fresh and vegetarian"])), id: \.0) { label, idea in
            Button { model.prompt = idea; promptFocused = false } label: { Text(label).font(.subheadline) }
                .supperGlassButton().accessibilityLabel(idea)
        }
    }

    private var loading: some View {
        VStack(spacing: 24) {
            DiscoveryKitchen(searching: true).frame(width: 280, height: 245)
            Text("Finding something\ngood.").font(.system(.largeTitle, design: .serif, weight: .semibold)).multilineTextAlignment(.center)
            Text(loadingLabel).font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("discoveryProgress").accessibilityValue(model.progress)
            Button("Cancel") { model.cancel() }.supperGlassButton().accessibilityIdentifier("cancelDiscoverySearch")
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingLabel: String {
        if model.progress.contains("photos") { return "Adding the finishing touches…" }
        if model.progress.contains("Checking") { return "Picking your matches…" }
        if model.progress.contains("Reading") { return "Reading the recipes…" }
        return "Searching the web…"
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

/// Warm window light and a little stovetop scene, separate from controls and layout.
private enum KitchenPalette {
    static let clay = Color(red: 0.68, green: 0.32, blue: 0.21)
    static let honey = Color(red: 0.85, green: 0.62, blue: 0.30)
    static let olive = Color(red: 0.40, green: 0.47, blue: 0.28)
    static let wood = Color(red: 0.49, green: 0.32, blue: 0.19)
}

private struct DiscoveryAtmosphere: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        RadialGradient(colors: [KitchenPalette.honey.opacity(colorScheme == .dark ? 0.12 : 0.13), .clear],
                       center: .init(x: 0.8, y: 0.3), startRadius: 10, endRadius: 440)
            .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct DiscoveryKitchen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let searching: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0.8 : timeline.date.timeIntervalSinceReferenceDate
                // Work in a small, fixed drawing space so every element scales together.
                let scale = min(size.width / 240, size.height / 210)
                context.translateBy(x: (size.width - 240 * scale) / 2, y: (size.height - 210 * scale) / 2)
                context.scaleBy(x: scale, y: scale)

                context.fill(Path(ellipseIn: CGRect(x: 45, y: 176, width: 150, height: 13)),
                             with: .color(KitchenPalette.wood.opacity(0.09)))
                // Steam rises, curls and fades without a jump at the loop boundary.
                for index in 0..<3 {
                    let phase = (t / (searching ? 2.8 : 4.5) + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    let x = 91.0 + Double(index) * 27
                    let y = 96 - phase * 66
                    var steam = Path()
                    steam.move(to: CGPoint(x: x, y: y + 18))
                    steam.addCurve(to: CGPoint(x: x + 5 * sin(phase * .pi * 2), y: y - 12),
                                   control1: CGPoint(x: x - 12, y: y + 6), control2: CGPoint(x: x + 13, y: y))
                    context.stroke(steam, with: .color(KitchenPalette.wood.opacity(sin(phase * .pi) * 0.36)),
                                   style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }

                // Enamel casserole, handles and a rounded base.
                for x in [43.0, 174.0] {
                    context.stroke(Path(roundedRect: CGRect(x: x, y: 119, width: 23, height: 18), cornerRadius: 8),
                                   with: .color(KitchenPalette.clay), lineWidth: 6)
                }
                var pot = Path()
                pot.move(to: CGPoint(x: 60, y: 112))
                pot.addLine(to: CGPoint(x: 66, y: 153))
                pot.addQuadCurve(to: CGPoint(x: 90, y: 175), control: CGPoint(x: 69, y: 175))
                pot.addLine(to: CGPoint(x: 150, y: 175))
                pot.addQuadCurve(to: CGPoint(x: 174, y: 153), control: CGPoint(x: 171, y: 175))
                pot.addLine(to: CGPoint(x: 180, y: 112))
                pot.closeSubpath()
                context.fill(pot, with: .linearGradient(Gradient(colors: [KitchenPalette.clay.opacity(0.78), KitchenPalette.clay]),
                                                       startPoint: CGPoint(x: 65, y: 110), endPoint: CGPoint(x: 175, y: 175)))
                context.fill(Path(ellipseIn: CGRect(x: 59, y: 99, width: 122, height: 32)), with: .color(KitchenPalette.clay))
                context.fill(Path(ellipseIn: CGRect(x: 65, y: 103, width: 110, height: 23)), with: .color(KitchenPalette.honey))
                context.stroke(Path(ellipseIn: CGRect(x: 59, y: 99, width: 122, height: 32)),
                               with: .color(KitchenPalette.clay.opacity(0.9)), lineWidth: 3)

                // Tiny bubbles and herbs follow the surface of the soup.
                for index in 0..<5 {
                    let phase = (t / 1.8 + Double(index) * 0.21).truncatingRemainder(dividingBy: 1)
                    let x = 83.0 + Double(index) * 18
                    let y = 111.0 + sin(Double(index) * 2) * 4
                    let radius = searching ? 1 + phase * 3 : 2
                    context.stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 1.2)),
                                   with: .color(.white.opacity(searching ? (1 - phase) * 0.65 : 0.3)), lineWidth: 1)
                    context.fill(Path(ellipseIn: CGRect(x: x + 3, y: y + 5, width: 5, height: 2)),
                                 with: .color(KitchenPalette.olive))
                }
                // The spoon traces an ellipse, visibly stirring rather than spinning.
                let stirring = searching ? t * 2.2 : 0.5
                let tip = CGPoint(x: 126 + sin(stirring) * 21, y: 114 + cos(stirring) * 4)
                let handle = CGPoint(x: 154 + sin(stirring) * 9, y: 62 + cos(stirring) * 3)
                var spoon = Path()
                spoon.move(to: handle); spoon.addLine(to: tip)
                context.stroke(spoon, with: .color(KitchenPalette.wood), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 6, y: tip.y - 4, width: 12, height: 8)),
                             with: .color(KitchenPalette.wood))
                var shine = Path()
                shine.move(to: CGPoint(x: 76, y: 139)); shine.addQuadCurve(to: CGPoint(x: 90, y: 163), control: CGPoint(x: 77, y: 160))
                context.stroke(shine, with: .color(.white.opacity(0.24)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
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
