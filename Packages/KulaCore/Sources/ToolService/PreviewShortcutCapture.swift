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
                    MainActor.assumeIsolated { capture.setEnabled(capture.enabled) }
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
        self.enabled = enabled
        if let port { CGEvent.tapEnable(tap: port, enable: enabled) }
    }

    isolated deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
    }
}
