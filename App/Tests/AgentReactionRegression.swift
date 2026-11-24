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

        // User reacting to an AI bubble persists without starting a new agent turn.
        let reactionCID = try store.create(title: "用户给 AI 贴表情")
        let reactionUser = try store.append(conversationID: reactionCID, role: "user", text: "帮我总结一下")
        let reactionReply = try store.append(conversationID: reactionCID, role: "assistant", text: "已经为你总结好了。")
        model.open(reactionCID)
        let countBefore = model.items.count
        model.toggleUserReaction("👍", for: reactionReply.id)
        precondition(!model.isRunning, "User reacting to an AI bubble must not invoke the agent")
        precondition(model.items.count == countBefore, "User reacting must not append any reply")
        precondition(model.items.first { $0.id == reactionReply.id }?.userReaction == "👍")
        model.open(reactionCID)
        precondition(model.items.first { $0.id == reactionReply.id }?.userReaction == "👍", "History preserves user reactions on AI bubbles")
        model.setUserReaction("not-an-emoji", for: reactionReply.id)
        precondition(model.items.first { $0.id == reactionReply.id }?.userReaction == "👍", "Invalid non-emoji reaction is ignored")
        model.toggleUserReaction("❤️", for: reactionReply.id)
        precondition(model.items.first { $0.id == reactionReply.id }?.userReaction == "❤️", "Selecting a different emoji swaps the reaction")
        model.open(reactionCID)
        precondition(model.items.first { $0.id == reactionReply.id }?.userReaction == "❤️", "Swapped user reaction persists across reload")
        model.toggleUserReaction("❤️", for: reactionReply.id)
        precondition(model.items.first { $0.id == reactionReply.id }?.userReaction == nil, "Selecting the active reaction clears it")
        model.open(reactionCID)
        precondition(model.items.first { $0.id == reactionReply.id }?.userReaction == nil, "Cleared user reaction stays cleared")

        // Full emoji catalog integrity: every quick and expanded emoji must be valid and unique.
        precondition(ChatUserReactionCatalog.categories.count == 8, "Full emoji picker must expose 8 categories")
        var seenEmojis = Set<String>()
        for category in ChatUserReactionCatalog.categories {
            precondition(!category.emojis.isEmpty, "Category \(category.id) must not be empty")
            precondition(AgentReactionReply.isEmoji(category.icon), "Category icon \(category.icon) must be a valid emoji")
            for emoji in category.emojis {
                precondition(AgentReactionReply.isEmoji(emoji), "Catalog emoji \(emoji) in \(category.id) must pass AgentReactionReply.isEmoji")
                precondition(seenEmojis.insert(emoji).inserted, "Catalog emoji \(emoji) must not be duplicated")
            }
        }
        for quick in ChatUserReactionCatalog.quickEmojis {
            precondition(seenEmojis.contains(quick), "Quick emoji \(quick) must also exist in full catalog")
        }

        // User reacting with a non-quick emoji from the full catalog persists and toggles cleanly.
        model.toggleUserReaction("🚀", for: reactionReply.id)
        precondition(model.items.first { $0.id == reactionReply.id }?.userReaction == "🚀", "Expanded catalog emoji must attach cleanly")
        model.open(reactionCID)
        precondition(model.items.first { $0.id == reactionReply.id }?.userReaction == "🚀", "Expanded catalog emoji must survive reload")
        model.toggleUserReaction("🚀", for: reactionReply.id)
        precondition(model.items.first { $0.id == reactionReply.id }?.userReaction == nil, "Expanded catalog emoji must clear on second selection")

        // Deleting a single user message removes only that message and keeps the AI reply.
        let deleted = await model.deleteUserMessage(reactionUser.id)
        precondition(deleted, "Deleting an idle user message must succeed")
        precondition(!model.items.contains { $0.id == reactionUser.id })
        precondition(model.items.contains { $0.id == reactionReply.id }, "Deleting user message preserves AI reply")
        model.open(reactionCID)
        precondition(store.message(reactionUser.id, conversationID: reactionCID) == nil)
        precondition(model.items.contains { $0.id == reactionReply.id })

        print("Reaction regression passed: all three modes, completed-only presentation, history, cancellation, target isolation, user reactions on AI bubbles, and single user message deletion")
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
                // containing More (28 pt) + 2 pt gap + Copy (28 pt), centered vertically.
                let copyPoint = NSPoint(x: textFrame.minX - 40, y: textFrame.midY)
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

    static func bubbleMenuPreviewRegression() async throws {
        let originalPointer = NSEvent.mouseLocation
        func move(_ point: NSPoint) {
            CGWarpMouseCursorPosition(CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y))
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y),
                mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        func click(_ point: NSPoint, in window: NSWindow) async throws {
            let screen = window.convertPoint(toScreen: point)
            move(screen)
            try await Task.sleep(for: .milliseconds(160))
            let quartz = CGPoint(x: screen.x, y: NSScreen.screens[0].frame.maxY - screen.y)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartz,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
                try await Task.sleep(for: .milliseconds(80))
            }
            try await Task.sleep(for: .milliseconds(260))
        }
        defer { move(originalPointer) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-bubble-menu-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "气泡操作菜单")
        let userText = "帮我把今天的会议要点整理成三句话吧"
        let replyText = "好的，今天会议主要确定了三件事：本周完成设计联调、下周二提测、发布前保留一次全量回归。"
        let userMessage = try store.append(conversationID: cid, role: "user", text: userText)
        let model = AgentModel(app: app)
        model.open(cid)
        model.avatarColor = .blue
        model.beginResponse(taskID: "menu-turn")
        model.handle(.message(taskID: "menu-turn", "<asky-reaction>😊</asky-reaction>\n" + replyText), conversationID: cid)
        model.handle(.taskState(taskID: "menu-turn", .completed), conversationID: cid)
        model.finishTask(conversationID: cid)
        let replyID = model.items.first { $0.kind == .assistant }!.id
        model.setUserReaction("😂", for: replyID)

        // Add earlier/later turns so we also verify expanding the full picker upward from a lower bubble.
        let lowerUserText = "顺便帮我确认一下发布清单"
        let lowerReplyText = "没问题，发布前我们会核对变更日志、签名与公证状态、自动更新清单以及核心路径的回归测试结果。"
        try store.append(conversationID: cid, role: "user", text: "好的，还有其他需要提前准备的事项吗？")
        try store.append(conversationID: cid, role: "assistant", text: "建议提前冻结接口字段，并同步一份给测试同学核对边界用例。")
        try store.append(conversationID: cid, role: "user", text: lowerUserText)
        let lowerReply = try store.append(conversationID: cid, role: "assistant", text: lowerReplyText)
        model.open(cid)
        model.setUserReaction("😂", for: lowerReply.id)

        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApp.windows.first { $0.title == "Asky AI" && $0.isVisible }!
        defer { window.orderOut(nil) }
        if let screen = NSScreen.screens.first {
            let origin = NSPoint(
                x: max(screen.visibleFrame.minX + 24, screen.visibleFrame.maxX - window.frame.width - 24),
                y: max(screen.visibleFrame.minY + 24, screen.visibleFrame.midY - window.frame.height / 2)
            )
            window.setFrameOrigin(origin)
        }
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let backing = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        backing.backgroundColor = NSColor(white: 0.25, alpha: 1)
        backing.level = .floating
        backing.order(.below, relativeTo: window.windowNumber)
        defer { backing.orderOut(nil) }

        func capture(_ name: String) throws {
            let path = "build/bubble-menu-\(name).png"
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            let rect = window.frame
            capture.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(NSScreen.screens[0].frame.maxY - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))", path]
            try capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0)
        }

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            backing.backgroundColor = name == "light" ? NSColor(white: 0.90, alpha: 1) : NSColor(white: 0.16, alpha: 1)
            window.makeKeyAndOrderFront(nil)
            backing.order(.below, relativeTo: window.windowNumber)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(600))
            let surface = window.contentView!
            let texts = descendants(surface).compactMap { $0 as? NSTextView }
            let userView = texts.first { $0.string == userText }!
            let replyView = texts.first { $0.string == replyText }!
            let lowerReplyView = texts.first { $0.string == lowerReplyText }!
            let userFrame = userView.convert(userView.bounds, to: nil)
            let replyFrame = replyView.convert(replyView.bounds, to: nil)
            let lowerReplyFrame = lowerReplyView.convert(lowerReplyView.bounds, to: nil)

            // 1. Hover top AI bubble -> click Emoji button -> capture quick bar, then expand downward.
            window.makeKeyAndOrderFront(nil)
            move(window.convertPoint(toScreen: NSPoint(x: replyFrame.midX, y: replyFrame.midY)))
            try await Task.sleep(for: .milliseconds(250))
            let aiBarLeft = replyFrame.maxX + 18 + 8
            let aiEmojiPoint = NSPoint(x: aiBarLeft + 14, y: replyFrame.midY)
            let aiMorePoint = NSPoint(x: aiBarLeft + 72, y: replyFrame.midY)
            try await click(aiEmojiPoint, in: window)
            try capture("emoji-\(name)")

            // Click '+' at the right end of the quick bar (clamped near right edge: 560 - 12 - 20 = 528).
            let topExpandPoint = NSPoint(x: min(560 - 12 - 20, aiEmojiPoint.x + 102), y: replyFrame.midY + 14 + 6 + 20)
            try await click(topExpandPoint, in: window)
            try await Task.sleep(for: .milliseconds(250))
            try capture("emoji-expanded-below-\(name)")

            // Dismiss, then hover lower AI bubble -> click Emoji -> click '+' to expand upward (above quick bar).
            try await click(NSPoint(x: 20, y: 200), in: window)
            model.setUserReaction("😂", for: lowerReply.id)
            try await Task.sleep(for: .milliseconds(120))
            window.makeKeyAndOrderFront(nil)
            move(window.convertPoint(toScreen: NSPoint(x: lowerReplyFrame.midX, y: lowerReplyFrame.midY)))
            try await Task.sleep(for: .milliseconds(250))
            let lowerBarLeft = lowerReplyFrame.maxX + 18 + 8
            let lowerEmojiPoint = NSPoint(x: lowerBarLeft + 14, y: lowerReplyFrame.midY)
            try await click(lowerEmojiPoint, in: window)
            let lowerExpandPoint = NSPoint(x: min(560 - 12 - 20, lowerEmojiPoint.x + 102), y: lowerReplyFrame.midY + 14 + 6 + 20)
            try await click(lowerExpandPoint, in: window)
            try await Task.sleep(for: .milliseconds(280))
            try capture("emoji-expanded-above-\(name)")

            // Scroll wheel inside the expanded full panel must not dismiss it; clicking a category tab jumps sections;
            // clicking an emoji cell inside the expanded grid selects that reaction.
            let panelRight = 560.0 - 12.0
            let panelLeft = panelRight - 306.0
            let quickBarTopAppKit = lowerReplyFrame.midY + 14 + 6 + 40
            let panelBottomAppKit = quickBarTopAppKit + 8
            let panelTopAppKit = panelBottomAppKit + 310
            let scrollCenter = NSPoint(x: (panelLeft + panelRight) / 2, y: (panelBottomAppKit + panelTopAppKit) / 2)
            move(window.convertPoint(toScreen: scrollCenter))
            try await Task.sleep(for: .milliseconds(100))
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(180))
            // Click the 7th category tab (🚀 Travel & Places) at the top bar of the expanded panel.
            let travelTabPoint = NSPoint(x: panelLeft + 10 + 6 * 36 + 17, y: panelTopAppKit - 22)
            try await click(travelTabPoint, in: window)
            try await Task.sleep(for: .milliseconds(260))
            try capture("emoji-expanded-category-\(name)")
            // Click the first visible emoji cell in the Travel & Places section (🚗) and verify reaction updates.
            let firstCellPoint = NSPoint(x: panelLeft + 10 + 17, y: panelTopAppKit - 45 - 42)
            try await click(firstCellPoint, in: window)
            try await Task.sleep(for: .milliseconds(220))
            let updatedReaction = model.items.first { $0.id == lowerReply.id }?.userReaction
            precondition(updatedReaction != nil && updatedReaction != "😂",
                         "Clicking an emoji inside the expanded picker must update the message reaction (got \(String(describing: updatedReaction)))")
            model.setUserReaction("😂", for: lowerReply.id)

            // Dismiss then open AI More menu
            try await click(NSPoint(x: 20, y: 200), in: window)
            window.makeKeyAndOrderFront(nil)
            move(window.convertPoint(toScreen: NSPoint(x: replyFrame.midX, y: replyFrame.midY)))
            try await Task.sleep(for: .milliseconds(250))
            try await click(aiMorePoint, in: window)
            try capture("assistant-more-\(name)")

            // Dismiss then open User More menu (first button in 58pt bar left of user bubble)
            try await click(NSPoint(x: 20, y: 200), in: window)
            window.makeKeyAndOrderFront(nil)
            move(window.convertPoint(toScreen: NSPoint(x: userFrame.midX, y: userFrame.midY)))
            try await Task.sleep(for: .milliseconds(250))
            let userMorePoint = NSPoint(x: userFrame.minX - 18 - 8 - 44, y: userFrame.midY)
            try await click(userMorePoint, in: window)
            try capture("user-more-\(name)")

            // Dismiss
            try await click(NSPoint(x: 20, y: 200), in: window)
            _ = userMessage
        }
        print("Bubble menu visual preview captured in light and dark")
    }

    static func reactionSwapPreviewRegression() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-reaction-swap-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "表情切换动效预览")
        let userText = "谢谢 🤖"
        let replyText = "短 AI 回复也应保持宽度。"
        try store.append(conversationID: cid, role: "user", text: userText)
        let model = AgentModel(app: app)
        model.open(cid)
        model.avatarColor = .yellow
        model.beginResponse(taskID: "swap-turn")
        model.handle(.message(taskID: "swap-turn", "<asky-reaction>🤖</asky-reaction>\n" + replyText), conversationID: cid)
        model.handle(.taskState(taskID: "swap-turn", .completed), conversationID: cid)
        model.finishTask(conversationID: cid)
        let replyID = model.items.first { $0.kind == .assistant }!.id
        model.setUserReaction("👍", for: replyID)

        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApp.windows.first { $0.title == "Asky AI" && $0.isVisible }!
        defer { window.orderOut(nil) }
        if let screen = NSScreen.screens.first {
            let origin = NSPoint(
                x: max(screen.visibleFrame.minX + 24, screen.visibleFrame.maxX - window.frame.width - 24),
                y: max(screen.visibleFrame.minY + 24, screen.visibleFrame.midY - window.frame.height / 2)
            )
            window.setFrameOrigin(origin)
        }
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let backing = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        backing.level = .floating
        backing.order(.below, relativeTo: window.windowNumber)
        defer { backing.orderOut(nil) }

        func capture(_ name: String) throws {
            let path = "build/reaction-swap-\(name).png"
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            let rect = window.frame
            capture.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(NSScreen.screens[0].frame.maxY - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))", path]
            try capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0)
        }

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            backing.backgroundColor = name == "light" ? NSColor(white: 0.90, alpha: 1) : NSColor(white: 0.16, alpha: 1)
            model.setUserReaction("👍", for: replyID)
            try await Task.sleep(for: .milliseconds(550))
            try capture("before-\(name)")

            // Trigger dedicated emoji swap animation and capture early, peak, and settled states.
            model.toggleUserReaction("❤️", for: replyID)
            try await Task.sleep(for: .milliseconds(75))
            try capture("early-\(name)")
            try await Task.sleep(for: .milliseconds(75))
            try capture("peak-\(name)")
            try await Task.sleep(for: .milliseconds(400))
            try capture("after-\(name)")
            precondition(model.items.first { $0.id == replyID }?.userReaction == "❤️")
        }
        print("Reaction swap preview passed in light and dark")
    }

    static func deleteDialogPreviewRegression() async throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-delete-dialog-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "删除确认弹窗")
        try store.append(conversationID: cid, role: "user", text: "帮我整理一下最近的产品节奏和优先级")
        let longReply = """
        时间要对齐：8 月是组织重组加外部唱衰，10 月才出新版本节奏。至于“清理没啥用的人”这个说法，我倾向于先看核心链路与产出，而不是简单做减法。

        前面聊的几个方向里，最值得优先推进的是第一项：把高频交互的视觉层次与动效统一起来，这正是提升整体完成度的关键。
        """
        let reply = try store.append(conversationID: cid, role: "assistant", text: longReply)
        let targetUser = try store.append(conversationID: cid, role: "user", text: "帮我给我妈发一个短信，说我给她买的牛排明天到")

        let model = AgentModel(app: app)
        model.open(cid)
        model.avatarColor = .blue

        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApp.windows.first { $0.title == "Asky AI" && $0.isVisible }!
        defer { window.orderOut(nil) }
        if let screen = NSScreen.screens.first {
            let origin = NSPoint(
                x: max(screen.visibleFrame.minX + 24, screen.visibleFrame.maxX - window.frame.width - 24),
                y: max(screen.visibleFrame.minY + 24, screen.visibleFrame.midY - window.frame.height / 2)
            )
            window.setFrameOrigin(origin)
        }
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let backing = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        backing.level = .floating
        backing.order(.below, relativeTo: window.windowNumber)
        defer { backing.orderOut(nil) }

        func capture(_ name: String) throws {
            let path = "build/delete-dialog-\(name).png"
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            let rect = window.frame
            capture.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(NSScreen.screens[0].frame.maxY - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))", path]
            try capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0)
        }

        // Wait for initial window presentation and activation before opening the dialog.
        try await Task.sleep(for: .milliseconds(450))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(250))

        let targetItem = model.items.first { $0.id == targetUser.id }!
        model.confirmAndDeleteUserMessage(targetItem)
        precondition(model.pendingDeleteMessage?.id == targetUser.id)

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            backing.backgroundColor = name == "light" ? NSColor(white: 0.90, alpha: 1) : NSColor(white: 0.14, alpha: 1)
            backing.order(.below, relativeTo: window.windowNumber)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(550))
            window.contentView?.layoutSubtreeIfNeeded()
            precondition(!(window.firstResponder is NSTextView),
                         "Composer text view must not keep focus while delete dialog is open in \(name) mode")

            let surface = window.contentView!
            let buttons = descendants(surface).compactMap { $0 as? NSButton }
            let cancelButton = buttons.first { $0.accessibilityIdentifier() == "chat-delete-confirm-cancel" }
            let deleteButton = buttons.first { $0.accessibilityIdentifier() == "chat-delete-confirm-delete" }
            let closeButton = buttons.first { $0.accessibilityIdentifier() == "chat-delete-confirm-close" }
            precondition(cancelButton != nil && deleteButton != nil && closeButton != nil,
                         "Delete confirmation dialog buttons must be present in \(name) mode")
            let cancelFrame = cancelButton!.convert(cancelButton!.bounds, to: surface)
            let deleteFrame = deleteButton!.convert(deleteButton!.bounds, to: surface)
            let pairMidX = (cancelFrame.minX + deleteFrame.maxX) / 2
            precondition(abs(pairMidX - surface.bounds.midX) < 3,
                         "Delete confirmation dialog must stay horizontally centered (pairMidX=\(pairMidX), midX=\(surface.bounds.midX))")
            precondition(abs(cancelFrame.width - deleteFrame.width) < 1.5,
                         "Cancel and Delete buttons must share equal width (\(cancelFrame.width) vs \(deleteFrame.width))")
            try capture(name)
        }

        // Escape cancels ONLY the dialog, keeping the Agent window visible and preserving the message.
        let escEvent = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        )!
        NSApp.sendEvent(escEvent)
        try await Task.sleep(for: .milliseconds(220))
        precondition(model.pendingDeleteMessage == nil, "Escape must dismiss the delete dialog")
        precondition(window.isVisible, "Escape on delete dialog must not close the Agent window")
        precondition(model.items.contains { $0.id == targetUser.id }, "Cancelling must preserve the user message")

        // Clicking outside cancels without deleting.
        model.confirmAndDeleteUserMessage(targetItem)
        try await Task.sleep(for: .milliseconds(260))
        precondition(model.pendingDeleteMessage?.id == targetUser.id)
        let outsideClick = NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 24, y: 24), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
        NSApp.sendEvent(outsideClick)
        try await Task.sleep(for: .milliseconds(220))
        precondition(model.pendingDeleteMessage == nil, "Clicking outside must dismiss the delete dialog")
        precondition(model.items.contains { $0.id == targetUser.id }, "Outside click must preserve the user message")

        // Re-open and confirm via the Delete button removes only the targeted user message.
        model.confirmAndDeleteUserMessage(targetItem)
        try await Task.sleep(for: .milliseconds(300))
        let surface = window.contentView!
        let deleteButton = descendants(surface).compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "chat-delete-confirm-delete" }!
        deleteButton.performClick(nil)
        for _ in 0..<40 where model.items.contains(where: { $0.id == targetUser.id }) {
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(model.pendingDeleteMessage == nil, "Confirming must dismiss the delete dialog")
        precondition(!model.items.contains { $0.id == targetUser.id }, "Confirming must delete the targeted user message")
        precondition(model.items.contains { $0.id == reply.id }, "Confirming must preserve sibling AI replies")
        precondition(store.message(targetUser.id, conversationID: cid) == nil, "Deleted message must be removed from store")
        print("Delete confirmation dialog regression passed in light and dark")
    }
}
