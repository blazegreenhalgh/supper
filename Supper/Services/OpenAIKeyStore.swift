import Foundation
import Security
import Combine

enum OpenAIKeyStore {
    private static var query: [String: Any] {
        var service = "com.supper.openai"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { service += ".ui-testing" }
        #endif
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "personal-api-key",
         kSecAttrSynchronizable as String: false]
    }
    static func read() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw SupperError.invalid("Couldn’t read your API key. Unlock this device and try again.")
        }
        return key
    }
    static func save(_ value: String) throws {
        let key = try OpenAIClient.validatedKey(value)
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw storageError }
        } else if status != errSecSuccess { throw storageError }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw storageError }
    }
    static func client() throws -> OpenAIClient {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            throw SupperError.invalid("Live OpenAI requests are disabled during UI tests.")
        }
        #endif
        guard let key = try read() else { throw SupperError.invalid("Add your OpenAI API key in Settings → AI to use this feature. Manual editing and on-device formatting still work.") }
        return try OpenAIClient(apiKey: key)
    }
    private static var storageError: SupperError { .invalid("Couldn’t update the API key in this device’s Keychain. Your previous key, if any, has not been replaced.") }
}

@MainActor final class OpenAISettings: ObservableObject {
    static let shared = OpenAISettings()
    @Published private(set) var isConfigured = false
    private init() { refresh() }
    func refresh() { isConfigured = (try? OpenAIKeyStore.read()) != nil }
    func save(_ key: String) throws { try OpenAIKeyStore.save(key); refresh() }
    func remove() throws { try OpenAIKeyStore.remove(); refresh() }
}
