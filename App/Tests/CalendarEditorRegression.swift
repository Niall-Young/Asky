import AppKit
import Contracts
import Scheduler
import SwiftUI

@main @MainActor
enum CalendarEditorRegression {
    static func main() {
        let start = Date().addingTimeInterval(86400)
        let draft = MessageCalendarDraft(title: "产品评审", start: start, location: "3 号会议室")
        let choices = [MessageCalendarChoice(id: "personal", name: "个人", account: "iCloud", isDefault: true),
                       MessageCalendarChoice(id: "work", name: "工作", account: "iCloud")]
        let model = MessageCalendarEditorModel(draft, calendars: choices, source: "带上新版原型")
        precondition(model.isValid && model.end == start.addingTimeInterval(3600))
        precondition(!model.isStartInPast && !model.isEndBeforeStart)
        precondition(model.formattedDuration != nil)

        model.title = " "
        precondition(!model.isValid)
        model.title = "产品评审"

        model.end = start.addingTimeInterval(-60)
        precondition(!model.isValid && model.isEndBeforeStart && model.formattedDuration == nil)
        model.end = start.addingTimeInterval(5400) // 1.5 hours
        precondition(model.isValid && !model.isEndBeforeStart)

        // Updating start preserves the current 1.5-hour duration.
        let shiftedStart = start.addingTimeInterval(7200)
        model.updateStart(shiftedStart)
        precondition(model.start == shiftedStart)
        precondition(abs(model.end.timeIntervalSince(model.start) - 5400) < 0.5)

        // Updating start date preserves time-of-day and duration.
        let calendar = Calendar(identifier: .gregorian)
        let nextWeek = calendar.date(byAdding: .day, value: 5, to: shiftedStart)!
        model.updateStartDate(nextWeek, calendar: calendar)
        precondition(calendar.isDate(model.start, inSameDayAs: nextWeek))
        precondition(calendar.component(.hour, from: model.start) == calendar.component(.hour, from: shiftedStart))
        precondition(calendar.component(.minute, from: model.start) == calendar.component(.minute, from: shiftedStart))
        precondition(abs(model.end.timeIntervalSince(model.start) - 5400) < 0.5)

        // Updating start time updates hour/minute and preserves duration.
        model.updateStartTime(hour: 15, minute: 30, calendar: calendar)
        precondition(calendar.component(.hour, from: model.start) == 15)
        precondition(calendar.component(.minute, from: model.start) == 30)
        precondition(abs(model.end.timeIntervalSince(model.start) - 5400) < 0.5)

        // Updating end time independently changes duration without moving start.
        model.updateEndTime(hour: 18, minute: 0, calendar: calendar)
        precondition(calendar.component(.hour, from: model.end) == 18)
        precondition(calendar.component(.minute, from: model.end) == 0)
        precondition(abs(model.end.timeIntervalSince(model.start) - 9000) < 0.5)

        // Past start detection.
        let pastStart = Date().addingTimeInterval(-3600)
        model.start = pastStart
        precondition(model.isStartInPast && !model.isValid)
        model.start = start
        model.end = start.addingTimeInterval(3600)

        model.calendarID = "missing"
        precondition(!model.isValid)
        model.calendarID = "work"
        precondition(model.isValid && model.draft.arguments["calendar"]?.stringValue == "work")
        precondition(model.draft.arguments["notes"]?.stringValue == "带上新版原型")

        let pickedDay = calendar.date(byAdding: .day, value: 3, to: start)!
        let picked = CalendarMonthPicker.selecting(pickedDay, preservingTimeFrom: start, calendar: calendar)!
        precondition(calendar.isDate(picked, inSameDayAs: pickedDay))
        precondition(calendar.component(.hour, from: picked) == calendar.component(.hour, from: start))
        precondition(calendar.component(.minute, from: picked) == calendar.component(.minute, from: start))
        precondition(MessageCalendarChoice.writableChoices([
            ["id": "read-only", "name": "生日", "writable": false],
            ["id": "work", "name": "工作", "writable": true]
        ]).map(\.id) == ["work"])
        print("Calendar editor model validation passed")

        if let dirIndex = CommandLine.arguments.firstIndex(of: "--snapshot-dir"),
           CommandLine.arguments.indices.contains(dirIndex + 1) {
            let outputDir = URL(fileURLWithPath: CommandLine.arguments[dirIndex + 1], isDirectory: true)
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            app.finishLaunching()
            Task { @MainActor in
                do {
                    try await captureSnapshots(to: outputDir, draft: draft, choices: choices)
                    print("Calendar editor snapshots saved to \(outputDir.path)")
                    exit(0)
                } catch {
                    fputs("Snapshot error: \(error)\n", stderr)
                    exit(1)
                }
            }
            app.run()
        }

        guard CommandLine.arguments.contains("--preview") else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        Task { @MainActor in
            var attempts = 0
            _ = await MessageCalendarEditor.present(draft, calendars: choices, source: "带上新版原型") { _ in
                attempts += 1
                if CommandLine.arguments.contains("--preview-error"), attempts == 1 {
                    return .failure("preview", .conflict, "该时间与已有日程冲突，请调整后重试")
                }
                return ExecutionResult(requestID: "preview", status: .completed)
            }
            print("Preview finished; no calendar writes")
            exit(0)
        }
        app.run()
    }

