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
        func postMouse(_ type: CGEventType, at point: NSPoint) {
            let screen = window.convertPoint(toScreen: point)
            let quartz = CGPoint(x: screen.x, y: NSScreen.screens[0].frame.maxY - screen.y)
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartz,
                    mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        func click(_ point: NSPoint) async throws {
            moveInWindow(point)
            try await Task.sleep(for: .milliseconds(100))
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                postMouse(type, at: point)
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
        func meanDiff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, rect: NSRect) -> Double {
            let scale = CGFloat(a.pixelsWide) / surface.bounds.width
            let x0 = Int(rect.minX * scale), x1 = Int(rect.maxX * scale)
            let y0 = Int((surface.bounds.height - rect.maxY) * scale)
            let y1 = Int((surface.bounds.height - rect.minY) * scale)
            var total = 0.0
            var count = 0
            for x in x0..<x1 {
                for y in y0..<y1 {
                    let ca = a.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let cb = b.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    total += abs(ca.redComponent - cb.redComponent)
                        + abs(ca.greenComponent - cb.greenComponent)
                        + abs(ca.blueComponent - cb.blueComponent)
                    count += 3
                }
            }
            return total / Double(max(count, 1))
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(600))
            let trigger = NSPoint(x: 460, y: 34)
            moveInWindow(trigger)
            try await Task.sleep(for: .milliseconds(150))
            let triggerIdle = try snapshot("\(name)-trigger-idle")
            postMouse(.leftMouseDown, at: trigger)
            try await Task.sleep(for: .milliseconds(180))
            let triggerPressed = try snapshot("\(name)-trigger-pressed")
            let triggerDiff = meanDiff(triggerIdle, triggerPressed, rect: NSRect(x: 410, y: 18, width: 100, height: 32))
            FileHandle.standardError.write(Data("trigger press diff \(name)=\(triggerDiff)\n".utf8))
            precondition(triggerDiff < 0.008, "Approval trigger must not scale or shift on press")
            postMouse(.leftMouseUp, at: trigger)
            try await Task.sleep(for: .milliseconds(300))
            moveInWindow(NSPoint(x: 20, y: 200))
            try await Task.sleep(for: .milliseconds(300))
            let idle = try snapshot("\(name)-idle")
            let rows = [NSPoint(x: 490, y: 118), NSPoint(x: 490, y: 80)]
            var hoverDeltas: [Double] = []
            for (index, row) in rows.enumerated() {
                moveInWindow(row)
                try await Task.sleep(for: .milliseconds(300))
                FileHandle.standardError.write(Data("hover \(name) \(index) target=\(row) actual=\(window.mouseLocationOutsideOfEventStream) key=\(window.isKeyWindow) permission=\(CGPreflightPostEventAccess())\n".utf8))
                let hovered = try snapshot("\(name)-row-\(index)")
                let delta = light(hovered, point: row) - light(idle, point: row)
                hoverDeltas.append(delta)
                FileHandle.standardError.write(Data("illumination delta=\(delta)\n".utf8))
                precondition(delta > 0.005, "Both menu rows must visibly brighten on hover, including above the composer")
                moveInWindow(NSPoint(x: 20, y: 200))
                try await Task.sleep(for: .milliseconds(300))
                let exited = try snapshot("\(name)-exit-\(index)")
                precondition(abs(light(idle, point: row) - light(exited, point: row)) < 0.006, "Hover must clear after leaving each row")
            }
            // Capture pressed state on the lower row before releasing to confirm light press highlight.
            moveInWindow(rows[1])
            try await Task.sleep(for: .milliseconds(150))
            postMouse(.leftMouseDown, at: rows[1])
            try await Task.sleep(for: .milliseconds(180))
            let pressed = try snapshot("\(name)-press-1")
            let pressDelta = light(pressed, point: rows[1]) - light(idle, point: rows[1])
            FileHandle.standardError.write(Data("press delta \(name)=\(pressDelta) (hover=\(hoverDeltas[1]))\n".utf8))
            precondition(pressDelta > hoverDeltas[1] + 0.01 && pressDelta < 0.115,
                         "Pressed row highlight should stay gently brighter than hover without becoming heavy")
            postMouse(.leftMouseUp, at: rows[1])
            try await Task.sleep(for: .milliseconds(300))
            precondition(model.approvalMode == .fullAccess)
            try await click(trigger)
            try await click(rows[0])
            precondition(model.approvalMode == .autoReview, "The upper row must receive clicks above the composer's bounds")
        }
        print("Approval menu passed: trigger does not scale, both rows hover/exit and gently brighten on press in light and dark, isolated settings")
    }
}
