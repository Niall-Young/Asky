import AppKit
import SwiftUI
import Observation
import Theme
import ToolService

@MainActor @Observable
private final class PermissionAuthorizationModel {
    let permission: SystemPermission
    var preparing = true
    var regrant = false
    var cardAbsent = false
    var dropped = false
    var needsRelaunch = false
    var message: String?

    init(permission: SystemPermission) { self.permission = permission }
}

@MainActor
struct PermissionAuthorizationSettingsHandle {
    let windowFrame: () -> CGRect?
    let dismiss: () -> Void
}

/// A standalone, nonmodal panel stays beside System Settings without activating Asky.
@MainActor
final class PermissionAuthorizationWindow: NSObject, NSWindowDelegate {
    static let shared = PermissionAuthorizationWindow()
    private var panel: NSPanel?
    private weak var hostingView: NSView?
    private var settingsSession: PermissionAuthorizationSettingsHandle?
    private var observation: Task<Void, Never>?
    private var generation = UUID()
    private let readState: (SystemPermission) async -> PermissionState
    private let openPermissionSettings: (SystemPermission) throws -> PermissionAuthorizationSettingsHandle
    private let resetAuthorization: (SystemPermission) async -> Void

    var window: NSPanel? { panel }

    init(readState: @escaping (SystemPermission) async -> PermissionState = { await SystemPermissions.state($0) },
         openSettings: @escaping (SystemPermission) throws -> PermissionAuthorizationSettingsHandle = {
             let session = try SystemPermissions.openAuthorizationSettings($0)
             return PermissionAuthorizationSettingsHandle(windowFrame: { session.windowFrame }, dismiss: { session.dismiss() })
         },
         resetAuthorization: @escaping (SystemPermission) async -> Void = { await SystemPermissions.resetAuthorization($0) }) {
        self.readState = readState
        self.openPermissionSettings = openSettings
        self.resetAuthorization = resetAuthorization
        super.init()
    }

