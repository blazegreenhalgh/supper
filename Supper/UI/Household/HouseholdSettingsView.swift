import SwiftUI
import CloudKit
import CoreData

struct HouseholdSettingsView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @State private var presentation: SharePresentation?
    @State private var task: Task<Void, Never>?
    @State private var libraryToRemove: HouseholdSummary?
    @State private var showingRemovalConfirmation = false
    @State private var copiedDiagnostics = false
    private var isBusy: Bool {
        store.shareProgress != nil || store.checkingCloudAccount || store.removingHouseholdID != nil || store.joiningHousehold
    }
    private var uniqueMembers: [HouseholdMember] {
        store.members.filter { ReactionIdentity.canonical($0.id, members: store.members) == $0.id }.sorted { $0.name < $1.name }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Your identity") {
                    TextField("Display name", text: $name)
                    Button("Save name") { do { try store.renameMember(name) } catch { self.error = error.localizedDescription } }
                }
                Section("Household members") {
                    ForEach(uniqueMembers) { member in
                        LabeledContent(member.name, value: member.id == store.currentMemberID ? "You" : "Member")
                    }
                    if store.recipes.contains(where: { $0.reactions.contains(where: { $0.personID == "me" || $0.personID.isEmpty }) }) {
                        Text("Older reactions without a known author are labelled Previous member.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Household sharing") {
                    if let progress = store.shareProgress { ProgressView(progress); Button("Cancel", role: .cancel) { task?.cancel() } }
                    else { Button("Invite or manage sharing", systemImage: "person.2.badge.plus", action: prepareShare).disabled(isBusy) }
                    if store.joiningHousehold { ProgressView("Downloading invited household…") }
                    if let message = store.sharingMessage { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                    if let message = store.cloudMessage { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                    if store.checkingCloudAccount {
                        ProgressView("Checking iCloud account…")
                    } else if let message = store.cloudAccountMessage {
                        Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("iCloud account result")
                    }
                    Button("Check iCloud", systemImage: "icloud") {
                        task = Task { await store.checkCloudAccount() }
                    }.disabled(isBusy)
                    if let diagnostics = store.cloudDiagnostics {
                        Button(copiedDiagnostics ? "Copied diagnostics" : "Copy iCloud diagnostics", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = diagnostics
                            copiedDiagnostics = true
                        }
                    }
                }
                Section {
                    ForEach(store.households) { household in
                        HStack {
                            Button {
                                do { try store.selectHousehold(household.id); name = store.currentMemberName }
                                catch { self.error = error.localizedDescription }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(household.name)
                                        Text(household.incoming ? "Shared with you" : "Your library").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if household.id == store.activeHouseholdID { Image(systemName: "checkmark") }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if store.removingHouseholdID == household.id {
                                ProgressView().accessibilityLabel(household.incoming ? "Leaving library" : "Deleting library")
                            } else {
                                Menu {
                                    Button(household.incoming ? "Leave library" : "Delete library", systemImage: household.incoming ? "rectangle.portrait.and.arrow.right" : "trash", role: .destructive) {
                                        confirmRemoval(household)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").padding(.vertical, 8)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Library options for \(household.name)")
                            }
                        }
                        .disabled(isBusy)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(household.incoming ? "Leave" : "Delete", systemImage: household.incoming ? "rectangle.portrait.and.arrow.right" : "trash", role: .destructive) {
                                confirmRemoval(household)
                            }.disabled(isBusy)
                        }
                    }
                } header: { Text("Libraries") } footer: {
                    Text("Tap a library to switch. Use its menu or swipe left to delete a library you own or leave one shared with you.")
                }
            }.navigationTitle("Household").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { task?.cancel(); dismiss() }.disabled(store.removingHouseholdID != nil) } }
                .interactiveDismissDisabled(store.removingHouseholdID != nil)
                .confirmationDialog(removalTitle, isPresented: $showingRemovalConfirmation, titleVisibility: .visible, presenting: libraryToRemove) { household in
                    Button(household.incoming ? "Leave library" : "Delete library", role: .destructive) { remove(household) }
                    Button("Cancel", role: .cancel) { libraryToRemove = nil }
                } message: { household in
                    Text(removalMessage(household))
                }
                .onAppear { name = store.currentMemberName }
                .onDisappear { task?.cancel() }
                .sheet(item: $presentation) { NativeCloudSharingView(presentation: $0, store: store) { error = $0; presentation = nil } }
                .supperError($error, title: "Couldn't update household")
        }
    }
    private var removalTitle: String {
        guard let household = libraryToRemove else { return "Remove library?" }
        return "\(household.incoming ? "Leave" : "Delete") “\(household.name)”?"
    }
    private func removalMessage(_ household: HouseholdSummary) -> String {
        var message = household.incoming
            ? "This removes the library from your account. Its owner and other members keep their recipes and groceries. You’ll need a new invitation to rejoin."
            : "This permanently deletes this library and its recipes, collections and groceries from your iCloud account and everyone it’s shared with. This can’t be undone."
        if store.households.count == 1 {
            message += " A new empty library will be created so you can keep using Supper."
        }
        return message
    }
    private func confirmRemoval(_ household: HouseholdSummary) {
        libraryToRemove = household
        showingRemovalConfirmation = true
    }
    private func remove(_ household: HouseholdSummary) {
        libraryToRemove = nil
        Task {
            do { try await store.removeHousehold(household.id); name = store.currentMemberName }
            catch { self.error = CloudProblem.message(error) }
        }
    }
    private func prepareShare() {
        task = Task {
            do {
                let share = try await store.prepareShare(); try Task.checkCancellation()
                guard let persistentStore = store.library?.objectID.persistentStore else { throw SupperError.invalid("Reopen Household and try again.") }
                presentation = SharePresentation(share: share, persistentStore: persistentStore, title: store.activeHousehold?.name ?? "Our Supper")
            } catch { if !(error is CancellationError) { self.error = CloudProblem.message(error) } }
        }
    }
}
struct SharePresentation: Identifiable {
    let id = UUID()
    var share: CKShare
    var persistentStore: NSPersistentStore
    var title: String
}
private struct NativeCloudSharingView: UIViewControllerRepresentable {
    let presentation: SharePresentation
    let store: RecipeStore
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(presentation: presentation, store: store, onError: onError) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: presentation.share, container: CKContainer(identifier: store.persistence.containerIdentifier))
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]; controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let presentation: SharePresentation
        let store: RecipeStore
        let onError: (String) -> Void
        init(presentation: SharePresentation, store: RecipeStore, onError: @escaping (String) -> Void) { self.presentation = presentation; self.store = store; self.onError = onError }
        func itemTitle(for csc: UICloudSharingController) -> String? { presentation.title }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            store.reportSharingError(error)
            onError(CloudProblem.message(error))
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let share = csc.share else { return }
            Task { @MainActor in
                do { try await store.persistShare(share, in: presentation.persistentStore) } catch { store.reportSharingError(error); onError(CloudProblem.message(error)) }
            }
        }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { store.sharingStopped() }
    }
}
struct HouseholdInvitationView: View {
    @EnvironmentObject private var store: RecipeStore
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Join this household", systemImage: "person.2.fill").font(.title2.bold())
                    Text("The shared cookbook and groceries will appear when they finish downloading. Your current library stays available in Household settings.")
                    if store.joiningHousehold { ProgressView("Accepting invitation…") }
                    else { Button("Join household") { Task { await store.acceptInvitation() } }.supperGlassButton(prominent: true) }
                }
            }.navigationTitle("Supper invitation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { store.pendingInvitation = nil }.disabled(store.joiningHousehold) } }
                .interactiveDismissDisabled(store.joiningHousehold)
        }
    }
}
