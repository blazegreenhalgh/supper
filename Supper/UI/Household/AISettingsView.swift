import SwiftUI

struct AISettingsView: View {
    @ObservedObject private var settings = OpenAISettings.shared
    @State private var key = ""
    @State private var status: String?
    @State private var error: String?
    @State private var testing = false
    @State private var task: Task<Void, Never>?
    @State private var confirmingRemoval = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        Form {
            Section {
                Label(settings.isConfigured ? "API key saved on this device" : "Connect your OpenAI account", systemImage: settings.isConfigured ? "checkmark.shield" : "key")
                SecureField(settings.isConfigured ? "Replacement API key" : "OpenAI API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    .focused($keyFocused)
                    .accessibilityIdentifier("openAIKeyInput")
                Button(settings.isConfigured ? "Replace key" : "Save key") {
                    do { try settings.save(key); key = ""; keyFocused = false; status = "Saved securely on this device. You can now use AI features." }
                    catch { self.error = error.localizedDescription }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testing)
                    .accessibilityIdentifier("saveOpenAIKey")
                if settings.isConfigured {
                    if testing { ProgressView("Checking model access…") }
                    Button("Test connection", systemImage: "network", action: test).disabled(testing || !key.isEmpty)
                    Button("Remove key", role: .destructive) { confirmingRemoval = true }.disabled(testing)
                }
                if let status { Text(status).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("openAIKeyStatus") }
            } header: { Text("Your API key") } footer: {
                Text("The key is stored in this device’s Keychain. It is not synced with iCloud, migrated to another device or shared with household members. Add a key separately on each device. Testing checks model access without generating a response; restricted keys need permission to read models for this check.")
            }
            Section("AI features") {
                LabeledContent("Recipe search & editing", value: "GPT-5.6 Terra")
                LabeledContent("Recipe covers", value: "GPT Image 2.5 Flare")
                LabeledContent("Covers from your photo", value: "GPT Image 2.5 Sunburst")
                Text("Recipe discovery only imports published recipes. Ask AI shows online sources and lets you review changes before applying them.")
                Text("Formatting, simple tags and text recognition stay on-device. Manual editing and URL import don’t require a key.")
            }
            Section {
                Text("Using AI sends your request and relevant recipe content to OpenAI. Online searches use OpenAI’s web-search tool; recipe pages and photos are downloaded from their publishers. Recipe text import reads photos on-device before sending the recognised text. Cover generation sends the title and ingredient list. Create from my photo sends your selected food image as a reference for a newly generated cookbook photograph, with camera metadata removed. Your API key is sent only to api.openai.com.")
                Text("API usage is billed separately from ChatGPT. Saving a key enables these user-requested features; no paid requests run in the background. OpenAI requests use store: false where supported, but OpenAI’s API data policies still apply.")
                Link("Create an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                Link("Manage API billing", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                Link("OpenAI API data policies", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
            } header: { Text("Privacy & usage") }
        }
        .navigationTitle("AI").navigationBarTitleDisplayMode(.inline)
        .onAppear { settings.refresh() }
        .onDisappear { task?.cancel(); key = "" }
        .confirmationDialog("Remove the OpenAI key from this device?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) {
                do { try settings.remove(); key = ""; status = "Key removed. Your recipes have not changed." }
                catch { self.error = error.localizedDescription }
            }.accessibilityIdentifier("confirmRemoveOpenAIKey")
        }
        .supperError($error, title: "OpenAI connection")
    }

    private func test() {
        testing = true; status = nil
        task = Task {
            defer { testing = false }
            do {
                try await OpenAIKeyStore.client().testConnection()
                try Task.checkCancellation()
                status = "Connected. GPT-5.6 Terra is accessible. Image access and available credits are checked when you use those features."
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
