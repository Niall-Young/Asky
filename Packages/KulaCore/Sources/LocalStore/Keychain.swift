import Foundation
import Contracts
import Security
import LocalAuthentication

/// Keychain wrapper for API keys and MCP instance credentials. Values never go to SQLite, logs or exports.
public struct Keychain: Sendable {
    public let service: String

    // A fresh namespace lets the signed app own migrated items without changing
    // legacy ACLs (which requires a separate system authorization).
    private var ownedService: String { service + ".signed.v1" }

    public init(service: String = "app.kulahere.credentials") { self.service = service }

    public enum KeychainError: LocalizedError {
        case status(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .status(let status):
                switch status {
                case errSecUserCanceled: return CoreLocalization.text("钥匙串授权已取消，请重新发送消息并允许 Asky 访问模型 Key")
                case errSecAuthFailed: return CoreLocalization.text("钥匙串授权失败，请重新发送消息并完成模型 Key 的访问授权")
                case errSecInteractionNotAllowed: return CoreLocalization.text("钥匙串暂时无法交互，请解锁登录钥匙串后重新发送消息")
                default: return CoreLocalization.format("读取模型 Key 失败（钥匙串状态码 %@）。请检查钥匙串授权或在设置 › 模型中重新保存 Key", String(describing: status))
                }
            }
        }

        public var requiresAuthentication: Bool {
            switch self {
            case .status(let status): status == errSecInteractionNotAllowed || status == errSecAuthFailed
            }
        }
    }

    public func set(_ secret: String, account: String) throws {
        try persist(secret, account: account, updateExisting: true)
    }

    private func persist(_ secret: String, account: String, updateExisting: Bool) throws {
        let base = query(service: ownedService, account: account)
        let data = Data(secret.utf8)
        // Add first so new items inherit the creating app's trusted identity.
        // Update existing items without deleting the user's only saved value.
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard updateExisting else { return }
            status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    private func query(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func get(account: String) -> String? {
        try? read(account: account)
    }

    /// Metadata checks must never decrypt a secret or present authentication UI.
    public func contains(account: String) -> Bool {
        [ownedService, service].contains { itemService in
            let context = LAContext()
            context.interactionNotAllowed = true
            var q = query(service: itemService, account: account)
            q[kSecReturnAttributes as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            q[kSecUseAuthenticationContext as String] = context
            return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
        }
    }

    /// Call interactive reads off the main thread, only for an explicit credential use.
    public func read(account: String, allowInteraction: Bool = true) throws -> String? {
        if let value = try readItem(service: ownedService, account: account, allowInteraction: allowInteraction) {
            return value
        }
        guard let legacy = try readItem(service: service, account: account, allowInteraction: allowInteraction) else {
            return nil
        }
        // A successful one-time legacy read is enough to migrate. Never change its
        // ACL or remove it: failed persistence must not destroy a working credential.
        // Failure here does not block this request; a later read retries migration.
        try? persist(legacy, account: account, updateExisting: false)
        return legacy
    }

    private func readItem(service: String, account: String, allowInteraction: Bool) throws -> String? {
        var q = query(service: service, account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        // Interactive reads use Keychain's default authorization UI. A fresh LAContext
        // is only needed to explicitly suppress interaction for the first attempt.
        if !allowInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            q[kSecUseAuthenticationContext as String] = context
        }
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public func delete(account: String) {
        for itemService in [ownedService, service] {
            SecItemDelete(query(service: itemService, account: account) as CFDictionary)
        }
    }
}
