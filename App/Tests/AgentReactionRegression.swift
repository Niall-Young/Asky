import AppKit
import Contracts
import LocalStore

extension AgentReplyRegression {
    static func reactionRegression(app: AppModel, capture: Bool) async throws {
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "表情回应回归")
        let model = AgentModel(app: app)
        let cases: [(String, String, String?, String?)] = [
            ("你好", "你好，有什么可以帮你？", nil, "你好，有什么可以帮你？"),
            ("你真棒", "<asky-reaction>😊</asky-reaction>", "😊", nil),
            ("谢谢！顺便告诉我 2 + 2 是多少", "<asky-reaction>❤️</asky-reaction>\n2 + 2 = 4。", "❤️", "2 + 2 = 4。")
        ]
        for (index, sample) in cases.enumerated() {
            let user = try store.append(conversationID: cid, role: "user", text: sample.0)
            model.open(cid)
            let task = "reaction-\(index)"
            model.beginResponse(taskID: task)
            model.handle(.textDelta(taskID: task, sample.1), conversationID: cid)
            precondition(model.items.last?.agentReaction == nil, "No partial reaction while streaming")
            model.handle(.message(taskID: task, sample.1), conversationID: cid)
            model.handle(.taskState(taskID: task, .completed), conversationID: cid)
            model.finishTask(conversationID: cid)
            precondition(!model.isRunning && model.streaming.isEmpty)
            precondition(model.items.first { $0.id == user.id }?.agentReaction == sample.2)
            let replies = model.items.filter { $0.responseID == task && $0.kind == .assistant }
            precondition(replies.map(\.text) == (sample.3.map { [$0] } ?? []), "Only textual replies create an assistant bubble")
            model.open(cid)
            precondition(model.items.first { $0.id == user.id }?.agentReaction == sample.2, "History preserves reactions")
            precondition(model.items.allSatisfy { !$0.text.contains("<asky-reaction>") })
            if capture {
                let controller = AgentWindowController(model: model, presentation: WindowPresentation())
                controller.show()
                guard let window = NSApp.windows.first(where: { String(describing: type(of: $0)) == "AgentWindow" && $0.isVisible }) else { fatalError("Missing reaction preview window") }
                for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    window.appearance = NSAppearance(named: appearance)
                    try await Task.sleep(for: .milliseconds(700))
                    window.contentView?.layoutSubtreeIfNeeded()
                    let process = Process()
                    process.executableURL = URL(filePath: "/usr/sbin/screencapture")
                    process.arguments = ["-x", "-o", "-l", String(window.windowNumber), "build/reactions-\(index)-\(name).png"]
                    try process.run(); process.waitUntilExit()
                    precondition(process.terminationStatus == 0)
                }
                window.orderOut(nil)
            }
        }
        for state in [AgentTaskState.cancelled, .failed, .pendingVerification] {
            let user = try store.append(conversationID: cid, role: "user", text: "取消这次回应")
            model.open(cid)
            model.beginResponse(taskID: "interrupted")
            model.handle(.message(taskID: "interrupted", "<asky-reaction>👍</asky-reaction>"), conversationID: cid)
            model.handle(.taskState(taskID: "interrupted", state), conversationID: cid)
            model.finishTask(conversationID: cid)
            precondition(store.message(user.id, conversationID: cid)?.presentation?.agentReaction == nil)
        }
        let longID = try store.create(title: "表情目标被分页移出")
        let longUser = try store.append(conversationID: longID, role: "user", text: "谢谢")
        model.open(longID)
        model.beginResponse(taskID: "long-reaction")
        for index in 0..<125 {
            let request = ActionRequest(requestID: "reaction-tool-\(index)", tool: "notes_search",
                arguments: [:], origin: .agent(sessionID: longID), intent: .explicitRequest)
            model.handle(.toolCall(taskID: "long-reaction", request), conversationID: longID)
            model.handle(.toolResult(taskID: "long-reaction", ExecutionResult(requestID: request.requestID, status: .completed)), conversationID: longID)
        }
        precondition(!model.items.contains { $0.id == longUser.id })
        model.handle(.message(taskID: "long-reaction", "<asky-reaction>👍🏽</asky-reaction>"), conversationID: longID)
        model.handle(.taskState(taskID: "long-reaction", .completed), conversationID: longID)
        model.finishTask(conversationID: longID)
        precondition(store.message(longUser.id, conversationID: longID)?.presentation?.agentReaction == "👍🏽")
        let other = try store.create(title: "不能贴到历史消息")
        model.open(other)
        model.beginResponse(taskID: "missing-target")
        model.handle(.message(taskID: "missing-target", "<asky-reaction>😊</asky-reaction>"), conversationID: other)
        model.handle(.taskState(taskID: "missing-target", .completed), conversationID: other)
        model.finishTask(conversationID: other)
        precondition(model.items.last?.text == "😊", "Missing target falls back to a visible reply")
        print("Reaction regression passed: all three modes, completed-only presentation, history, cancellation and target isolation")
    }
}


