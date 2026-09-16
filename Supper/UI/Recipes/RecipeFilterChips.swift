import SwiftUI

struct RecipeFilterChips: View {
    @EnvironmentObject private var store: RecipeStore
    @Binding var filter: RecipeFilter
    var scope: RecipeBrowseScope = .all
    @State private var showingTags = false
    @ScaledMetric(relativeTo: .subheadline) private var labelHeight: CGFloat = 22
    private var allTags: [String] { Array(Set(store.recipes.filter { scope.includes($0) }.flatMap(\.tags))).sorted() }
    private var collections: [RecipeCollection] {
        store.collections.filter { $0.id != RecipeCollection.exploreID || scope == .all }
    }
    var body: some View {
        HStack(spacing: 0) {
            if filter.isActive {
                Button { filter = RecipeFilter() } label: {
                    Image(systemName: "xmark").frame(width: labelHeight, height: labelHeight)
                }
                .supperGlassButton()
                .foregroundStyle(.primary)
                .accessibilityLabel("Clear filters")
                .accessibilityIdentifier("clearFilters")
                .padding(.leading, 20).padding(.trailing, 8)
                .transition(.opacity)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SupperStyle.chipSpacing) {
                    Menu {
                        Section("Match all selected collections") {
                            ForEach(collections) { collection in
                                Toggle(collection.name, isOn: Binding(get: { filter.collectionIDs.contains(collection.id) }, set: { on in if on { filter.collectionIDs.insert(collection.id) } else { filter.collectionIDs.remove(collection.id) } }))
                            }
                        }
                        Button("Clear collections") { filter.collectionIDs = [] }
                    } label: { chipLabel(filter.collectionIDs.isEmpty ? "Collections" : "Collections · \(filter.collectionIDs.count)", systemImage: "folder") }.filterChip(active: !filter.collectionIDs.isEmpty, identifier: "collectionsFilter").disabled(collections.isEmpty)
                    Menu {
                        Picker("Maximum duration", selection: $filter.maximumMinutes) {
                            Text("Any duration").tag(Optional<Int>.none)
                            ForEach([15, 30, 45, 60, 90], id: \.self) { Text("Up to \($0) min").tag(Optional($0)) }
                        }
                    } label: { chipLabel(filter.maximumMinutes.map { "≤ \($0) min" } ?? "Duration", systemImage: "clock") }.filterChip(active: filter.maximumMinutes != nil, identifier: "durationFilter")
                    Menu {
                        Section("Match all selected tags") {
                            ForEach(allTags, id: \.self) { tag in
                                Toggle(tag, isOn: Binding(get: { filter.tags.contains(tag) }, set: { on in if on { filter.tags.insert(tag) } else { filter.tags.remove(tag) } }))
                            }
                        }
                        Button("Clear tags") { filter.tags = [] }
                        Button("Manage tags…", systemImage: "tag") { showingTags = true }
                    } label: { chipLabel(filter.tags.isEmpty ? "Tags" : "Tags · \(filter.tags.count)", systemImage: "tag") }.filterChip(active: !filter.tags.isEmpty, identifier: "tagsFilter")

                    Menu {
                        Picker("Reactions", selection: $filter.reaction) { ForEach(RecipeFilter.ReactionFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    } label: { chipLabel(filter.reaction == .any ? "Reactions" : filter.reaction.rawValue, systemImage: "face.smiling") }.filterChip(active: filter.reaction != .any, identifier: "reactionFilter")
                }
            }
            // Inset the content, not the viewport: chips travel to the screen edge.
            .contentMargins(.leading, filter.isActive ? 0 : 20, for: .scrollContent)
            .contentMargins(.trailing, 20, for: .scrollContent)
            .accessibilityIdentifier("filterScrollView")
        }
        .font(.subheadline).controlSize(.small)
        .sheet(isPresented: $showingTags) { TagsView() }
    }

    private func chipLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .fixedSize().frame(height: labelHeight)
            .contentTransition(.numericText())
    }
}

private extension View {
    func filterChip(active: Bool, identifier: String) -> some View {
        supperGlassButton(prominent: active)
            .tint(active ? Color(uiColor: .systemBlue) : Color.primary)
            .foregroundStyle(active ? Color.white : Color.primary)
            .accessibilityIdentifier(identifier)
            .accessibilityValue(active ? "Active" : "Not active")
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}
