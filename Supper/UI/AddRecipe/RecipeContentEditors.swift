import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    static let supperRecipeContent = UTType(exportedAs: "app.supper.recipe-content", conformingTo: .data)
}
private struct RecipeContentDrag: Codable {
    let editorID: UUID
    let section: String?
    let itemID: UUID?
}

/// Native List insertion handles row positioning; headers accept whole sections or rows.
private struct RecipeSectionsEditor<Item: RecipeSectionItem, Row: View>: View {
    @Binding var content: RecipeSectionedContent<Item>
    let defaultTitle: String
    let itemName: String
    let add: (String) -> Void
    let edit: (Item) -> Void
    @ViewBuilder let row: (Item, Int) -> Row
    @State private var editorID = UUID()
    @State private var dropTarget: String?
    @State private var namingSection = false
    @State private var renamedSection: String?
    @State private var sectionName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ForEach(content.sections) { section in
            Section {
                ForEach(section.items) { item in
                    Button { edit(itemInSection(item, title: section.title)) } label: {
                        HStack(spacing: 12) {
                            row(item, content.flattened.firstIndex(where: { $0.id == item.id }) ?? 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }.contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .onDrag { provider(section: nil, itemID: item.id) }
                    .contextMenu {
                        Menu("Move to section", systemImage: "folder") {
                            ForEach(content.sections) { destination in
                                Button(destination.title.isEmpty ? defaultTitle : destination.title) {
                                    _ = content.moveItem(item.id, to: destination.title)
                                }.disabled(destination.id == section.id)
                            }
                        }
                        Button("Delete \(itemName)", systemImage: "trash", role: .destructive) {
                            delete([item.id], from: section.title)
                        }
                    }
                }
                .onDelete { offsets in delete(offsets.map { section.items[$0].id }, from: section.title) }
                .onMove { offsets, destination in
                    guard let index = content.sections.firstIndex(where: { $0.id == section.id }) else { return }
                    content.sections[index].items.move(fromOffsets: offsets, toOffset: destination)
                }
                .onInsert(of: [.supperRecipeContent]) { offset, providers in
                    let next = section.items.indices.contains(offset) ? section.items[offset].id : nil
                    _ = receive(providers, section: section.title, before: next)
                }
                if section.items.isEmpty {
                    Text("Drop \(itemName == "ingredient" ? "ingredients" : "steps") here or tap +")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                        .onDrop(of: [.supperRecipeContent], isTargeted: target(section.id)) {
                            receive($0, section: section.title)
                        }
                }
            } header: {
                HStack(spacing: 12) {
                    Text(section.title.isEmpty ? defaultTitle : section.title)
                        .font(.headline).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .onDrag { provider(section: section.title, itemID: nil) }
                        .accessibilityHint("Drag to reorder this section")
                    Menu("Section options", systemImage: "ellipsis") {
                        Button("Rename section", systemImage: "pencil") {
                            renamedSection = section.title; sectionName = section.title; namingSection = true
                        }
                        Button("Move section to top", systemImage: "arrow.up.to.line") {
                            _ = content.moveSection(section.title, before: content.sections.first?.title)
                        }.disabled(content.sections.first?.id == section.id)
                        Button("Move section to bottom", systemImage: "arrow.down.to.line") {
                            _ = content.moveSection(section.title, before: nil)
                        }.disabled(content.sections.last?.id == section.id)
                        if section.items.isEmpty && content.sections.count > 1 {
                            Button("Delete empty section", systemImage: "trash", role: .destructive) {
                                content.sections.removeAll { $0.id == section.id }
                            }
                        }
                    }.accessibilityLabel("Options for \(section.title.isEmpty ? defaultTitle : section.title)")
                    Button { add(section.title) } label: {
                        Image(systemName: "plus").font(.body.weight(.semibold)).frame(minWidth: 32, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Add \(itemName) to \(section.title.isEmpty ? defaultTitle : section.title)")
                    .accessibilityIdentifier((itemName == "ingredient" ? "addIngredient" : "addMethodStep") + (content.sections.first?.id == section.id ? "" : "-" + section.title))
                }
                .textCase(nil)
                .background(dropTarget == section.id ? Color(uiColor: .systemBlue).opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
                .contentShape(.rect)
                .onDrop(of: [.supperRecipeContent], isTargeted: target(section.id)) {
                    receive($0, section: section.title)
                }
                .accessibilityIdentifier("recipeSection-" + (section.title.isEmpty ? defaultTitle : section.title))
            }
        }
        Section {
            Button("Add section", systemImage: "plus") {
                renamedSection = nil; sectionName = ""; namingSection = true
            }
            .accessibilityIdentifier("addRecipeSection")
            .onDrop(of: [.supperRecipeContent], isTargeted: nil) { receive($0, section: nil) }
        } footer: {
            Text("Drag rows between sections. Drag a section heading to move its contents together. Edit lets you reorder or remove rows.")
        }
        .alert(renamedSection == nil ? "New Section" : "Rename Section", isPresented: $namingSection) {
            TextField("Section name", text: $sectionName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let renamedSection { _ = content.renameSection(renamedSection, to: sectionName) }
                else { _ = content.addSection(sectionName) }
            }.disabled(!canSaveName)
        } message: { Text("For example, Sauce, Dough or To serve.") }
    }

    private var canSaveName: Bool {
        let name = sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !content.sections.contains { $0.title != renamedSection && $0.title.caseInsensitiveCompare(name) == .orderedSame }
    }
    private func itemInSection(_ item: Item, title: String) -> Item { var item = item; item.group = title; return item }
    private func delete(_ ids: [UUID], from title: String) {
        guard let index = content.sections.firstIndex(where: { $0.title == title }) else { return }
        content.sections[index].items.removeAll { ids.contains($0.id) }
    }
    private func target(_ id: String) -> Binding<Bool> {
        Binding(get: { dropTarget == id }, set: { active in
            if active { dropTarget = id } else if dropTarget == id { dropTarget = nil }
        })
    }
    private func provider(section: String?, itemID: UUID?) -> NSItemProvider {
        let payload = RecipeContentDrag(editorID: editorID, section: section, itemID: itemID)
        guard let data = try? JSONEncoder().encode(payload) else { return NSItemProvider() }
        return NSItemProvider(item: data as NSData, typeIdentifier: UTType.supperRecipeContent.identifier)
    }
    private func receive(_ providers: [NSItemProvider], section: String?, before itemID: UUID? = nil) -> Bool {
        guard providers.count == 1, let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.supperRecipeContent.identifier) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.supperRecipeContent.identifier) { data, _ in
            Task { @MainActor in
                guard let data, let payload = try? JSONDecoder().decode(RecipeContentDrag.self, from: data), payload.editorID == editorID else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    if let title = payload.section {
                        var next = section
                        if let source = content.sections.firstIndex(where: { $0.title == title }),
                           let destination = content.sections.firstIndex(where: { $0.title == section }), source < destination {
                            next = content.sections.indices.contains(destination + 1) ? content.sections[destination + 1].title : nil
                        }
                        _ = content.moveSection(title, before: next)
                    } else if let id = payload.itemID, let section { _ = content.moveItem(id, to: section, before: itemID) }
                    dropTarget = nil
                }
            }
        }
        return true
    }
}

struct IngredientListEditor: View {
    @Binding var content: RecipeSectionedContent<Ingredient>
    let availableSections: [String]
    let sourceURL: URL?
    var onEditingChange: (Bool) -> Void = { _ in }
    @State private var editing: Ingredient?
    @State private var recoveringSections = false
    @State private var formatting = false
    private var ingredients: Binding<[Ingredient]> {
        Binding(get: { content.flattened }, set: { content.replaceItems($0) })
    }
    var body: some View {
        List {
            RecipeSectionsEditor(content: $content, defaultTitle: "Ingredients", itemName: "ingredient", add: {
                editing = Ingredient(name: "", group: $0)
            }, edit: { editing = $0 }) { ingredient, _ in IngredientLabel(ingredient: ingredient) }
            if let sourceURL, ["https", "http"].contains(sourceURL.scheme ?? ""), !content.flattened.isEmpty {
                Section {
                    Button("Recover sections from source", systemImage: "arrow.triangle.2.circlepath") { recoveringSections = true }
                } footer: { Text("Review the source’s ingredient sections before applying them. Your names and amounts stay the same.") }
            }
        }
        .scrollContentBackground(.hidden).background(SupperStyle.canvas)
        .navigationTitle("Ingredients").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Auto format", systemImage: "sparkles") { formatting = true }
                    .font(.subheadline).disabled(content.flattened.isEmpty)
                    .accessibilityIdentifier("autoFormatIngredients")
            }
            ToolbarItem(placement: .primaryAction) { EditButton().disabled(content.flattened.isEmpty) }
        }
        .onChange(of: editing?.id) { _, value in onEditingChange(value != nil) }
        .navigationDestination(item: $editing) { ingredient in
            IngredientEditor(ingredient: ingredient, isNew: !content.flattened.contains { $0.id == ingredient.id },
                             availableSections: sectionNames) { content.save($0, in: $0.group) }
        }
        .sheet(isPresented: $recoveringSections) { GroupRecoveryView(ingredients: ingredients, sourceURL: sourceURL) }
        .sheet(isPresented: $formatting) { IngredientFormattingView(ingredients: ingredients) }
    }
    private var sectionNames: [String] { content.sections.map(\.title) + availableSections }
}

