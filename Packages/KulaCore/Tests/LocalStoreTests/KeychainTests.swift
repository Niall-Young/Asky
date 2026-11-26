import Testing
import Foundation
import Contracts
import LocalStore
import Security

@Suite struct KeychainTests {
    @Test func authorizationFailuresHaveActionableMessages() {
        #expect(Keychain.KeychainError.status(errSecUserCanceled).localizedDescription == CoreLocalization.text("钥匙串授权已取消，请重新发送消息并允许 Asky 访问模型 Key"))
        for status in [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed, errSecNotAvailable] {
            #expect(!Keychain.KeychainError.status(status).localizedDescription.hasSuffix("。"))
        }
        #expect(Keychain.KeychainError.status(errSecAuthFailed).requiresAuthentication)
        #expect(Keychain.KeychainError.status(errSecInteractionNotAllowed).requiresAuthentication)
        #expect(!Keychain.KeychainError.status(errSecUserCanceled).requiresAuthentication)
        #expect(Keychain.KeychainError.status(errSecNotAvailable).localizedDescription.contains(String(errSecNotAvailable)))
    }

    @Test func metadataAndNoninteractiveReadsUseOnlyTheRequestedAccount() throws {
        let keychain = Keychain(service: "app.asky.tests.\(UUID().uuidString)")
        defer { keychain.delete(account: "model") }
        #expect(!keychain.contains(account: "model"))
        #expect(try keychain.read(account: "model", allowInteraction: false) == nil)

        try keychain.set("synthetic-test-credential", account: "model")
        #expect(keychain.contains(account: "model"))
        #expect(!keychain.contains(account: "other"))
        #expect(try keychain.read(account: "model") == "synthetic-test-credential")
        #expect(try keychain.read(account: "model", allowInteraction: false) == "synthetic-test-credential")

        keychain.delete(account: "model")
        #expect(!keychain.contains(account: "model"))
        #expect(try keychain.read(account: "model", allowInteraction: false) == nil)
    }
    @Test func legacyReadMigratesAndNewSavesTakePrecedence() throws {
        let service = "app.asky.tests.\(UUID().uuidString)"
        let keychain = Keychain(service: service)
        defer { keychain.delete(account: "model") }
        let legacy: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "model",
            kSecValueData as String: Data("legacy-synthetic".utf8),
        ]
        #expect(SecItemAdd(legacy as CFDictionary, nil) == errSecSuccess)
        #expect(keychain.contains(account: "model"))
        #expect(try keychain.read(account: "model", allowInteraction: false) == "legacy-synthetic")

        // Remove only the fixture: further reads must come from the migrated item.
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "model",
        ]
        #expect(SecItemDelete(legacyQuery as CFDictionary) == errSecSuccess)
        #expect(try keychain.read(account: "model", allowInteraction: false) == "legacy-synthetic")
        #expect(SecItemAdd(legacy as CFDictionary, nil) == errSecSuccess)
        try keychain.set("new-synthetic", account: "model")
        try keychain.set("updated-synthetic", account: "model")
        #expect(try keychain.read(account: "model", allowInteraction: false) == "updated-synthetic")
        keychain.delete(account: "model")
        #expect(!keychain.contains(account: "model"))
        #expect(try keychain.read(account: "model", allowInteraction: false) == nil)
    }

}
