import AppKit
import SwiftUI

extension AgentReplyRegression {
    /// Exercise both rows with real pointer events, including the row above the composer.
    static func approvalMenuHoverRegression() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-approval-hover-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = AgentModel(app: app)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApp.windows.first { $0.title == "Asky AI" && $0.isVisible }!
        let originalPointer = NSEvent.mouseLocation
        func move(_ point: NSPoint) {
            CGWarpMouseCursorPosition(CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y))
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y),
                mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        func moveInWindow(_ point: NSPoint) { move(window.convertPoint(toScreen: point)) }
        func click(_ point: NSPoint) async throws {
            let screen = window.convertPoint(toScreen: point)
            move(screen)
            try await Task.sleep(for: .milliseconds(100))
            let quartz = CGPoint(x: screen.x, y: NSScreen.screens[0].frame.maxY - screen.y)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartz,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
                try await Task.sleep(for: .milliseconds(80))
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        defer { window.orderOut(nil); move(originalPointer) }
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let backing = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        backing.backgroundColor = NSColor(white: 0.25, alpha: 1)
        backing.level = .floating
        backing.order(.below, relativeTo: window.windowNumber)
        defer { backing.orderOut(nil) }
        let surface = window.contentView!
        func snapshot(_ name: String) throws -> NSBitmapImageRep {
            let path = "build/approval-hover-\(name).png"
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            let rect = window.frame
            capture.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(NSScreen.screens[0].frame.maxY - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))", path]
            try capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0)
            return NSBitmapImageRep(data: try Data(contentsOf: URL(filePath: path)))!
        }
        func light(_ bitmap: NSBitmapImageRep, point: NSPoint) -> Double {
            let scale = CGFloat(bitmap.pixelsWide) / surface.bounds.width
            let x = Int(point.x * scale), y = Int((surface.bounds.height - point.y) * scale)
            var total = 0.0
            for dx in -4...4 { for dy in -4...4 {
                let color = bitmap.colorAt(x: x + dx, y: y + dy)!.usingColorSpace(.deviceRGB)!
                total += (color.redComponent + color.greenComponent + color.blueComponent) / 3
            } }
            return total / 81
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(600))
            let trigger = NSPoint(x: 460, y: 34)
            try await click(trigger)
            moveInWindow(NSPoint(x: 20, y: 200))
            try await Task.sleep(for: .milliseconds(300))
            let idle = try snapshot("\(name)-idle")
            let rows = [NSPoint(x: 490, y: 118), NSPoint(x: 490, y: 80)]
            for (index, row) in rows.enumerated() {
                moveInWindow(row)
                try await Task.sleep(for: .milliseconds(300))
                FileHandle.standardError.write(Data("hover \(name) \(index) target=\(row) actual=\(window.mouseLocationOutsideOfEventStream) key=\(window.isKeyWindow) permission=\(CGPreflightPostEventAccess())\n".utf8))
                let hovered = try snapshot("\(name)-row-\(index)")
                let delta = light(hovered, point: row) - light(idle, point: row)
                FileHandle.standardError.write(Data("illumination delta=\(delta)\n".utf8))
                precondition(delta > 0.005, "Both menu rows must visibly brighten on hover, including above the composer")
                moveInWindow(NSPoint(x: 20, y: 200))
                try await Task.sleep(for: .milliseconds(300))
                let exited = try snapshot("\(name)-exit-\(index)")
                precondition(abs(light(idle, point: row) - light(exited, point: row)) < 0.006, "Hover must clear after leaving each row")
            }
            // Isolated temporary settings allow checking both choices without changing the user's mode.
            try await click(rows[1])
            precondition(model.approvalMode == .fullAccess)
            try await click(trigger)
            try await click(rows[0])
            precondition(model.approvalMode == .autoReview, "The upper row must receive clicks above the composer's bounds")
        }
        print("Approval menu passed: both rows hover/exit in light and dark, both choices clickable, isolated settings")
    }
}