    private static func captureSnapshots(to directory: URL, draft: MessageCalendarDraft, choices: [MessageCalendarChoice]) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSApp.activate(ignoringOtherApps: true)

        func makeWindow(model: MessageCalendarEditorModel, appearance: NSAppearance.Name) -> CalendarEditorWindow {
            let view = MessageCalendarEditorView(model: model, cancel: {}, create: {})
            let host = NSHostingView(rootView: view
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea())
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: MessageCalendarEditor.windowSize)
            let panel = CalendarEditorWindow(
                contentRect: host.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.appearance = NSAppearance(named: appearance)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.contentView = WindowSurface.glassContentView(host, cornerRadius: MessageCalendarEditor.cornerRadius)
            if let surface = panel.contentView {
                WindowSurface.updateCorners(of: surface, radius: MessageCalendarEditor.cornerRadius, circular: true)
            }
            panel.center()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return panel
        }

        func writeWindowPNG(_ window: NSWindow, to url: URL) throws {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-l", "\(window.windowNumber)", url.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "CalendarEditorRegression", code: Int(process.terminationStatus))
            }
        }

        func findMarker(_ id: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == id { return view }
            for sub in view.subviews {
                if let match = findMarker(id, in: sub) { return match }
            }
            return nil
        }

        func clickCenter(of marker: NSView, in window: NSWindow) {
            let centerInWindow = marker.convert(NSPoint(x: marker.bounds.midX, y: marker.bounds.midY), to: nil)
            let down = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: centerInWindow,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )!
            let up = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: centerInWindow,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + 0.02,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 0
            )!
            window.sendEvent(down)
            window.sendEvent(up)
        }

        // 1. Light & Dark ready snapshots
        for (name, appearance) in [("calendar-light.png", NSAppearance.Name.aqua),
                                   ("calendar-dark.png", NSAppearance.Name.darkAqua)] {
            let model = MessageCalendarEditorModel(draft, calendars: choices, source: "上次会议约定要带上新版原型，记得提前准备")
            let panel = makeWindow(model: model, appearance: appearance)
            try await Task.sleep(for: .milliseconds(350))
            try writeWindowPNG(panel, to: directory.appendingPathComponent(name))
            panel.orderOut(nil)
            panel.close()
        }

        // 2. Dark error + validation hint snapshot
        do {
            let model = MessageCalendarEditorModel(draft, calendars: choices, source: "上次会议约定要带上新版原型")
            model.end = model.start.addingTimeInterval(-600)
            model.error = "该时间与已有日程冲突，请调整后重试"
            let panel = makeWindow(model: model, appearance: .darkAqua)
            try await Task.sleep(for: .milliseconds(350))
            try writeWindowPNG(panel, to: directory.appendingPathComponent("calendar-error-dark.png"))
            panel.orderOut(nil)
            panel.close()
        }

        // 3. Light saving state snapshot
        do {
            let model = MessageCalendarEditorModel(draft, calendars: choices, source: "上次会议约定要带上新版原型")
            model.saving = true
            let panel = makeWindow(model: model, appearance: .aqua)
            try await Task.sleep(for: .milliseconds(350))
            try writeWindowPNG(panel, to: directory.appendingPathComponent("calendar-saving-light.png"))
            panel.orderOut(nil)
            panel.close()
        }

        // 4. Interactive Date & Time popovers in dark mode (verify real click opens popovers)
        do {
            let model = MessageCalendarEditorModel(draft, calendars: choices, source: "带上新版原型")
            let panel = makeWindow(model: model, appearance: .darkAqua)
            try await Task.sleep(for: .milliseconds(300))

            // Verify header drag area & trigger markers exist
            let content = panel.contentView!
            guard let datePickerMarker = findMarker("calendar-editor-start-date-picker", in: content),
                  let timePickerMarker = findMarker("calendar-editor-start-time-picker", in: content) else {
                throw NSError(domain: "CalendarEditorRegression", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing picker markers"])
            }

            clickCenter(of: datePickerMarker, in: panel)
            try await Task.sleep(for: .milliseconds(350))
            let datePopoverWindow = NSApp.windows.first { $0 !== panel && $0.isVisible && $0.frame.width > 200 }
            precondition(datePopoverWindow != nil, "Date popover did not open")
            if let popover = datePopoverWindow {
                try writeWindowPNG(popover, to: directory.appendingPathComponent("calendar-date-popover-dark.png"))
            }
            clickCenter(of: datePickerMarker, in: panel)
            try await Task.sleep(for: .milliseconds(250))

            clickCenter(of: timePickerMarker, in: panel)
            try await Task.sleep(for: .milliseconds(350))
            let timePopoverWindow = NSApp.windows.first { $0 !== panel && $0.isVisible && $0.frame.width > 120 }
            precondition(timePopoverWindow != nil, "Time popover did not open")
            if let popover = timePopoverWindow {
                try writeWindowPNG(popover, to: directory.appendingPathComponent("calendar-time-popover-dark.png"))
            }

            panel.orderOut(nil)
            panel.close()
        }
    }
}