extension AgentReplyRegression {
    /// Run inside NSApplication.run: sendEvent alone does not exercise SwiftUI hover tracking.
    static func userBubbleHoverRegression() async throws {
        let originalPointer = NSEvent.mouseLocation
        func movePointer(_ point: NSPoint) {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y),
                mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        defer { movePointer(originalPointer) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let samples = ["Anthropic 呢?", "谢谢 🤖", String(repeating: "长消息达到最大宽度后正常换行。", count: 8)]
        let reply = "短 AI 回复也应保持宽度。"
        for (sampleIndex, sample) in samples.enumerated() {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let root = FileManager.default.temporaryDirectory.appending(path: "Asky-hover-\(UUID())")
                defer { try? FileManager.default.removeItem(at: root) }
                let app = try AppModel(root: root)
                let store = ConversationStore(app.store)
                let cid = try store.create(title: "User bubble hover")
                try store.append(conversationID: cid, role: "user", text: sample)
                let model = AgentModel(app: app)
                model.open(cid)
                model.avatarColor = .yellow
                model.beginResponse(taskID: "hover-reaction")
                model.handle(.message(taskID: "hover-reaction", "<asky-reaction>🤖</asky-reaction>\n" + reply), conversationID: cid)
                model.handle(.taskState(taskID: "hover-reaction", .completed), conversationID: cid)
                model.finishTask(conversationID: cid)
                let controller = AgentWindowController(model: model, presentation: WindowPresentation())
                controller.show()
                let window = NSApp.windows.first { $0.title == "Asky AI" && $0.isVisible }!
                defer { window.orderOut(nil) }
                // Other native regression windows may be running in the workspace.
                // Keep pointer events on this fixture rather than a normal-level window.
                window.level = .floating
                window.appearance = NSAppearance(named: appearance)
                NSApp.activate(ignoringOtherApps: true)
                movePointer(window.convertPoint(toScreen: NSPoint(x: 10, y: 10)))
                try await Task.sleep(for: .milliseconds(700))
                let surface = window.contentView!
                let texts = descendants(surface).compactMap { $0 as? NSTextView }
                let text = texts.first { $0.string == sample }!
                let answer = texts.first { $0.string == reply }!
                let initial = text.convert(text.bounds, to: surface)
                let answerFrame = answer.convert(answer.bounds, to: surface)
                let textFrame = text.convert(text.bounds, to: nil)
                // Left side action bar sits 8 pt left of the bubble (18 pt text inset),
                // containing Copy (28 pt) + 2 pt gap + Reply (28 pt), centered vertically.
                let copyPoint = NSPoint(x: textFrame.minX - 70, y: textFrame.midY)
                let copyRect = surface.convert(NSRect(x: copyPoint.x - 14, y: copyPoint.y - 14, width: 28, height: 28), from: nil)
                func snapshot() -> NSBitmapImageRep {
                    let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)!
                    surface.cacheDisplay(in: surface.bounds, to: bitmap)
                    return bitmap
                }
                func pixels(_ bitmap: NSBitmapImageRep, in rect: NSRect) -> Data {
                    let scale = CGFloat(bitmap.pixelsWide) / surface.bounds.width
                    let crop = CGRect(x: rect.minX * scale,
                        y: (surface.bounds.height - rect.maxY) * scale,
                        width: rect.width * scale, height: rect.height * scale)
                    return NSBitmapImageRep(cgImage: bitmap.cgImage!.cropping(to: crop)!)
                        .representation(using: .png, properties: [:])!
                }
                let initialBitmap = snapshot()
                let hiddenCopy = pixels(initialBitmap, in: copyRect)
                let bubbleRect = initial.insetBy(dx: -18, dy: -14)
                let beforeBubble = pixels(initialBitmap, in: bubbleRect)
                print("Hover \(sampleIndex) \(name) initial: \(initial)")
                for index in 0..<12 {
                    let phase = index % 3
                    let point = phase == 0 ? text.convert(NSPoint(x: 20, y: 10), to: nil)
                        : phase == 1 ? copyPoint : NSPoint(x: 10, y: 10)
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    movePointer(window.convertPoint(toScreen: point))
                    try await Task.sleep(for: .milliseconds(240))
                    surface.layoutSubtreeIfNeeded()
                    let frame = text.convert(text.bounds, to: surface)
                    let bitmap = snapshot()
                    if index < 3 {
                        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/user-bubble-hover-\(sampleIndex)-\(name)-\(phase).png"))
                    }
                    print("Hover \(sampleIndex) \(name) \(index): \(frame), target=\(point), pointer=\(window.mouseLocationOutsideOfEventStream), key=\(window.isKeyWindow)")
                    precondition(abs(frame.width - initial.width) < 0.5 && abs(frame.height - initial.height) < 0.5
                        && abs(frame.minX - initial.minX) < 0.5 && abs(frame.minY - initial.minY) < 0.5,
                        "Hovering must not resize or move the user bubble")
                    precondition(answer.convert(answer.bounds, to: surface) == answerFrame,
                        "User hover must not move or resize the AI reply")
                    precondition(pixels(bitmap, in: bubbleRect) == beforeBubble,
                        "The rendered bubble must remain pixel-identical")
                    precondition((pixels(bitmap, in: copyRect) == hiddenCopy) == (phase == 2),
                        "Copy must appear on hover, stay visible over its button, then hide on exit")
                }
                if sampleIndex < 2 { precondition(initial.width < 130, "Short user text must hug content") }
                else { precondition(initial.height > 40, "Long user text must wrap") }
            }
        }
        print("User bubble hover passed: 72 native pointer transitions, copy visibility, stable user/AI frames and bubble pixels, reactions, short/emoji/long text, light/dark")
    }
}
