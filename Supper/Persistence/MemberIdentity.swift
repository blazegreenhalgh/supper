#if SWIFT_PACKAGE
import SupperCore
#endif
import Foundation
import Security

/// Keychain survives app restarts/reinstalls. Cloud record IDs link this provisional identity
/// across devices only after successful account resolution; names are never identity keys.
@MainActor
final class MemberIdentity {
    private struct Saved: Codable { var id: String; var name: String; var accountID: String? }
    private var saved: Saved
    private let service = "com.blazegreenhalgh.Supper.member"
    var id: String { saved.id }
    var accountID: String? { saved.accountID }
    var name: String { get { saved.name } set { saved.name = newValue; persist() } }

    init() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.blazegreenhalgh.Supper.member", kSecAttrAccount as String: "identity", kSecReturnData as String: true]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
           let value = try? JSONDecoder().decode(Saved.self, from: data) { saved = value }
        else if let data = UserDefaults.standard.data(forKey: "memberIdentityFallback"), let value = try? JSONDecoder().decode(Saved.self, from: data) { saved = value }
        else { saved = Saved(id: UUID().uuidString, name: "Me", accountID: nil) }
        persist()
    }
    func resolve(accountID: String) {
        if let previous = saved.accountID, previous != accountID {
            // An account switch must never adopt the previous person's offline reactions.
            let key = "memberIdentity.account." + accountID
            saved = Saved(id: UserDefaults.standard.string(forKey: key) ?? UUID().uuidString, name: "Me", accountID: accountID)
        } else { saved.accountID = accountID }
        UserDefaults.standard.set(saved.id, forKey: "memberIdentity.account." + accountID)
        persist()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "identity"]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { _ = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
        UserDefaults.standard.set(data, forKey: "memberIdentityFallback")
    }
}