/// A section is selected from the recipe, with free text only when creating a new one.
private struct RecipeSectionPicker: View {
    @Binding var selection: String
    let available: [String]
    @State private var adding = false
    @State private var name = ""
    private var names: [String] {
        var seen = Set<String>()
        return ([""] + available + [selection]).filter { seen.insert($0.lowercased()).inserted }
    }
    var body: some View {
        Section("Section") {
            Picker("Section", selection: $selection) {
                ForEach(names, id: \.self) { Text($0.isEmpty ? "Main section" : $0).tag($0) }
            }
            .accessibilityIdentifier("recipeSectionPicker")
            Button("Add section", systemImage: "plus") { name = ""; adding = true }
        }
        .alert("New Section", isPresented: $adding) {
            TextField("Section name", text: $name)
            Button("Cancel", role: .cancel) { }
            Button("Add") {
                let clean = name.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                selection = names.first(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) ?? clean
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct IngredientEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var ingredient: Ingredient
    let isNew: Bool
    let availableSections: [String]
    let apply: (Ingredient) -> Void
    var body: some View {
        Form {
            Section("Ingredient name") {
                TextField("e.g. olive oil", text: $ingredient.name, axis: .vertical)
                    .accessibilityIdentifier("ingredientName")
            }
            Section {
                LabeledContent("Quantity") {
                    TextField("e.g. 1½", text: $ingredient.quantity).multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("ingredientQuantity")
                }
                LabeledContent("Unit") {
                    TextField("e.g. tbsp", text: $ingredient.unit).multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("ingredientUnit")
                }
            } header: { Text("Amount · optional") } footer: { Text("Fractions, ranges and amounts such as “to taste” are welcome.") }
            RecipeSectionPicker(selection: $ingredient.group, available: availableSections)
            Section {
                Picker("Category", selection: $ingredient.categoryOverride) {
                    Text("Automatic").tag(Optional<GroceryAisle>.none)
                    ForEach(GroceryAisle.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
            } header: { Text("Shopping category") } footer: {
                Text("Automatic suggestion: \(IngredientPresentation.matching(ingredient.name).aisle.rawValue). Choose a category to override it in Groceries.")
            }
        }
        .scrollContentBackground(.hidden).background(SupperStyle.canvas)
        .navigationTitle(isNew ? "Add Ingredient" : "Edit Ingredient").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Done") {
                    ingredient.name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    ingredient.quantity = ingredient.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
                    ingredient.unit = ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines)
                    apply(ingredient); dismiss()
                }.disabled(ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveIngredient")
            }
        }
    }
}

struct MethodListEditor: View {
    @Binding var content: RecipeSectionedContent<RecipeStep>
    let availableSections: [String]
    var onEditingChange: (Bool) -> Void = { _ in }
    @State private var editing: RecipeStep?
    var body: some View {
        List {
            RecipeSectionsEditor(content: $content, defaultTitle: "Method", itemName: "step", add: {
                editing = RecipeStep(text: "", group: $0)
            }, edit: { editing = $0 }) { step, index in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step \(index + 1)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text(step.text).font(.body).foregroundStyle(.primary).lineLimit(3)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }
        }
        .scrollContentBackground(.hidden).background(SupperStyle.canvas)
        .navigationTitle("Method").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton().disabled(content.flattened.isEmpty) } }
        .onChange(of: editing?.id) { _, value in onEditingChange(value != nil) }
        .navigationDestination(item: $editing) { step in
            MethodStepEditor(step: step, isNew: !content.flattened.contains { $0.id == step.id },
                             availableSections: content.sections.map(\.title) + availableSections) { content.save($0, in: $0.group) }
        }
    }
}
private struct MethodStepEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var step: RecipeStep
    let isNew: Bool
    let availableSections: [String]
    let apply: (RecipeStep) -> Void
    var body: some View {
        Form {
            Section("Instructions") {
                TextField("What happens in this step?", text: $step.text, axis: .vertical).lineLimit(4...30)
                    .accessibilityIdentifier("methodStepText")
            }
            RecipeSectionPicker(selection: $step.group, available: availableSections)
        }
        .navigationTitle(isNew ? "Add Step" : "Edit Step").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Done") {
                    step.text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    apply(step); dismiss()
                }.disabled(step.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveMethodStep")
            }
        }
    }
}

