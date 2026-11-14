import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled, notRegistered, requiresApproval, notFound, unknown

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .notRegistered: self = .notRegistered
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .unknown
        }
    }
}

/// Injectable system boundary so failure and approval paths can be checked without changing login items.
@MainActor
struct LaunchAtLoginRegistration {
    var status: () -> LaunchAtLoginStatus
    var register: () throws -> Void
    var unregister: () throws -> Void

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        let current = status()
        if enabled {
            if current != .enabled && current != .requiresApproval { try register() }
        } else if current != .notRegistered {
            try unregister()
        }
        let result = status()
        guard enabled ? (result == .enabled || result == .requiresApproval) : result == .notRegistered else {
            throw RegistrationError.unconfirmed
        }
        return result
    }

    private enum RegistrationError: LocalizedError {
        case unconfirmed
        var errorDescription: String? {
            NSLocalizedString("无法确认登录项状态，请在系统设置中检查。", comment: "")
        }
    }
}

extension ToolService {
    @MainActor
    public static var launchAtLoginStatus: LaunchAtLoginStatus { LaunchAtLoginStatus(SMAppService.mainApp.status) }

    @MainActor
    public static var launchAtLoginEnabled: Bool { launchAtLoginStatus == .enabled }

    @MainActor
    @discardableResult
    public static func setLaunchAtLogin(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        try LaunchAtLoginRegistration(
            status: { launchAtLoginStatus },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() }
        ).setEnabled(enabled)
    }

    @MainActor
    public static func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Preserve pending system approval and any already enabled registration.
    @MainActor
    public static func enableDefaultLaunchAtLogin() throws {
        if SMAppService.mainApp.status == .notRegistered {
            try setLaunchAtLogin(true)
        }
    }
}
