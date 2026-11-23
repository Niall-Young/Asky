import AppKit
import ApplicationServices

/// Provides Control-Space to the focused preview surface before macOS switches input sources.
/// The caller keeps the tap disabled whenever it has no focused surface.
@MainActor
public final class PreviewShortcutCapture {
    private let handle: (NSEvent) -> Bool
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var enabled = false

    public init?(handle: @escaping (NSEvent) -> Bool) {
        guard AXIsProcessTrusted() else { return nil }
        self.handle = handle
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    let capture = Unmanaged<PreviewShortcutCapture>.fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { capture.handleTapDisabled(type) }
                    return nil
                }
                let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
                guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 49,
                      event.flags.intersection(modifiers) == .maskControl else {
                    return Unmanaged.passUnretained(event)
                }
                let capture = Unmanaged<PreviewShortcutCapture>.fromOpaque(context).takeUnretainedValue()
                let handled = MainActor.assumeIsolated {
                    NSEvent(cgEvent: event).map(capture.handle) ?? false
                }
                return handled ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return nil }
        CGEvent.tapEnable(tap: port, enable: false)
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    public func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if let port { CGEvent.tapEnable(tap: port, enable: enabled) }
    }

    public func invalidate() {
        enabled = false
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = nil
        }
        if let port {
            CFMachPortInvalidate(port)
            self.port = nil
        }
    }

    /// Re-enables only after a system timeout while the caller still wants capture active.
    /// Calling `tapEnable(false)` on `.tapDisabledByUserInput` makes WindowServer emit
    /// `.tapDisabledByUserInput` again, spinning both processes in a Mach IPC loop.
    static func shouldReenable(after type: CGEventType, desiredEnabled: Bool) -> Bool {
        type == .tapDisabledByTimeout && desiredEnabled
    }

    private func handleTapDisabled(_ type: CGEventType) {
        guard Self.shouldReenable(after: type, desiredEnabled: enabled), let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    isolated deinit {
        invalidate()
    }
}