struct DraftCollectionsEditor: View {
    @EnvironmentObject private var store: RecipeStore
    @Binding var selected: Set<UUID>
    var body: some View {
        List {
            if store.collections.isEmpty { Text("Open Collections on the Recipes screen to create a collection.").foregroundStyle(.secondary) }
            ForEach(store.collections) { collection in
                Toggle(collection.name, isOn: Binding(get: { selected.contains(collection.id) }, set: { on in
                    if on { selected.insert(collection.id) } else { selected.remove(collection.id) }
                }))
            }
        }.navigationTitle("Collections").navigationBarTitleDisplayMode(.inline)
    }
}

struct RecipeTagsEditor: View {
    @Binding var tagsText: String
    let draft: RecipeDraft
    var title = "Tags"
    @State private var suggestions: [String] = []
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("e.g. Easy, Dinner, Vegetarian", text: $tagsText, axis: .vertical).lineLimit(2...6)
                    .accessibilityIdentifier("recipeTagsText")
            } header: { Text("Tags") } footer: { Text("Separate tags with commas. Use them to find recipes in Search.") }
            Section {
                if busy {
                    ProgressView("Suggesting tags…")
                    Button("Cancel suggestions") { task?.cancel(); busy = false }
                } else { Button("Suggest tags", systemImage: "sparkles", action: suggest) }
                ForEach(suggestions, id: \.self) { tag in
                    Button("Add “\(tag)”", systemImage: "plus.circle") {
                        tagsText = tagsText.trimmingCharacters(in: .whitespacesAndNewlines)
                        tagsText += tagsText.isEmpty ? tag : ", " + tag
                        suggestions.removeAll { $0 == tag }
                    }
                }
            }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .onDisappear { task?.cancel() }.supperError($error, title: "Tag suggestions")
    }
    private func suggest() {
        task?.cancel(); busy = true
        task = Task {
            defer { busy = false }
            do {
                let existing = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                let values = try await OnDeviceRecipeAssistant().suggestTags(for: draft)
                try Task.checkCancellation()
                suggestions = values.filter { !existing.contains($0.lowercased()) }
                if suggestions.isEmpty { error = "No additional tags suggested. You can enter your own tags above." }
            } catch { if !(error is CancellationError) { self.error = "\(error.localizedDescription) You can still enter tags manually." } }
        }
    }
}