    func show(_ permission: SystemPermission, colorScheme: ColorScheme) {
        guard permission.supportsAppDrag else { return }
        cancel()
        let generation = UUID()
        self.generation = generation
        let model = PermissionAuthorizationModel(permission: permission)
        let view = PermissionAuthorizationView(model: model, close: { [weak self] in self?.cancel() },
            reopenSettings: { [weak self] in self?.openSettings(for: model) },
            relaunch: {
                do { try SystemPermissions.relaunchApp() }
                catch { model.message = error.localizedDescription }
            },
            dropEnded: { [weak self] accepted in self?.dropEnded(accepted, model: model, generation: generation) })
            .environment(\.colorScheme, colorScheme)
        let host = NSHostingView(rootView: view)
        let panel = AuthorizationPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        panel.title = "\(permission.title) — Asky"
        panel.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        hostingView = host
        panel.contentView = WindowSurface.glassContentView(host, cornerRadius: 24)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.setContentSize(host.fittingSize)
        self.panel = panel
        position(beside: nil)
        panel.makeKeyAndOrderFront(nil)

        observation = Task { [weak self] in
            guard let self else { return }
            let initial = await self.readState(permission)
            guard self.generation == generation, !Task.isCancelled else { return }
            model.regrant = initial == .authorized
            // A switched-on entry that does not apply belongs to another build's signature and makes
            // System Settings reject the drop. Remove it so dragging the card adds and enables this build.
            if initial != .authorized {
                await self.resetAuthorization(permission)
                guard self.generation == generation, !Task.isCancelled else { return }
                model.needsRelaunch = permission.requiresRelaunchAfterGrant
            }
            model.preparing = false
            var progress = PermissionAuthorizationProgress(initialState: initial)
            self.openSettings(for: model)
            for _ in 0..<20 {
                guard self.generation == generation, !Task.isCancelled else { return }
                self.resizeToContent()
                if let frame = self.settingsSession?.windowFrame() {
                    self.position(beside: frame)
                    break
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            while self.generation == generation, !Task.isCancelled {
                let state = await self.readState(permission)
                guard self.generation == generation, !Task.isCancelled else { return }
                self.resizeToContent()
                if progress.observe(state) {
                    self.settingsSession?.dismiss()
                    // The switch is on, but capture keeps failing until Asky restarts.
                    if permission.requiresRelaunchAfterGrant {
                        model.needsRelaunch = true
                        model.cardAbsent = true
                        self.resizeToContent()
                        self.panel?.makeKeyAndOrderFront(nil)
                    } else {
                        self.cancel()
                    }
                    return
                }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }

    /// An accepted drop that does not produce a working grant brings the card back for a retry.
    /// Screen recording cannot be confirmed before relaunch, so its card stays hidden.
    private func dropEnded(_ accepted: Bool, model: PermissionAuthorizationModel, generation: UUID) {
        model.cardAbsent = accepted
        guard accepted, !model.permission.requiresRelaunchAfterGrant else { return }
        model.dropped = true
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.generation == generation else { return }
            // The drop did not produce a working grant: bring the card back so it can be retried.
            if await self.readState(model.permission) != .authorized {
                guard self.generation == generation else { return }
                model.cardAbsent = false
                self.resizeToContent()
            }
        }
    }

    private func openSettings(for model: PermissionAuthorizationModel) {
        do {
            settingsSession = try openPermissionSettings(model.permission)
            model.message = nil
            if let frame = settingsSession?.windowFrame() { position(beside: frame) }
            panel?.makeKeyAndOrderFront(nil)
        } catch { model.message = error.localizedDescription }
    }

    func cancel() {
        generation = UUID()
        observation?.cancel()
        observation = nil
        settingsSession = nil
        let oldPanel = panel
        panel = nil
        hostingView = nil
        oldPanel?.delegate = nil
        oldPanel?.close()
    }

    func windowWillClose(_ notification: Notification) { cancel() }

    private func resizeToContent() {
        guard let panel, let content = hostingView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        if size.width > 0, size.height > 0, size != panel.frame.size { panel.setContentSize(size) }
    }

    private func position(beside settingsFrame: CGRect?) {
        guard let panel else { return }
        let screen = settingsFrame.flatMap { frame in
            NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let size = panel.frame.size
        var x = visible.minX
        var y = visible.midY - size.height / 2
        if let frame = settingsFrame {
            let right = frame.maxX + 12
            let left = frame.minX - size.width - 12
            x = right + size.width <= visible.maxX ? right : max(visible.minX, left)
            y = frame.maxY - size.height - 36
        }
        x = max(visible.minX, min(x, visible.maxX - size.width))
        y = max(visible.minY, min(y, visible.maxY - size.height))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class AuthorizationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { close() }
}

private struct PermissionAuthorizationView: View {
    let model: PermissionAuthorizationModel
    let close: () -> Void
    let reopenSettings: () -> Void
    let relaunch: () -> Void
    let dropEnded: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text(NSLocalizedString(model.permission.title, comment: ""))
                    .font(.system(size: 16, weight: .regular))
                Spacer()
                Button(action: close) {
                    Image(mingCute: "xmark", size: 12)
                        .frame(width: 28, height: 28).contentShape(.circle)
                }
                .buttonStyle(.plain).foregroundStyle(ThemeColor.kTextSubtle)
                .accessibilityLabel(NSLocalizedString("关闭", comment: ""))
            }
            let canDrag = SystemPermissions.canDragApp(at: SystemPermissions.appURL)
            if canDrag {
                PermissionAppDragCard(onStarted: { model.cardAbsent = true }, onEnded: dropEnded)
                    .frame(height: 80)
                    .opacity(model.preparing || model.cardAbsent ? 0 : 1)
                    .allowsHitTesting(!model.preparing && !model.cardAbsent)
            } else {
                PermissionAppCard(colorScheme: colorScheme, reduceTransparency: reduceTransparency).opacity(0.5)
            }
            Text(NSLocalizedString(model.preparing
                ? "正在准备授权…"
                : !canDrag
                ? "请先将 Asky.app 移到“应用程序”文件夹并重新打开，再拖拽授权。"
                : model.needsRelaunch
                ? "将卡片拖入系统设置，然后重新启动 Asky 使屏幕录制生效。"
                : model.dropped && !model.cardAbsent
                ? "仍未生效，请再拖一次。"
                : model.regrant
                ? "先删除旧条目，再拖入卡片并开启。"
                : "将卡片拖入系统设置，开启 Asky 开关。", comment: ""))
                .font(.system(size: 14)).foregroundStyle(ThemeColor.kTextSubtle)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.message {
                Text(message).font(.system(size: 13)).foregroundStyle(ThemeColor.kTextNegative)
                    .fixedSize(horizontal: false, vertical: true)
                Button(NSLocalizedString("打开系统设置", comment: ""), action: reopenSettings)
                    .compatibleGlassButtonStyle()
            }
            if model.needsRelaunch && !model.preparing {
                Button(NSLocalizedString("重新启动 Asky", comment: ""), action: relaunch)
                    .compatibleGlassButtonStyle(prominent: true)
            }
        }
        .padding(20)
        .frame(width: 360)
        .foregroundStyle(ThemeColor.kText)
        .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

}
