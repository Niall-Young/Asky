import AppKit
import AgentHost
import LocalStore
import SwiftUI
import Contracts
import ToolService

@main
@MainActor
enum AgentReplyRegression {
    static func bubbleWidthPreview(app: AppModel) async throws {
        let sample = "给你这条消息贴了个 💬，表示要发短信这件事。"
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Bubble width")
        try store.append(conversationID: cid, role: "user", text: "发短信")
        try store.append(conversationID: cid, role: "assistant", text: sample)
        let model = AgentModel(app: app)
        model.open(cid)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApplication.shared.windows.first { $0.title == "Asky AI" }!
        defer { window.orderOut(nil) }
        func texts(_ node: NSView) -> [NSTextView] {
            (node as? NSTextView).map { [$0] } ?? node.subviews.flatMap(texts)
        }
        try await Task.sleep(for: .milliseconds(600))
        let reply = texts(window.contentView!).first { $0.string == sample }!
        let question = texts(window.contentView!).first { $0.string == "发短信" }!
        precondition(question.bounds.width < 60, "Short user messages must also hug their text in the trailing HStack")
        precondition(reply.bounds.width < 380, "Short reply must not stretch to the available 460 pt")
        precondition(reply.bounds.height < 40, "The supplied short reply must stay on one line")
        let surface = window.contentView!
        let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)!
        surface.cacheDisplay(in: surface.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/bubble-width-chat.png"))

        // Capture the running typing indicator for visual alignment review.
        model.beginResponse(taskID: "typing-alignment")
        try await Task.sleep(for: .milliseconds(350))
        window.contentView?.layoutSubtreeIfNeeded()
        let typingBitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)!
        surface.cacheDisplay(in: surface.bounds, to: typingBitmap)
        try typingBitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/typing-bubble-alignment.png"))
        model.finishTask(conversationID: cid)

        for width: CGFloat in [280, 460] {
            for content in [sample, "**粗体**、`code` 和 💬", String(repeating: "长回复需要正常换行。", count: 12)] {
                let hosted = NSHostingView(rootView: ChatReplyView(text: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
                let fixture = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: 500),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                fixture.contentView = hosted
                fixture.orderFront(nil)
                try await Task.sleep(for: .milliseconds(120))
                hosted.layoutSubtreeIfNeeded()
                let text = texts(hosted).first!
                let used = text.layoutManager!.usedRect(for: text.textContainer!)
                precondition(text.bounds.width <= width + 1, "Text must respect the offered maximum")
                precondition(used.width <= text.bounds.width + 1 && used.height <= text.bounds.height,
                    "Rich text and wrapped lines must not clip")
                if content.count > 100 {
                    precondition(text.bounds.height > 40, "Long replies must wrap")
                } else if content.contains("粗体") {
                    precondition(text.bounds.width < 200, "Styled short replies must also hug their content")
                }
                fixture.orderOut(nil)
            }
        }
        // A minimum-width marker must not claim half the width of a long list item.
        let listSample = """
        - 各家渠道对 Astra 的报价差异不小（有 $2/$10 的分档报价，也有 $10/$50 的官方价），我按 OpenAI 官方的挂牌价讲；第三方聚合平台的价格会随缓存、长上下文档位变化。
        - 9 月之后又陆续出了 Sol、Luna、6.1 Sol、6.1 Terra 和 11 月初的网络安全专项 GPT-6 Cyber。11 月是否还有更新的通用旗舰，我这次没检索到可靠信息，不替你打包票。
        """
        for width: CGFloat in [280, 460] {
            for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                let content = listSample + "\n\n98. 编号正文需要使用标记之外的可用宽度。\n99. 第二项\n100. 三位编号\n     - 嵌套正文\n"
                let hosted = NSHostingView(rootView: ChatMarkdownView(text: content)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(scheme == .dark ? Color(white: 0.15) : .white)
                    .environment(\.colorScheme, scheme))
                let fixture = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: 760),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                fixture.contentView = hosted
                fixture.orderFront(nil)
                defer { fixture.orderOut(nil) }
                try await Task.sleep(for: .milliseconds(180))
                hosted.layoutSubtreeIfNeeded()
                let views = texts(hosted)
                let path = "build/list-width-\(Int(width))-\(name).png"
                let bitmap = hosted.bitmapImageRepForCachingDisplay(in: hosted.bounds)!
                hosted.cacheDisplay(in: hosted.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: path))
                let paragraph = views.first { $0.string.hasPrefix("各家渠道") }!
                let frame = paragraph.convert(paragraph.bounds, to: hosted)
                print("List width \(width) \(name): body x=\(frame.minX), width=\(frame.width)")
                precondition(frame.minX <= 50, "Bullet must not consume half the paragraph width")
                precondition(frame.width >= width - 70, "Long list prose must use the remaining width")
                let nested = views.first { $0.string == "嵌套正文" }!
                let nestedFrame = nested.convert(nested.bounds, to: hosted)
                precondition(nestedFrame.minX > frame.minX && nestedFrame.minX < 100,
                    "Nested lists must add only one marker column")
                let ordered = views.filter { ["98.", "99.", "100."].contains($0.string) }
                precondition(ordered.count == 3)
                let rightEdges = ordered.map { $0.convert($0.bounds, to: hosted).maxX }
                precondition(rightEdges.max()! - rightEdges.min()! <= 1, "Number markers must stay right-aligned")
                for text in views {
                    let used = text.layoutManager!.usedRect(for: text.textContainer!)
                    precondition(used.width <= text.bounds.width + 1 && used.height <= text.bounds.height,
                        "List text and markers must not clip")
                }
            }
        }
        print("Bubble widths passed: actual chat screenshot, short Chinese/emoji, styled text, long wrapping, bullet/numbered/nested lists in light/dark at 280/460 pt")
    }

    static func tableFadePreview(app: AppModel) async throws {
        let fitting = ChatTableScrollFade.resolve(visibleMinX: 0, visibleMaxX: 460, contentMinX: 0, contentMaxX: 320)
        precondition(fitting == ChatTableScrollFade(leading: 0, trailing: 0), "Non-overflowing tables must not fade")
        let start = ChatTableScrollFade.resolve(visibleMinX: 0, visibleMaxX: 460, contentMinX: 0, contentMaxX: 600)
        precondition(start == ChatTableScrollFade(leading: 0, trailing: 1), "Unscrolled wide tables must fade only trailing edge")
        let middle = ChatTableScrollFade.resolve(visibleMinX: 70, visibleMaxX: 530, contentMinX: 0, contentMaxX: 600)
        precondition(middle == ChatTableScrollFade(leading: 1, trailing: 1), "Mid-scrolled wide tables must fade both edges")
        let end = ChatTableScrollFade.resolve(visibleMinX: 140, visibleMaxX: 600, contentMinX: 0, contentMaxX: 600)
        precondition(end == ChatTableScrollFade(leading: 1, trailing: 0), "End-scrolled wide tables must clear trailing fade")
        let subpixel = ChatTableScrollFade.resolve(visibleMinX: 0.3, visibleMaxX: 599.7, contentMinX: 0, contentMaxX: 600)
        precondition(subpixel == ChatTableScrollFade(leading: 0, trailing: 0), "Sub-pixel rounding must not trigger edge fades")
        let ramp = ChatTableScrollFade.resolve(visibleMinX: 0, visibleMaxX: 595.5, contentMinX: 0, contentMaxX: 600)
        precondition(abs(ramp.trailing - 0.5) < 0.01 && ramp.leading == 0, "Fade must ramp smoothly over the final 8 pt")

        var lock = ChatTableScrollAxisLock()
        precondition(lock.evaluate(dx: 0, dy: 0, phase: .mayBegin, momentumPhase: []) == .passThrough)
        precondition(lock.evaluate(dx: 0, dy: 0, phase: .began, momentumPhase: []) == .passThrough)
        precondition(lock.evaluate(dx: -8, dy: -1, phase: .changed, momentumPhase: []) == .lockHorizontal)
        precondition(lock.evaluate(dx: -2, dy: -3, phase: .changed, momentumPhase: []) == .lockHorizontal,
            "Mid-gesture vertical wobble must stay locked to horizontal")
        precondition(lock.evaluate(dx: 0, dy: 2, phase: .changed, momentumPhase: []) == .lockHorizontal,
            "Pausing or reversing horizontally must not leak vertical scroll")
        precondition(lock.evaluate(dx: 0, dy: 0, phase: .ended, momentumPhase: []) == .lockHorizontal)
        precondition(lock.evaluate(dx: -3, dy: -2, phase: [], momentumPhase: .changed) == .lockHorizontal,
            "Momentum after a horizontal swipe must also strip vertical drift")
        precondition(lock.evaluate(dx: 0, dy: 0, phase: [], momentumPhase: .ended) == .lockHorizontal)
        precondition(!lock.isTrackingHorizontal, "Axis lock must reset after momentum ends")
        precondition(lock.evaluate(dx: -1, dy: -8, phase: .began, momentumPhase: []) == .passThrough)
        precondition(lock.evaluate(dx: -6, dy: -2, phase: .changed, momentumPhase: []) == .passThrough,
            "Vertical gestures over a table must stay unlocked for transcript scrolling")
        precondition(lock.evaluate(dx: 0, dy: -4, phase: [], momentumPhase: []) == .passThrough,
            "Pure vertical discrete wheel must pass through to transcript")
        precondition(lock.evaluate(dx: -10, dy: -2, phase: [], momentumPhase: []) == .lockHorizontal,
            "Horizontal discrete wheel must strip vertical noise")

        let wideTable = """
        | 模型 | 输入 | 输出（含思考 token） | 缓存读取 | 上下文窗口 |
        | --- | --- | --- | --- | --- |
        | **Gemini 4 Hydrogen** | $1.50 | $7.50 | $0.375 | 1M |
        | **Gemini 4 Carbon**（到 11/30） | $2.00 | $10.00 | $0.50 | 1M |
        | **Gemini 4 Carbon**（12/1 起） | $4.00 | $20.00 | $1.00 | 1M |
        | **Gemini 4 Neon** | $3.00 | $15.00 | $0.75 | 1M |

        | 功能 | 状态 |
        | --- | --- |
        | Markdown | 支持 |
        """

        func scrollViews(_ node: NSView) -> [NSScrollView] {
            var list: [NSScrollView] = []
            if let scroll = node as? NSScrollView { list.append(scroll) }
            for subview in node.subviews { list.append(contentsOf: scrollViews(subview)) }
            return list
        }

        func textViews(_ node: NSView) -> [ChatSelectableTextView] {
            var list: [ChatSelectableTextView] = []
            if let text = node as? ChatSelectableTextView { list.append(text) }
            for subview in node.subviews { list.append(contentsOf: textViews(subview)) }
            return list
        }

        func observerViews(_ node: NSView) -> [ChatTableScrollObserver.ObserverView] {
            var list: [ChatTableScrollObserver.ObserverView] = []
            if let observer = node as? ChatTableScrollObserver.ObserverView { list.append(observer) }
            for subview in node.subviews { list.append(contentsOf: observerViews(subview)) }
            return list
        }

        func makeTrackpadScroll(dx: Double, dy: Double, phase: Int64) -> NSEvent {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)!
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.timestamp = DispatchTime.now().uptimeNanoseconds
            return NSEvent(cgEvent: cg)!
        }

        // Verify in the real Agent chat window (nested inside the vertical transcript ScrollView + Liquid Glass).
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Table horizontal fade")
        try store.append(conversationID: cid, role: "user", text: "对比一下几个模型的价格")
        try store.append(conversationID: cid, role: "assistant", text: wideTable)
        let model = AgentModel(app: app)
        model.open(cid)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.show()
        let chatWindow = NSApplication.shared.windows.last { $0.title == "Asky AI" && $0.isVisible }!
        chatWindow.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(700))
        let chatScrolls = scrollViews(chatWindow.contentView!).filter {
            ($0.documentView?.bounds.width ?? 0) > $0.documentVisibleRect.width + 5
        }
        precondition(!chatScrolls.isEmpty, "Real chat window must host the horizontally overflowing table ScrollView")
        let cellText = textViews(chatScrolls[0]).first { $0.string.contains("Gemini 4 Hydrogen") }!
        cellText.setSelectedRange(NSRange(location: 0, length: 6))
        precondition(cellText.selectedRange().length == 6, "Table cells inside masked ScrollView must remain selectable")
        cellText.setSelectedRange(NSRange(location: 0, length: 0))
        let surface = chatWindow.contentView!
        let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)!
        surface.cacheDisplay(in: surface.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/table-fade-chat.png"))
        chatWindow.close()

        // Verify horizontal table swipes with vertical wobble never jitter the enclosing transcript ScrollView.
        let tallID = try store.create(title: "Table horizontal stability")
        let fillerTop = String(repeating: "上文段落，用来让外层对话流具备上下滚动空间。\n\n", count: 6)
        let fillerBottom = String(repeating: "下文段落，用来验证表上垂直滚动仍可正常驱动外层对话流。\n\n", count: 6)
        try store.append(conversationID: tallID, role: "user", text: "对比一下几个模型的价格")
        try store.append(conversationID: tallID, role: "assistant", text: fillerTop + wideTable + "\n\n" + fillerBottom)
        let tallModel = AgentModel(app: app)
        tallModel.open(tallID)
        let tallController = AgentWindowController(model: tallModel, presentation: WindowPresentation())
        NSApplication.shared.activate(ignoringOtherApps: true)
        tallController.show()
        let tallWindow = NSApplication.shared.windows.last { $0.title == "Asky AI" && $0.isVisible }!
        tallWindow.makeKeyAndOrderFront(nil)
        defer { tallWindow.close() }
        try await Task.sleep(for: .milliseconds(1100))
        let tallTableScroll = scrollViews(tallWindow.contentView!).last {
            ($0.documentView?.bounds.width ?? 0) > $0.documentVisibleRect.width + 5
        }!
        let outerScroll = tallTableScroll.enclosingScrollView!
        let observer = observerViews(tallTableScroll).first!
        let tallCell = textViews(tallTableScroll).first { $0.string.contains("Gemini 4 Hydrogen") }!
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: outerScroll)
        let tableInDoc = outerScroll.documentView!.convert(tallTableScroll.bounds, from: tallTableScroll)
        let startOuterY = max(0, tableInDoc.midY - outerScroll.contentView.bounds.height / 2)
        outerScroll.contentView.scroll(to: NSPoint(x: 0, y: startOuterY))
        outerScroll.reflectScrolledClipView(outerScroll.contentView)
        try await Task.sleep(for: .milliseconds(150))

        func dispatchFiltered(_ event: NSEvent) {
            if !observer.consumeScrollEvent(event, hitView: tallCell) {
                tallCell.scrollWheel(with: event)
            }
        }
        // Swipe to the right edge (overscroll) and immediately swipe back with realistic vertical wobble.
        dispatchFiltered(makeTrackpadScroll(dx: 0, dy: 0, phase: 128))
        for i in 0..<24 {
            let phase: Int64 = i == 0 ? 1 : (i == 23 ? 4 : 2)
            dispatchFiltered(makeTrackpadScroll(dx: i == 23 ? 0 : -10, dy: 0, phase: phase))
            try await Task.sleep(for: .milliseconds(12))
        }
        precondition(tallTableScroll.documentVisibleRect.minX > 40, "Horizontal table swipe must scroll the table")
        let wobble: [(Double, Double)] = [
            (8, -1), (8, -2), (6, -3), (4, -3), (2, -3), (1, -3),
            (6, 2), (8, 3), (4, 3), (2, 3), (1, 3), (8, -2), (0, 0)
        ]
        dispatchFiltered(makeTrackpadScroll(dx: 0, dy: 0, phase: 128))
        for (i, delta) in wobble.enumerated() {
            let phase: Int64 = i == 0 ? 1 : (i == wobble.count - 1 ? 4 : 2)
            dispatchFiltered(makeTrackpadScroll(dx: delta.0, dy: delta.1, phase: phase))
            try await Task.sleep(for: .milliseconds(16))
            precondition(abs(outerScroll.contentView.bounds.origin.y - startOuterY) < 0.01,
                "Horizontal table swipe must not jitter outer transcript vertically: expected \(startOuterY), got \(outerScroll.contentView.bounds.origin.y)")
        }
        try await Task.sleep(for: .milliseconds(180))
        precondition(abs(outerScroll.contentView.bounds.origin.y - startOuterY) < 0.01,
            "Ending a horizontal table swipe must not trigger vertical transcript momentum: expected \(startOuterY), got \(outerScroll.contentView.bounds.origin.y)")
        // Verify vertical scrolling over the table still scrolls the enclosing transcript.
        dispatchFiltered(makeTrackpadScroll(dx: 0, dy: 0, phase: 128))
        for i in 0..<6 {
            let phase: Int64 = i == 0 ? 1 : (i == 5 ? 4 : 2)
            dispatchFiltered(makeTrackpadScroll(dx: 0, dy: i == 5 ? 0 : -12, phase: phase))
            try await Task.sleep(for: .milliseconds(16))
        }
        precondition(outerScroll.contentView.bounds.origin.y > startOuterY + 10,
            "Vertical scrolling over a wide table must still scroll the outer transcript")

        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let content = VStack(alignment: .leading, spacing: 0) {
                ChatMarkdownView(text: wideTable)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(width: 496, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16).fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)))
            .padding(20)
            .frame(width: 536, height: 360, alignment: .topLeading)
            .background(scheme == .dark ? Color(white: 0.14) : Color(white: 0.94))
            .environment(\.colorScheme, scheme)

            let hosted = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: 160, y: 200, width: 536, height: 360),
                styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = hosted
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(350))
            hosted.layoutSubtreeIfNeeded()

            let scrolls = scrollViews(hosted).filter { ($0.documentView?.bounds.width ?? 0) > $0.documentVisibleRect.width + 5 }
            precondition(!scrolls.isEmpty, "Wide table must overflow horizontally in \(name) mode")
            let wideScroll = scrolls[0]
            let maxX = max(0, (wideScroll.documentView?.bounds.width ?? 0) - wideScroll.documentVisibleRect.width)
            print("Table fade \(name): docWidth=\(wideScroll.documentView?.bounds.width ?? 0), visibleWidth=\(wideScroll.documentVisibleRect.width), maxX=\(maxX)")

            func capture(_ suffix: String) throws {
                let proc = Process()
                proc.executableURL = URL(filePath: "/usr/sbin/screencapture")
                proc.arguments = ["-x", "-o", "-l", String(window.windowNumber), "build/table-fade-\(name)-\(suffix).png"]
                try proc.run(); proc.waitUntilExit()
                precondition(proc.terminationStatus == 0)
            }

            try capture("start")

            wideScroll.contentView.scroll(to: NSPoint(x: maxX * 0.5, y: 0))
            wideScroll.reflectScrolledClipView(wideScroll.contentView)
            try await Task.sleep(for: .milliseconds(250))
            try capture("mid")

            wideScroll.contentView.scroll(to: NSPoint(x: maxX, y: 0))
            wideScroll.reflectScrolledClipView(wideScroll.contentView)
            try await Task.sleep(for: .milliseconds(250))
            try capture("end")
        }
        print("Table fade preview passed: real chat window, table selection, and light/dark start, mid, and end states")
    }

    static func sourcesPreview() async throws {
        precondition(ChatSourceTextView.badgeLabel(name: "Cognition", count: 2) == "Cognition +1")
        precondition(ChatSourceTextView.badgeLabel(name: "Kimi", count: 4) == "Kimi +3")
        precondition(ChatSourceTextView.badgeLabel(name: "Kimi", count: 1) == "Kimi")
        precondition(ChatSourceTextView.isCitation("[12]"))
        precondition(ChatSourceTextView.isCitation("来源"))
        precondition(!ChatSourceTextView.isCitation("打开官网"))
        let screen = NSRect(x: -1200, y: -200, width: 1200, height: 900)
        let viewport = NSRect(x: -1000, y: 0, width: 640, height: 500)
        for anchor in [NSRect(x: -500, y: 20, width: 18, height: 18), NSRect(x: -30, y: 450, width: 18, height: 18)] {
            let frame = ChatSourcePopover.frame(size: NSSize(width: 300, height: 260), anchor: anchor, screen: screen, viewport: viewport)
            precondition(screen.contains(frame), "Card must fit its source's screen, including negative origins")
            if anchor.minY < 100 { precondition(frame.minY >= anchor.maxY + 8, "Low sources must open upward") }
        }
        let linked = try AttributedString(markdown: "[Moonshot AI 官网](https://example.com) 与 [来源](https://example.com)")
        precondition(ChatSourceTextView.sources(in: linked).count == 1, "Repeated links in one information block share one favicon")

        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 440),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Asky Source Preview"
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let view = NSHostingView(rootView: ChatMarkdownView(text: """
            ## 联网搜索结果
            安全仪表盘可以查看扫描结果、风险和修复进度。[1](https://devin.ai/) [2](https://example.com/security) [3](https://devin.ai/docs) [4](https://example.com/news)

            - **扫描**：核对权限边界，找出潜在漏洞。[来源](https://devin.ai/)
            - **修复**：使用 `Fix with Devin` 创建修复任务。[2](https://devin.ai/)

            [打开官网](https://devin.ai/) 查看详细信息。
            """).padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(scheme == .dark ? Color(white: 0.15) : .white).environment(\.colorScheme, scheme))
            if scheme == .dark {
                // Exercise a real clip-view offset and a source close to the viewport bottom.
                let document = NSHostingView(rootView: VStack(spacing: 0) {
                    Color.clear.frame(height: 500)
                    ChatMarkdownView(text: "[Wikipedia：Moonshot AI](https://devin.ai/)：Kimi 通过网页、API 和移动端提供服务，并支持图像和视频等多模态输入。")
                        .padding(28)
                    Color.clear.frame(height: 300)
                }.frame(width: 640, alignment: .topLeading).background(Color(white: 0.15)).environment(\.colorScheme, .dark))
                document.frame = NSRect(x: 0, y: 0, width: 640, height: 950)
                let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 440))
                scroll.hasVerticalScroller = true
                scroll.documentView = document
                window.contentView = scroll
                document.layoutSubtreeIfNeeded()
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
                scroll.reflectScrolledClipView(scroll.contentView)
            } else { window.contentView = view }
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(500))
            view.layoutSubtreeIfNeeded()
            var badges = 0
            var sourceText: ChatSourceTextView?
            func inspect(_ node: NSView) {
                if let text = node as? ChatSourceTextView, let storage = text.textStorage {
                    var firstSource: Int?
                    storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                        guard let attachment = value as? NSTextAttachment,
                              storage.attribute(.chatSelectionText, at: range.location, effectiveRange: nil) == nil else { return }
                        precondition(attachment.image == nil && attachment.attachmentCell != nil,
                                     "Source badge must draw via vector attachment cell rather than resampled NSImage")
                        if sourceText == nil { sourceText = text }
                        badges += 1
                        if firstSource == nil { firstSource = range.location }
                        precondition(storage.attribute(.link, at: range.location, effectiveRange: nil) as? URL != nil)
                        let sources = storage.attribute(.chatSources, at: range.location, effectiveRange: nil) as! [URL]
                        if sources.count > 1 { precondition(sources.count == 4, "One tag must retain all four sources") }
                    }
                    if let firstSource {
                        let suffix = (storage.string as NSString).substring(from: firstSource)
                        precondition(suffix.allSatisfy { $0 == "\u{fffc}" || $0.isWhitespace }, "Source icons belong after all information text")
                    }
                }
                node.subviews.forEach(inspect)
            }
            inspect(window.contentView!)
            precondition(badges == (scheme == .dark ? 1 : 4), "All paragraph sources must end in favicon attachments")
            let surface = window.contentView!
            guard let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds) else { fatalError("capture") }
            surface.cacheDisplay(in: surface.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/sources-" + name + ".png"))
            if let text = sourceText, let storage = text.textStorage, let manager = text.layoutManager, let container = text.textContainer {
                var linkRange = NSRange()
                // Target the source attachment, not an earlier heading or ordinary inline link.
                storage.enumerateAttribute(.chatSources, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                    if value != nil { linkRange = range; stop.pointee = true }
                }
                let rect = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: linkRange, actualCharacterRange: nil), in: container)
                let local = NSPoint(x: rect.midX + text.textContainerOrigin.x, y: rect.midY + text.textContainerOrigin.y)
                let point = text.convert(local, to: nil)
                let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
                text.mouseMoved(with: event)
                try await Task.sleep(for: .milliseconds(450))
                precondition(text.preview?.isShown == true, "Hovering a source must open its card")
                let anchor = text.sourceAnchor(at: linkRange.location)!
                let cardFrame = text.preview!.panel.frame
                if scheme == .dark { precondition(cardFrame.minY >= anchor.maxY + 7, "Scrolled low source must open upward") }
                precondition(cardFrame.minY >= anchor.maxY + 7 || cardFrame.maxY <= anchor.minY - 7,
                             "Source card must sit beside its attachment, never at the paragraph bottom")

                if let card = text.preview?.contentView,
                   let bitmap = card.bitmapImageRepForCachingDisplay(in: card.bounds) {
                    card.cacheDisplay(in: card.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/source-card-" + name + ".png"))
                }
                text.preview?.close()
                precondition(text.textView(text, willDisplayToolTip: "https://devin.ai/", forCharacterAt: linkRange.location) == nil,
                             "Source tag must suppress the default raw URL tooltip")
                precondition(text.textView(text, clickedOnLink: URL(string: "https://devin.ai/")!, at: linkRange.location),
                             "Clicking a grouped source tag opens its list rather than navigating to the first URL")
                precondition(text.preview?.isShown == true)
                text.preview?.close()
            }

        }
        let sampleFavicon: Data = {
            let image = NSImage(size: NSSize(width: 28, height: 28), flipped: false) { rect in
                NSColor.systemBlue.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
                NSColor.white.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 7, dy: 7)).fill()
                return true
            }
            let tiff = image.tiffRepresentation!
            return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
        }()
        let kimi = URL(string: "https://platform.kimi.com/")!
        let kr = URL(string: "https://m.36kr.com/p/4024942758268804")!
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let rows = ChatSourcePreview(sources: [kimi], metadata: [kimi: .init(
                title: "Kimi K3.1 Pro - Kimi API 开放平台", siteName: "Kimi API 开放平台", favicon: sampleFavicon)])
                .environment(\.colorScheme, scheme)
            let size = SurfacePanel.fittingSize(of: rows, maxWidth: ChatSourcePreview.width)
            precondition(size.width == 300 && size.height < 76, "Single-source card should remain compact")
            let host = NSHostingView(rootView: rows)
            host.frame = NSRect(origin: .zero, size: size)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = WindowSurface.glassContentView(host, cornerRadius: ChatSourcePreview.cornerRadius)
            window.setContentSize(size)
            try await Task.sleep(for: .milliseconds(200))
            let surface = window.contentView!
            surface.layoutSubtreeIfNeeded()
            let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)!
            surface.cacheDisplay(in: surface.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(
                to: URL(filePath: "build/source-card-kimi-" + name + ".png"))

            // Also capture a two-item card showing favicon+siteName+title+date alongside a fallback globe icon.
            let twoRows = ChatSourcePreview(sources: [kimi, kr], metadata: [
                kimi: .init(title: "Kimi K3.1 Pro - Kimi API 开放平台", siteName: "Kimi API 开放平台", publishedAt: "2026-11-18", favicon: sampleFavicon),
                kr: .init(title: "刚刚，谷歌Gemini 4 Argon上线，API价格限时五折-36氪", siteName: "36氪", publishedAt: "2026-11-19")
            ]).environment(\.colorScheme, scheme)
            let twoSize = SurfacePanel.fittingSize(of: twoRows, maxWidth: ChatSourcePreview.width)
            let twoHost = NSHostingView(rootView: twoRows)
            twoHost.frame = NSRect(origin: .zero, size: twoSize)
            window.contentView = WindowSurface.glassContentView(twoHost, cornerRadius: ChatSourcePreview.cornerRadius)
            window.setContentSize(twoSize)
            try await Task.sleep(for: .milliseconds(200))
            let twoSurface = window.contentView!
            twoSurface.layoutSubtreeIfNeeded()
            let twoBitmap = twoSurface.bitmapImageRepForCachingDisplay(in: twoSurface.bounds)!
            twoSurface.cacheDisplay(in: twoSurface.bounds, to: twoBitmap)
            try twoBitmap.representation(using: .png, properties: [:])!.write(
                to: URL(filePath: "build/source-card-list-" + name + ".png"))
        }
        window.setContentSize(NSSize(width: 640, height: 440))
        let many = (0..<12).map { URL(string: "https://example.com/article/\($0)")! }
        let list = NSHostingView(rootView: ScrollView { ChatSourcePreview(sources: many) }.frame(width: ChatSourcePreview.width, height: 460))
        window.contentView = list
        try await Task.sleep(for: .milliseconds(250))
        list.layoutSubtreeIfNeeded()
        func findScroll(_ node: NSView) -> NSScrollView? {
            if let scroll = node as? NSScrollView { return scroll }
            return node.subviews.compactMap(findScroll).first
        }
        let scroll = findScroll(list)!
        precondition(scroll.documentView!.bounds.height > scroll.contentView.bounds.height, "Long source lists must scroll inside the card")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        precondition(scroll.contentView.bounds.minY > 0, "Source list accepts a real native scroll offset")
        window.orderOut(nil)
        print("Source tags, +N grouping, hover/click lists, long-list scrolling and light/dark positioning passed")
    }

    static func mathPreview() async throws {
        let formulas = [
            #"E = mc^2"#,
            #"\int_{-\infty}^{\infty} e^{-x^2}\,\mathrm{d}x = \sqrt{\pi}"#,
            #"f(x) = \sum_{n=0}^{\infty} \frac{f^{(n)}(a)}{n!}(x-a)^n"#,
            #"\begin{aligned} \nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0} \\ \nabla \times \mathbf{B} &= \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t} \end{aligned}"#,
            #"A = \begin{pmatrix} a & b \\ c & d \end{pmatrix},\quad |x| = \begin{cases} x, & x \ge 0 \\ -x, & x < 0 \end{cases}"#
        ]
        for formula in formulas {
            for color in [NSColor.white, .black] {
                guard let rendered = ChatMathRenderer.render(.init(source: formula, display: true), color: color),
                      let bitmap = rendered.image.representations.first as? NSBitmapImageRep else {
                    preconditionFailure(formula)
                }
                // Glyphs must fit inside the transparent top/bottom padding, including descenders.
                for x in 0..<bitmap.pixelsWide {
                    precondition(bitmap.colorAt(x: x, y: 0)!.alphaComponent < 0.01, formula)
                    precondition(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 1)!.alphaComponent < 0.01, formula)
                }
            }
        }
        precondition(ChatMathRenderer.render(.init(source: #"\unknowncommand{x}"#, display: true), color: .black) == nil)
        for literal in [#"`$x$`"#, "```tex\n$$x$$\n```", #"\$20 and \$30"#, "$20 and $30", #"[price](https://example.com/$x$)"#, "$unfinished", "$$unfinished", "    $$code$$"] {
            precondition(ChatMath.markdown(literal) == literal, literal)
        }
        for input in [#"$x^2$"#, #"$2x$"#, #"$20$"#, #"$$x^2$$"#, #"\(x^2\)"#, #"\[x^2\]"#] {
            precondition(ChatMath.markdown(input).contains("asky-math://"), input)
        }
        let explanatory = "独立公式（使用 $$ 包裹）：\n\n$$x^2$$"
        precondition(ChatMath.markdown(explanatory).hasPrefix("独立公式（使用 $$ 包裹）："))
        precondition(ChatMath.markdown(explanatory).contains("asky-math://display/"))
        let markdown = """
        ## 公式示例
        行内公式：质能方程 $E = mc^2$，圆的面积 $S = \\pi r^2$。

        """ + formulas.dropFirst().map { "$$" + $0 + "$$" }.joined(separator: "\n\n") + """

        **粗体**、`$code$`、价格 $20 and $30 保持原样。
        """
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 760, height: 640),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.title = "Asky Math Regression"
        for (name, scheme, appearance, width) in [("light", ColorScheme.light, NSAppearance.Name.aqua, 760.0),
                                                   ("dark", .dark, .darkAqua, 760.0),
                                                   ("dark-narrow", .dark, .darkAqua, 420.0)] {
            window.setContentSize(NSSize(width: width, height: 640))
            window.appearance = NSAppearance(named: appearance)
            let view = NSHostingView(rootView: ChatMarkdownView(text: markdown).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(scheme == .dark ? Color(white: 0.15) : .white).environment(\.colorScheme, scheme))
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(800))
            view.layoutSubtreeIfNeeded()
            func checkTextWidth(_ node: NSView) {
                if let text = node as? NSTextView, let container = text.textContainer, let manager = text.layoutManager,
                   String(describing: type(of: manager)) == "ChatInlineLayoutManager" {
                    manager.ensureLayout(for: container)
                    precondition(text.bounds.width <= width - 48 + 1, "Paragraph must fit inside the window")
                    precondition(manager.usedRect(for: container).width <= text.bounds.width + 1,
                                 "Inline text must wrap: used=\(manager.usedRect(for: container)) bounds=\(text.bounds) container=\(container.containerSize)")
                }
                node.subviews.forEach(checkTextWidth)
            }
            checkTextWidth(view)
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("capture") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/math-" + name + ".png"))
        }
        window.orderOut(nil)
        print("Math parsing, native layout, invalid-source fallback and light/dark window captures passed")
    }

    static func latexFormPreview(app: AppModel) async throws {
        let source = #"""
        ```asky-form
        {"title":"LaTeX 公式"}
        {"id":"goal","type":"radio","label":"你想要什么","options":["查看常用公式示例","输入具体数学式子"],"required":true,"allowCustom":true}
        {"id":"detail","type":"text","label":"具体式子（可选）"}
        {"id":"display","type":"radio","label":"输出形式","options":["行内 $...$","独立公式块 $$...$$ 或 \[...\]","两者都给"],"allowCustom":true}
        ```
        """#
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "LaTeX 表单回归")
        try store.append(conversationID: cid, role: "user", text: "看看公式")
        try store.append(conversationID: cid, role: "assistant", text: source)
        let model = AgentModel(app: app)
        model.open(cid)
        let item = model.items.last!
        precondition(item.text == source, "History must retain the original model output")
        let form = ChatFormParser.form(in: item.text)!
        precondition(form.isComplete && form.fields.count == 3 && model.formIsActive(item.id))
        model.formValues[item.id] = ["goal": ["查看常用公式示例"], "display": ["两者都给"]]
        precondition(form.accepts(model.formValues[item.id]!))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 540, height: 680),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Asky LaTeX Form Regression"
        defer { window.orderOut(nil) }
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let view = NSHostingView(rootView: ChatReplyView(text: item.text,
                values: Binding(get: { model.formValues[item.id] ?? [:] }, set: { model.formValues[item.id] = $0 }),
                active: model.formIsActive(item.id)).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(scheme == .dark ? Color(white: 0.15) : .white).environment(\.colorScheme, scheme))
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(500))
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/latex-form-" + name + ".png"))
        }
        print("LaTeX form passed: invalid escape recovery, unchanged history, active form, valid answers and light/dark captures")
    }

    static func formPrefillRegression(app: AppModel) async throws {
        let source = """
        ```asky-form
        {"title":"会议安排"}
        {"id":"title","type":"text","label":"会议名称","required":true,"defaultValue":"项目周会"}
        {"id":"format","type":"radio","label":"会议形式","options":["线上","线下"],"defaultValue":"线上"}
        {"id":"length","type":"select","label":"会议时长","options":["30 分钟","60 分钟"],"defaultValue":"30 分钟"}
        {"id":"topics","type":"multi","label":"议题","options":["设计","开发"],"defaultValue":["设计"]}
        {"id":"day","type":"date","label":"会议日期","required":true,"defaultValue":"2026-11-15"}
        {"id":"time","type":"time","label":"开始时间","required":true,"defaultValue":"15:00"}
        {"id":"duration","type":"duration","label":"讨论时长","components":["minute"],"defaultValue":"30"}
        {"id":"place","type":"radio","label":"地点","options":["会议室"],"allowCustom":true,"defaultValue":"视频通话"}
        ```
        """
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "表单预填回归")
        let message = try store.append(conversationID: cid, role: "assistant", text: source)
        let model = AgentModel(app: app)
        model.open(cid)
        let defaults = model.formAnswers(message.id)
        precondition(defaults.count == 8 && defaults["time"] == ["15:00"] && defaults["place"] == ["视频通话"])
        precondition(model.formValues[message.id] == nil, "Defaults must be usable without touching a control")
        precondition(store.message(message.id, conversationID: cid)?.presentation?.submittedFormValues == nil,
                     "Prefilling must never count as submission")
        let form = ChatFormParser.form(in: source)!
        model.setFormAnswers(["title": [""], "topics": []], for: message.id)
        precondition(model.formAnswers(message.id)["title"] == [""] && model.formAnswers(message.id)["topics"] == [])
        precondition(!form.accepts(model.formAnswers(message.id)) && !model.submitForm(message.id))
        model.setFormAnswers(["title": ["设计评审"], "topics": []], for: message.id)
        precondition(model.formAnswers(message.id)["title"] == ["设计评审"])
        model.open(cid)
        precondition(model.formAnswers(message.id) == defaults, "Reopening an unsubmitted form restores its schema defaults")

        let window = NSWindow(contentRect: NSRect(x: 100, y: 60, width: 540, height: 1000),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Asky Prefilled Form Regression"
        defer { window.orderOut(nil) }
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let view = NSHostingView(rootView: ChatReplyView(text: source,
                values: Binding(get: { model.formAnswers(message.id) }, set: { model.setFormAnswers($0, for: message.id) }),
                active: model.formIsActive(message.id)).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(scheme == .dark ? Color(white: 0.15) : .white).environment(\.colorScheme, scheme))
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(350))
            view.layoutSubtreeIfNeeded()
            precondition(model.formAnswers(message.id) == defaults, "Date/time controls must retain model defaults")
            func descendants(_ node: NSView) -> [NSView] { [node] + node.subviews.flatMap(descendants) }
            let inputs = descendants(view).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
            precondition(inputs.contains { $0.stringValue == "项目周会" }, "Text default must reach the actual input")
            precondition(inputs.contains { $0.stringValue == "视频通话" }, "Custom default must open its editable input")
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/form-prefill-" + name + ".png"))
        }
        app.preferences.automaticUpdates = false
        await app.start()
        precondition(app.agent != nil)
        app.modelConfiguration = ModelConfiguration(baseURL: URL(string: "http://127.0.0.1:1/v1")!,
            modelName: "prefill-regression", credentialRef: "Asky-prefill-unset-" + UUID().uuidString)
        precondition(model.submitForm(message.id), "Untouched valid defaults must submit through the normal path")
        precondition(model.items.last!.text == form.reply(defaults))
        precondition(!model.submitForm(message.id), "Defaults must not enable duplicate submission")
        for _ in 0..<100 where model.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        precondition(!model.isRunning && model.state == .failed, "The intentionally missing credential prevents a real model call")
        let reopened = AgentModel(app: app)
        reopened.open(cid)
        precondition(reopened.formAnswers(message.id) == defaults && !reopened.formIsActive(message.id))
        reopened.setFormAnswers(["title": ["覆盖"]], for: message.id)
        precondition(reopened.formAnswers(message.id) == defaults, "Submitted defaults must remain immutable")
        // A legacy submitted form with an omitted answer must not acquire a new schema default.
        let legacy = try store.append(conversationID: cid, role: "assistant", text: source,
            presentation: MessagePresentation(submittedFormValues: ["title": ["旧答案"]]))
        reopened.open(cid)
        precondition(reopened.formAnswers(legacy.id) == ["title": ["旧答案"]])
        print("Form prefill passed: native light/dark controls, untouched submission, edits/clearing, reopen, immutable snapshots and no automatic action")
    }

    static func formLifecycleRegression(app: AppModel) async throws {
        let store = ConversationStore(app.store)
        let model = AgentModel(app: app)
        let cid = try store.create(title: "表单生命周期")
        try store.append(conversationID: cid, role: "user", text: "帮我写公式")
        model.open(cid)
        model.beginResponse(taskID: "form-lifecycle")
        let schema = "```asky-form\n{\"title\":\"公式需求\"}\n{\"id\":\"goal\",\"type\":\"text\",\"label\":\"这个公式要算什么\",\"required\":true}\n```"
        model.handle(.message(taskID: "form-lifecycle", schema), conversationID: cid)
        model.finishTask(conversationID: cid)
        let messageID = model.items.last!.id
        model.formValues[messageID] = ["goal": ["求和"]]
        // finishTask schedules this real cleanup even when retention deletes nothing.
        await app.maintainConversationHistory()
        precondition(model.formIsActive(messageID), "cleanup must not expire a just-completed form")
        precondition(model.formValues[messageID]?["goal"] == ["求和"], "cleanup must retain unsubmitted answers")
        model.resumeTimeline()
        precondition(model.conversationID == nil && model.formIsActive(messageID), "timeline must resolve the form's original storage segment")
        model.formValues[messageID] = ["goal": ["求平均值"]]
        let unrelated = try store.create(title: "待删除的其他记录")
        try store.append(conversationID: unrelated, role: "user", text: "其他记录", now: Date.distantPast)
        let deletedUnrelated = await app.deleteConversationHistory(unrelated)
        precondition(deletedUnrelated)
        precondition(model.formIsActive(messageID) && model.formValues[messageID]?["goal"] == ["求平均值"], "unrelated deletion must preserve the active form and answers")
        let later = try store.create(title: "后续问题")
        try store.append(conversationID: later, role: "user", text: "改用文字回答")
        model.resumeTimeline()
        precondition(model.formIsActive(messageID), "later messages must not expire an unsubmitted form")
        try store.append(conversationID: later, role: "assistant", text: "后续回答")
        model.resumeTimeline()
        precondition(model.formIsActive(messageID), "later assistant replies must not expire an unsubmitted form")
        model.open(cid)
        precondition(model.formIsActive(messageID), "reopening the source history must keep an unsubmitted form available")
        let deletedForm = await app.deleteConversationHistory(cid)
        precondition(deletedForm)
        precondition(!model.formIsActive(messageID) && !model.submitForm(messageID), "deleted forms must never submit")
        print("Form lifecycle passed: completion cleanup, draft preservation, timeline reopen, unrelated deletion, later input and deleted form rejection")
    }

    static func formPreview(app: AppModel, model: AgentModel) async throws {
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "会议安排")
        try store.append(conversationID: cid, role: "user", text: "帮我安排会议，先让我选择时间和议题。")
        model.open(cid)
        let prefix = "请补充会议信息：\n\n```asky-form\n{\"title\":\"会议安排\"}\n{\"id\":\"title\",\"type\":\"text\",\"label\":\"会议名称\",\"required\":true}\n"
        var rest = """
        {"id":"duration","type":"select","label":"会议时长","options":["30 分钟","60 分钟"],"required":true}
        {"id":"topics","type":"multi","label":"讨论议题","options":["设计方案","开发计划"]}
        {"id":"day","type":"date","label":"会议日期","required":true}
        ```
        """
        let testingCustom = CommandLine.arguments.contains("--custom-preview")
        let testingRadio = CommandLine.arguments.contains("--radio-preview") || testingCustom
        let testingComponents = CommandLine.arguments.contains("--components-preview")
        let testingTime = CommandLine.arguments.contains("--time-preview") || testingComponents
        if testingTime {
            rest = rest.replacingOccurrences(of: "\n```", with: "\n{\"id\":\"time\",\"type\":\"time\",\"label\":\"具体时间\",\"required\":true}\n```")
        }
        if testingComponents {
            rest = """
            {"id":"duration","type":"select","label":"会议时长","options":["30 分钟","60 分钟"],"required":true}
            {"id":"time","type":"time","label":"时分秒","components":["hour","minute","second"],"required":true}
            {"id":"countdown","type":"duration","label":"仅分秒","components":["minute","second"],"required":true}
            {"id":"seconds","type":"duration","label":"仅秒钟","components":["second"],"required":true}
            ```
            """
        }
        if testingRadio {
            rest = """
            {"id":"duration","type":"select","label":"会议时长（下拉单选）","options":["30 分钟","60 分钟"],"required":true}
            {"id":"plan","type":"radio","label":"选择方案（单选）","options":["方案 A","方案 B","方案 C"],"required":true}
            {"id":"when","type":"radio","label":"执行时间（独立单选组）","options":["现在","稍后"],"required":true}
            {"id":"topics","type":"multi","label":"讨论议题（多选）","options":["设计方案","开发计划"]}
            ```
            """
        }
        if testingCustom {
            rest = rest.replacingOccurrences(of: "\"type\":\"radio\"", with: "\"allowCustom\":true,\"type\":\"radio\"")
            rest = rest.replacingOccurrences(of: "\"type\":\"select\"", with: "\"allowCustom\":true,\"type\":\"select\"")
        }
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        // show() restores the global timeline; bind the simulated reply to its real segment.
        model.open(cid)
        let window = NSApplication.shared.windows.first { $0.title == "Asky AI" }!
        window.setContentSize(NSSize(width: 760, height: 800))
        defer { window.orderOut(nil) }
        func capture(_ name: String) throws {
            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/form-" + name + ".png"))
        }
        model.beginResponse(taskID: "form-stream")
        model.handle(.textDelta(taskID: "form-stream", prefix), conversationID: cid)
        try await Task.sleep(for: .milliseconds(150))
        precondition(!model.items.contains { $0.kind == .assistant }, "Forms must stay hidden while the reply is being prepared")
        try capture("pending")
        model.handle(.message(taskID: "form-stream", prefix + rest), conversationID: cid)
        precondition(!model.items.contains { $0.kind == .assistant }, "Even a complete message must wait for task completion")
        model.handle(.taskState(taskID: "form-stream", .completed), conversationID: cid)
        model.finishTask(conversationID: cid)
        let messageID = model.items.last!.id
        try await Task.sleep(for: .milliseconds(250))
        precondition(model.formIsActive(messageID), "completed form must remain active after scheduled cleanup")
        func editableField(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.compactMap { editableField($0) }.first
        }
        let answerField = editableField(window.contentView!)
        if let field = answerField, window.makeFirstResponder(field), let editor = field.currentEditor() {
            editor.insertText("原生输入回归")
            try await Task.sleep(for: .milliseconds(100))
            precondition(model.formValues[messageID]?["title"] == ["原生输入回归"])
        } else { preconditionFailure("The complete reply must expose an editable native form") }
        try capture("complete")
        func popup(_ view: NSView) -> NSPopUpButton? {
            if let button = view as? NSPopUpButton, button.numberOfItems == (testingCustom ? 4 : 3) { return button }
            return view.subviews.compactMap { popup($0) }.first
        }
        let picker = popup(window.contentView!)!
        picker.selectItem(at: 1)
        NSApplication.shared.sendAction(picker.action!, to: picker.target, from: picker)
        precondition(model.formValues[messageID]?["duration"] == ["30 分钟"], "native popup selection must update the answer")
        if testingCustom {
            picker.selectItem(at: 3)
            NSApplication.shared.sendAction(picker.action!, to: picker.target, from: picker)
            try await Task.sleep(for: .milliseconds(100))
            func customInput(_ view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable,
                   field.placeholderString == NSLocalizedString("输入你的回答", comment: "") { return field }
                return view.subviews.compactMap { customInput($0) }.first
            }
            let input = customInput(window.contentView!)!
            precondition(window.makeFirstResponder(input))
            input.currentEditor()!.insertText("45 分钟")
            try await Task.sleep(for: .milliseconds(100))
            precondition(model.formValues[messageID]?["duration"] == ["45 分钟"])
            picker.selectItem(at: 1)
            NSApplication.shared.sendAction(picker.action!, to: picker.target, from: picker)
            try await Task.sleep(for: .milliseconds(100))
            precondition(model.formValues[messageID]?["duration"] == ["30 分钟"])
        }
        model.formValues[messageID]?["topics"] = ["设计方案"]
        model.formValues[messageID]?["day"] = ["2026-10-22"]
        if testingRadio {
            func radio(_ title: String, in view: NSView) -> NSButton? {
                if let button = view as? NSButton, button.title == title { return button }
                return view.subviews.compactMap { radio(title, in: $0) }.first
            }
            let a = radio("方案 A", in: window.contentView!)!
            let b = radio("方案 B", in: window.contentView!)!
            let c = radio("方案 C", in: window.contentView!)!
            let later = radio("稍后", in: window.contentView!)!
            precondition(a.accessibilityRole() == .radioButton, "single choice must expose native radio semantics")
            precondition([a, b, c, later].allSatisfy { $0.state == .off }, "radio must not silently preselect an answer")
            // Dispatch native actions without performClick's nested event loop in async main.
            func choose(_ button: NSButton) {
                button.state = .on
                NSApplication.shared.sendAction(button.action!, to: button.target, from: button)
            }
            choose(a)
            try await Task.sleep(for: .milliseconds(50))
            precondition(model.formValues[messageID]?["plan"] == ["方案 A"])
            choose(c)
            try await Task.sleep(for: .milliseconds(50))
            precondition(model.formValues[messageID]?["plan"] == ["方案 C"])
            precondition(a.state == .off && b.state == .off && c.state == .on, "a radio group must keep only one selection")
            choose(later)
            try await Task.sleep(for: .milliseconds(50))
            precondition(c.state == .on && later.state == .on, "separate groups must not clear each other")
            if testingCustom {
                // Each group owns a separate custom field and remembers its draft across switches.
                let custom = radio(NSLocalizedString("自己填写", comment: ""), in: window.contentView!)!
                choose(custom)
                try await Task.sleep(for: .milliseconds(100))
                precondition(!ChatFormParser.form(in: prefix + rest)!.accepts(model.formValues[messageID]!))
                func customField(_ view: NSView) -> NSTextField? {
                    if let field = view as? NSTextField, field.isEditable,
                       field.placeholderString == NSLocalizedString("输入你的回答", comment: "") { return field }
                    return view.subviews.compactMap { customField($0) }.first
                }
                let field = customField(window.contentView!)!
                precondition(window.makeFirstResponder(field))
                field.currentEditor()!.insertText("先给我看改动，再决定")
                try await Task.sleep(for: .milliseconds(100))
                precondition(model.formValues[messageID]?["plan"] == ["先给我看改动，再决定"])
                choose(a)
                try await Task.sleep(for: .milliseconds(100))
                precondition(model.formValues[messageID]?["plan"] == ["方案 A"])
                choose(custom)
                try await Task.sleep(for: .milliseconds(100))
                precondition(model.formValues[messageID]?["plan"] == ["先给我看改动，再决定"])
                precondition(model.formValues[messageID]?["when"] == ["稍后"])
            }
        }
        if testingTime {
            func choices(_ view: NSView) -> [NSPopUpButton] {
                (view as? NSPopUpButton).map { [$0] } ?? view.subviews.flatMap(choices)
            }
            let pickers = choices(window.contentView!)
            let hour = pickers.first { $0.numberOfItems == 24 }!
            func rect(_ picker: NSPopUpButton) -> NSRect { window.contentView!.convert(picker.bounds, from: picker) }
            func row(_ picker: NSPopUpButton) -> [NSPopUpButton] {
                pickers.filter { abs(rect($0).midY - rect(picker).midY) < 2 }.sorted { rect($0).minX < rect($1).minX }
            }
            func choose(_ picker: NSPopUpButton, _ value: Int) async throws {
                picker.selectItem(at: value)
                NSApplication.shared.sendAction(picker.action!, to: picker.target, from: picker)
                try await Task.sleep(for: .milliseconds(50))
            }
            let clock = row(hour)
            try await choose(clock[0], 14)
            try await choose(clock[1], 30)
            if testingComponents {
                try await choose(clock[2], 45)
                let leading = pickers.filter { $0.numberOfItems == 100 }.sorted {
                    window.contentView!.isFlipped ? rect($0).minY < rect($1).minY : rect($0).maxY > rect($1).maxY
                }
                try await choose(leading[0], 3)
                try await choose(row(leading[0])[1], 30)
                try await choose(leading[1], 30)
                precondition(model.formValues[messageID]?["countdown"] == ["03:30"])
                precondition(model.formValues[messageID]?["seconds"] == ["30"])
            }
            precondition(model.formValues[messageID]?["time"] == [testingComponents ? "14:30:45" : "14:30"], "only requested time components must be submitted")
        }
        precondition(editableField(window.contentView!) === answerField, "Editing must retain the same native field")
        precondition(model.formIsActive(messageID))
        precondition(ChatFormParser.form(in: model.items.last!.text)!.accepts(model.formValues[messageID]!))
        for (name, appearance, width) in [("light", NSAppearance.Name.aqua, 760.0),
                                           ("dark", .darkAqua, 760.0), ("narrow", .darkAqua, 560.0)] {
            window.appearance = NSAppearance(named: appearance)
            window.setContentSize(NSSize(width: width, height: 800))
            try await Task.sleep(for: .milliseconds(400))
            NSApplication.shared.activate()
            window.makeKeyAndOrderFront(nil)
            if let field = editableField(window.contentView!) { window.makeFirstResponder(field) }
            try await Task.sleep(for: .milliseconds(150))
            try capture(name)
            if CommandLine.arguments.contains("--forms-inspect") {
                let capture = Process()
                capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), "build/form-glass-" + name + ".png"]
                try capture.run(); capture.waitUntilExit()
                precondition(capture.terminationStatus == 0)
            }
            try capture("field-" + name + "-focused")
            window.makeFirstResponder(nil)
            try await Task.sleep(for: .milliseconds(100))
            try capture("field-" + name + "-idle")
        }
        if CommandLine.arguments.contains("--forms-inspect") {
            // Reproduce a bright desktop showing through dark glass instead of validating only black wallpaper.
            let underlay = NSWindow(contentRect: window.frame, styleMask: .borderless, backing: .buffered, defer: false)
            underlay.isReleasedWhenClosed = false
            underlay.backgroundColor = NSColor(white: 0.78, alpha: 1)
            underlay.isOpaque = true
            underlay.order(.below, relativeTo: window.windowNumber)
            defer { underlay.orderOut(nil) }
            window.makeFirstResponder(nil)
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(400))
            let brightCapture = Process()
            brightCapture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            brightCapture.arguments = ["-x", "-o", "-l", String(window.windowNumber), "build/form-glass-bright.png"]
            try brightCapture.run(); brightCapture.waitUntilExit()
            precondition(brightCapture.terminationStatus == 0)
            // Click the date row in the fixed 560x800 fixture using native window events.
            func click(_ point: NSPoint) {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                    NSApplication.shared.sendEvent(event)
                }
            }
            click(NSPoint(x: 200, y: 278))
            try await Task.sleep(for: .milliseconds(300))
            let calendarWindow = NSApplication.shared.windows.first { $0 !== window && $0.isVisible && String(describing: type(of: $0)).contains("Popover") }!
            let screenshot = Process()
            screenshot.executableURL = URL(filePath: "/usr/sbin/screencapture")
            screenshot.arguments = ["-x", "-o", "-l", String(calendarWindow.windowNumber), "build/form-calendar-popover.png"]
            try screenshot.run(); screenshot.waitUntilExit()
            precondition(screenshot.terminationStatus == 0)
            click(NSPoint(x: 20, y: 20))
            window.makeKeyAndOrderFront(nil)
        }
        // Exercise the actual submit path with an intentionally absent test credential. No model
        // request can leave the machine; the normal user-message append happens before that failure.
        let submittedValues = model.formValues[messageID]!
        let reply = ChatFormParser.form(in: prefix + rest)!.reply(submittedValues)
        app.preferences.automaticUpdates = false
        await app.start()
        precondition(app.agent != nil, "test bundle must locate the actual runtime")
        app.modelConfiguration = ModelConfiguration(baseURL: URL(string: "http://127.0.0.1:1/v1")!,
            modelName: "form-regression", credentialRef: "Asky-form-unset-" + UUID().uuidString)
        model.draft = "保留输入框草稿"
        let attachment = AttachmentRef(id: "draft-only", kind: .file, path: "/draft-only", mimeType: "text/plain", byteSize: 0, temporary: false)
        model.attachments = [attachment]
        precondition(model.submitForm(messageID), "valid form must enter the normal submit path")
        let submittedCID = model.conversationID!
        precondition(submittedCID != cid && model.items.last!.text == reply, "timeline replies use a fresh storage segment")
        precondition(model.items.last!.attachments.isEmpty, "form submission must not send composer attachments")
        precondition(model.draft == "保留输入框草稿" && model.attachments == [attachment])
        precondition(!model.submitForm(messageID), "double submission must be rejected")
        precondition(model.formAnswers(messageID) == submittedValues, "submission must retain the exact selected answers")
        model.setFormAnswers(["title": ["不能覆盖"]], for: messageID)
        precondition(model.formAnswers(messageID) == submittedValues, "submitted answers must be immutable")
        for _ in 0..<100 where model.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        precondition(!model.isRunning)
        model.resumeTimeline()
        precondition(!model.formIsActive(messageID) && !model.submitForm(messageID))
        precondition(model.formAnswers(messageID) == submittedValues, "timeline restore must retain submitted answers")
        try await Task.sleep(for: .milliseconds(150))
        try capture("field-dark-disabled")
        // The intentionally missing credential appends an error after the submitted reply.
        precondition(model.state == .failed, "The test credential must fail without a real model call")
        precondition(model.items.filter { $0.kind == .user && $0.text == reply }.count == 1,
                     "The form reply must survive history exactly once, including when the request fails")
        precondition(ChatFormParser.form(in: model.items.first { $0.id == messageID }!.text)?.fields.count == (testingTime || testingRadio ? 5 : 4))
        let restored = AgentModel(app: app)
        restored.open(cid)
        precondition(!restored.formIsActive(messageID) && !restored.submitForm(messageID), "source-only history must never unlock a submitted form")
        precondition(restored.formAnswers(messageID) == submittedValues)
        try store.delete(submittedCID)
        restored.resumeTimeline()
        precondition(!restored.formIsActive(messageID) && restored.formAnswers(messageID) == submittedValues,
                     "deleting the later reply must not unlock or erase the original submitted form")
        let readonly = NSHostingView(rootView: ChatReplyView(text: prefix + rest,
            values: Binding(get: { restored.formAnswers(messageID) }, set: { restored.setFormAnswers($0, for: messageID) }),
            active: restored.formIsActive(messageID), submit: { restored.submitForm(messageID) }).padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
        let readonlyWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 760),
                                      styleMask: [.titled], backing: .buffered, defer: false)
        readonlyWindow.contentView = readonly
        readonlyWindow.appearance = NSAppearance(named: .aqua)
        readonlyWindow.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(200))
        readonly.layoutSubtreeIfNeeded()
        var submitButtons = 0
        var displayedAnswers: [String] = []
        func checkReadOnly(_ view: NSView) {
            if let button = view as? NSButton {
                precondition(!button.isEnabled, "submitted form buttons and choices must be disabled")
                if button.title == NSLocalizedString("提交回复", comment: "") { submitButtons += 1 }
            }
            if let field = view as? NSTextField {
                precondition(!field.isEditable || !field.isEnabled)
                displayedAnswers.append(field.stringValue)
            }
            view.subviews.forEach(checkReadOnly)
        }
        checkReadOnly(readonly)
        precondition(submitButtons == 1, "keep the disabled submit button visible")
        precondition(displayedAnswers.contains(submittedValues["title"]!.first!), "read-only text field must display its original answer")
        let readonlyCapture = Process()
        readonlyCapture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        readonlyCapture.arguments = ["-x", "-o", "-l", String(readonlyWindow.windowNumber), "build/form-submitted-readonly.png"]
        try readonlyCapture.run(); readonlyCapture.waitUntilExit()
        precondition(readonlyCapture.terminationStatus == 0)
        readonlyWindow.orderOut(nil)
        // New session and opening history are native-only; no model calls are needed for rendering.
        await model.startNewConversation()
        precondition(model.formValues.isEmpty)
        await app.shutdown()
        print("Native form UI: hidden until completion, native typing, light/dark/narrow captures, history, replay prevention and cleanup passed")
    }

    static func historyRegression(app: AppModel) throws {
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "工具历史回归")
        let model = AgentModel(app: app)
        model.open(cid)
        let startedAt = Date()
        model.beginResponse(taskID: "history-turn", now: startedAt)
        model.handle(.message(taskID: "history-turn", "先检查日历"), conversationID: cid)
        for index in 0..<45 {
            let request = ActionRequest(requestID: "history-call-\(index)", tool: "calendar_search", arguments: .object([:]),
                taskID: "history-turn", origin: .agent(sessionID: cid), intent: .explicitRequest)
            model.handle(.toolCall(taskID: "history-turn", request), conversationID: cid)
            if index < 44 {
                model.handle(.toolResult(taskID: "history-turn", .failure(request.requestID, .permissionDenied, "请授权日历")), conversationID: cid)
            }
        }
        model.handle(.error(taskID: "history-turn", "执行已中断"), conversationID: cid)
        model.handle(.taskState(taskID: "history-turn", .pendingVerification), conversationID: cid)
        model.handle(.message(taskID: "history-turn", "请检查授权"), conversationID: cid)
        model.finishTask(conversationID: cid, now: startedAt.addingTimeInterval(13))
        let expected = model.items
        let reopened = AgentModel(app: app)
        reopened.open(cid)
        precondition(reopened.items.count == AgentModel.firstPage)
        reopened.loadOlder()
        precondition(reopened.items == expected, "Tool state, errors, ordering, response groups and elapsed time must survive paging/reopening")
        precondition(reopened.items.filter { if case .tool = $0.kind { true } else { false } }.count == 45)
        precondition(reopened.items.contains { $0.kind == .tool(.pendingVerification) })
        precondition(reopened.items.contains { $0.kind == .tool(.failed) && $0.needsPermissionSettings && $0.toolError == "请授权日历" })
        precondition(reopened.items.last(where: { $0.kind == .assistant })?.workSeconds == 13)
        precondition(!reopened.isRunning)
        let longID = try store.create(title: "长工具历史")
        reopened.open(longID)
        reopened.beginResponse(taskID: "long-turn")
        for index in 0..<125 {
            let request = ActionRequest(requestID: "long-call-\(index)", tool: "calendar_search", arguments: .object([:]),
                taskID: "long-turn", origin: .agent(sessionID: longID), intent: .explicitRequest)
            reopened.handle(.toolCall(taskID: "long-turn", request), conversationID: longID)
        }
        reopened.handle(.toolResult(taskID: "long-turn", .failure("long-call-0", .permissionDenied, "迟到的结果")), conversationID: longID)
        reopened.finishTask(conversationID: longID)
        precondition(store.message("long-call-0", conversationID: longID)?.presentation?.toolStatus == .failed)
        precondition(store.messages(conversationID: longID, limit: 200).count == 125, "Evicted tool results must update their original record")
        reopened.loadOlder()
        precondition(reopened.items.first?.id == "long-call-0", "History must remain pageable after the live window is trimmed")
        print("Historical transcript regression passed: tools, failure/permission state, interrupted tool, notices, errors, grouping, timing and pagination")
    }

    static func toolRepliesRegression(app: AppModel, capture: Bool = false) async throws {
        let model = AgentModel(app: app)
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "打开 Claude Code")
        try store.append(conversationID: cid, role: "user", text: "帮我在 Orca 的 Asky 项目中打开 Claude Code")
        model.open(cid)
        model.beginResponse(taskID: "complete-reply", now: Date().addingTimeInterval(-8))
        model.handle(.taskState(taskID: "complete-reply", .running), conversationID: cid)
        let controller = capture ? AgentWindowController(model: model, presentation: WindowPresentation()) : nil
        if let controller { controller.show() }
        func group() -> ChatResponseGroup {
            ChatResponseGroup(id: "complete-reply", items: model.items.filter { $0.responseID == "complete-reply" }, isRunning: model.isRunning, state: model.state, streaming: model.streaming)
        }
        func snapshot(_ name: String, delay: Duration = .milliseconds(300)) async throws {
            guard capture else { return }
            try await Task.sleep(for: delay)
            let view = NSApplication.shared.windows.first { $0.title == "Asky AI" }!.contentView!
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/reply-activity-\(name).png"))
        }
        precondition(group().activityLabel == NSLocalizedString("思考中…", comment: ""))
        try await snapshot("thinking")
        try await snapshot("thinking-pulse", delay: .milliseconds(150))
        for (index, text) in ["先查看项目。", "已找到项目，继续查看工作区。"].enumerated() {
            let midpoint = text.count / 2
            model.handle(.textDelta(taskID: "complete-reply", String(text.prefix(midpoint))), conversationID: cid)
            model.handle(.textDelta(taskID: "complete-reply", String(text.dropFirst(midpoint))), conversationID: cid)
            if index == 1 { model.handle(.message(taskID: "complete-reply", text), conversationID: cid) }
            precondition(model.streaming == text)
            precondition(!model.items.contains { $0.kind == .assistant }, "Progress narration must not be persisted as a final answer")
            if index == 0 { try await snapshot("before-tool") }
            let request = ActionRequest(requestID: "activity-tool-\(index)", tool: index == 0 ? "plugin_orca__cli_query" : "web_search", arguments: [:], origin: .agent(sessionID: cid), intent: .explicitRequest)
            model.handle(.toolCall(taskID: "complete-reply", request), conversationID: cid)
            precondition(group().tools.last?.kind == .tool(nil))
            precondition(group().showsThinkingIndicator && group().content.isEmpty, "Tool execution must retain only the typing bubble")
            precondition(model.streaming.isEmpty, "The next model completion must start with an empty stream")
            precondition(model.items.last(where: { $0.kind == .toolNarration })?.text == text,
                         "Pre-tool text remains stored without becoming visible dialogue")
            precondition(group().steps.filter { $0.kind == .toolNarration }.count == index + 1)
            precondition(!group().content.contains { $0.text == text }, "Progress belongs to the tool timeline, not the final answer")
            if index == 0 { try await snapshot("tool") }
            if index == 1 { try await snapshot("tool-states") }
            let result = index == 0 ? ExecutionResult(requestID: request.requestID, status: .completed)
                : ExecutionResult.failure(request.requestID, .unavailable, "搜索暂不可用")
            model.handle(.toolResult(taskID: "complete-reply", result), conversationID: cid)
            if index == 1 { try await snapshot("tool-failed") }
            precondition(group().activityLabel == NSLocalizedString("思考中…", comment: ""))
        }
        model.handle(.taskState(taskID: "complete-reply", .compacting), conversationID: cid)
        precondition(group().activityLabel == NSLocalizedString("正在压缩上下文…", comment: ""))
        model.handle(.taskState(taskID: "complete-reply", .running), conversationID: cid)
        let final = "### 已启动 Claude Code\n\n- 项目：**Asky**\n- 打开方式：CLI 终端窗口\n- 终端句柄：`term_5`"
        let prefix = "### 已启动 Claude Code\n\n- 项目：**Asky**\n"
        model.handle(.textDelta(taskID: "complete-reply", prefix), conversationID: cid)
        precondition(model.streaming == prefix && model.isRunning, "Partial final text must be available before the response finishes")
        try await snapshot("streaming-start")
        model.handle(.textDelta(taskID: "complete-reply", String(final.dropFirst(prefix.count))), conversationID: cid)
        model.handle(.message(taskID: "complete-reply", final), conversationID: cid)
        precondition(!model.items.contains { $0.kind == .assistant })
        precondition(model.streaming == final, "The complete answer remains buffered until completion")
        precondition(group().showsThinkingIndicator && group().content.isEmpty, "Partial text must stay hidden behind the typing bubble")
        try await snapshot("streaming-result")
        model.handle(.taskState(taskID: "complete-reply", .completed), conversationID: cid)
        model.finishTask(conversationID: cid)
        precondition(!model.isRunning)
        precondition(model.items.filter { $0.kind == .assistant }.count == 1)
        precondition(model.items.last?.text == final)
        precondition(!group().showsThinkingIndicator && group().content.map(\.text) == [final])
        try await snapshot("transition", delay: .milliseconds(70))
        try await snapshot("completed")
        model.open(cid)
        precondition(model.items.filter { $0.kind == .assistant }.count == 1, "Only the final answer is an assistant reply")
        precondition(model.items.filter { $0.kind == .toolNarration }.map(\.text) == ["先查看项目。", "已找到项目，继续查看工作区。"],
                     "Tool narration must survive reopening without becoming final-answer text")
        let dialogue = store.messages(conversationID: cid, limit: 30, dialogueOnly: true)
        precondition(!dialogue.contains { $0.role == "tool_narration" }, "Progress notes must not enter dialogue-only memory extraction")
        if capture { NSApplication.shared.windows.first { $0.title == "Asky AI" }?.close() }
        print("Bubble reply regression passed: hidden tools and partial text, typing placeholder, complete answer and history")
    }

    static func pagingRegression(app: AppModel) throws {
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Bidirectional pages")
        for index in 0..<205 {
            try store.append(conversationID: cid, role: index.isMultiple(of: 2) ? "user" : "assistant", text: "Page message \(index)")
        }
        for timeline in [false, true] {
            let model = AgentModel(app: app)
            if timeline { model.resumeTimeline() } else { model.open(cid) }
            let expected = timeline ? store.timeline(limit: 1000) : store.messages(conversationID: cid, limit: 1000)
            let latest = model.items.map(\.id)
            while model.hasOlder {
                model.loadOlder()
                precondition(model.items.count <= AgentModel.window)
            }
            precondition(model.items.first?.id == expected.first?.id)
            precondition(model.hasNewer, "Evicting newer messages must leave a path back to them")
            var visited = Set(model.items.map(\.id))
            while model.hasNewer {
                model.loadNewer()
                visited.formUnion(model.items.map(\.id))
                precondition(model.items.count <= AgentModel.window)
                precondition(Set(model.items.map(\.id)).count == model.items.count)
            }
            precondition(visited == Set(expected.map(\.id)), "Paging back down must recover every record without gaps")
            precondition(Array(model.items.suffix(latest.count)).map(\.id) == latest)
            model.loadOlder()
            precondition(model.hasNewer)
            model.loadLatestMessages()
            precondition(model.items.map(\.id) == latest && !model.hasNewer)
            model.beginResponse(taskID: "paging-active")
            let activeIDs = model.items.map(\.id)
            model.loadOlder()
            precondition(model.items.map(\.id) == activeIDs, "History paging must not evict an active response")
            model.finishTask(conversationID: cid)
        }
        // Live trimming must advance the older-page cursor to the actual window edge.
        let model = AgentModel(app: app)
        model.open(cid)
        model.beginResponse(taskID: "trim-cursor")
        for index in 0..<130 {
            model.handle(.error(taskID: "trim-cursor", "Error \(index)"), conversationID: cid)
        }
        model.finishTask(conversationID: cid)
        let edge = model.items.first!.id
        model.loadOlder()
        precondition(model.items.contains { $0.id == edge })
        precondition(Set(model.items.map(\.id)).count == model.items.count)
        print("Paging passed: both directions, latest jump, 120-record bound, active response and live-trim cursor")
    }

    static func replyNavigationRegression(app: AppModel) async throws {
        let store = ConversationStore(app.store)
        let sourceCID = try store.create(title: "Reply navigation sources")
        let short = try store.append(conversationID: sourceCID, role: "assistant", text: "这是要定位的简短原回复")
        let long = try store.append(conversationID: sourceCID, role: "assistant", text:
            (0..<45).map { "原回复段落 \($0)：长回复必须从开头阅读，滚动后不能被重新拉回" }.joined(separator: "\n\n"))
        let cid = try store.create(title: "Reply navigation references")
        for index in 0..<160 {
            try store.append(conversationID: cid, role: index.isMultiple(of: 2) ? "user" : "assistant", text: "中间历史消息 \(index)")
        }
        let reference = try store.append(conversationID: cid, role: "user", text: "查看之前的回复", presentation:
            MessagePresentation(quotes: [MessageQuote(sourceMessageID: long.id, text: long.text, kind: .reply)]))
        try store.append(conversationID: cid, role: "assistant", text: "可以点击上面的回复卡片")
        let model = AgentModel(app: app)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApplication.shared.windows.first { $0.title == "Asky AI" }!
        defer { window.orderOut(nil) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func marker(_ id: String) -> NSView? {
            descendants(window.contentView!).first { $0.identifier?.rawValue == id }
        }
        func click(_ point: NSPoint) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
            }
        }
        try await Task.sleep(for: .milliseconds(1200))
        let scroll = descendants(window.contentView!).compactMap { $0 as? NSScrollView }.first { $0.contentSize.height > 200 }!
        model.draft = "保留未发送的草稿"
        let originalIDs = model.items.map(\.id)
        precondition(!originalIDs.contains(long.id), "The source must begin outside the loaded page")
        let referenceView = marker("transcript-group-" + reference.id)!
        let cardRect = scroll.contentView.convert(referenceView.bounds, from: referenceView)
        let cardPoint = NSPoint(x: cardRect.maxX - 152, y: cardRect.minY + 26)
        precondition(scroll.contentView.bounds.contains(cardPoint), "The actual reply card must be visible")
        click(scroll.contentView.convert(cardPoint, to: nil))
        try await Task.sleep(for: .milliseconds(1200))
        precondition(model.replyNavigation?.messageID == long.id, "Clicking the sent card must navigate to its source")
        precondition(model.items.count <= AgentModel.window && model.hasNewer)
        precondition(model.draft == "保留未发送的草稿" && !model.isRunning)
        func assertAligned(_ id: String) {
            let reply = marker("transcript-reply-" + id)!
            let offset = scroll.contentView.convert(reply.bounds, from: reply).minY - scroll.contentView.bounds.minY
            precondition(abs(offset - 90) <= 2, "Original reply text must begin below the toolbar: \(offset)")
        }
        assertAligned(long.id)
        let surface = window.contentView!
        let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)!
        surface.cacheDisplay(in: surface.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/reply-navigation.png"))
        // Interrupt an in-flight scroll: animation and layout corrections must relinquish control.
        precondition(model.revealReply(short.id))
        try await Task.sleep(for: .milliseconds(100))
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        let manualY = scroll.contentView.bounds.minY + 160
        scroll.contentView.scroll(to: NSPoint(x: 0, y: manualY))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(1000))
        precondition(abs(scroll.contentView.bounds.minY - manualY) <= 1, "Manual reading must cancel reply alignment")
        let beforeAnimation = scroll.contentView.bounds.minY
        precondition(model.revealReply(short.id))
        try await Task.sleep(for: .milliseconds(100))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let intermediate = scroll.contentView.bounds.minY
            precondition(intermediate > 1 && intermediate < beforeAnimation - 1,
                         "Reply navigation must visibly scroll through an intermediate position: \(beforeAnimation) -> \(intermediate)")
            print("Reply animation intermediate: \(beforeAnimation) -> \(intermediate)")
        }
        try await Task.sleep(for: .milliseconds(1100))
        assertAligned(short.id)
        precondition(model.revealReply(short.id))
        try await Task.sleep(for: .milliseconds(1100))
        assertAligned(short.id)
        // The existing floating control returns from the historical neighborhood to the latest page.
        let editor = descendants(window.contentView!).compactMap { $0 as? NSTextView }.first { $0.isEditable }!
        let editorRect = scroll.contentView.convert(editor.bounds, from: editor)
        click(scroll.contentView.convert(NSPoint(x: scroll.contentView.bounds.midX, y: editorRect.minY - 34), to: nil))
        try await Task.sleep(for: .milliseconds(1100))
        precondition(model.items.map(\.id) == originalIDs && !model.hasNewer)
        let priorNavigation = model.replyNavigation
        precondition(!model.revealReply("deleted-source"))
        precondition(model.items.map(\.id) == originalIDs && model.replyNavigation == priorNavigation)
        model.beginResponse(taskID: "navigation-active")
        precondition(!model.revealReply(long.id), "Navigation must not evict an active response")
        precondition(model.items.map(\.id) == originalIDs)
        model.finishTask(conversationID: cid)
        // Conversation-scoped navigation also loads older messages without switching segments.
        model.open(cid)
        let oldReply = store.messages(conversationID: cid, limit: 1000).first { $0.role == "assistant" }!
        precondition(model.revealReply(oldReply.id))
        precondition(model.conversationID == cid && model.items.contains { $0.id == oldReply.id })
        precondition(!model.revealReply(long.id), "Scoped history must not switch conversations")
        print("Reply navigation passed: actual card click, cross-segment history, short/long top alignment, repeated jumps, manual scroll, return to latest, missing source and active response protection")
    }

    static func scrollStabilityRegression(app: AppModel) async throws {
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Scroll stability")
        for index in 0..<160 {
            let count = index.isMultiple(of: 2) ? 1 : 3 + index % 9
            let text = (0..<count).map {
                "消息 \(index) 段落 \($0)：滚动前后必须完整保留正文和布局位置。" + String(repeating: "长消息需要正确换行。", count: index % 5)
            }.joined(separator: "\n\n")
            try store.append(conversationID: cid, role: index.isMultiple(of: 2) ? "user" : "assistant", text: text)
        }
        let model = AgentModel(app: app)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApplication.shared.windows.first { $0.title == "Asky AI" }!
        defer { window.orderOut(nil) }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.contentSize.height > 200 { return scroll }
            return view.subviews.compactMap(findScroll).first
        }
        func texts(_ view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(texts)
        }
        try await Task.sleep(for: .milliseconds(1200))
        let scroll = findScroll(window.contentView!)!
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        let height = scroll.documentView!.bounds.height
        for fraction: CGFloat in [0, 0.25, 0.5, 0.75, 1, 0.5, 0, 1] {
            let offset = (height - scroll.contentView.bounds.height) * fraction
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(300))
            let actualHeight = scroll.documentView!.bounds.height
            print("Scroll fraction=\(fraction), height=\(actualHeight), initial=\(height), offset=\(scroll.contentView.bounds.minY)")
            precondition(abs(actualHeight - height) <= 1, "Scrolling unchanged messages must not change the document height")
            precondition(abs(scroll.contentView.bounds.minY - offset) <= 1, "Reading position must not jump while scrolling")
            let visible = scroll.contentView.bounds.insetBy(dx: 0, dy: 80)
            precondition(texts(scroll).contains { !$0.string.isEmpty && scroll.contentView.convert($0.bounds, from: $0).intersects(visible) },
                         "The viewport must contain message text after every scroll")
        }
        let latestIDs = model.items.map(\.id)
        func click(_ point: NSPoint) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
            }
        }
        func clickAboveComposer(_ distance: CGFloat) {
            let editor = texts(window.contentView!).first { $0.isEditable }!
            let editorRect = scroll.contentView.convert(editor.bounds, from: editor)
            let position = NSPoint(x: scroll.contentView.bounds.midX, y: editorRect.minY - distance)
            precondition(scroll.contentView.bounds.contains(position), "History control must be inside the viewport")
            click(scroll.contentView.convert(position, to: nil))
        }
        for page in 1...3 {
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(150))
            if page == 1 {
                let surface = window.contentView!
                let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)!
                surface.cacheDisplay(in: surface.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/scroll-older-button.png"))
            }
            let previousFirst = model.items.first!.id
            let text = texts(scroll).first { $0.string.hasPrefix(model.items.first!.text.components(separatedBy: "\n\n")[0]) }!
            let before = scroll.contentView.convert(text.bounds, from: text).minY - scroll.contentView.bounds.minY
            click(scroll.convert(NSPoint(x: scroll.bounds.midX,
                y: scroll.isFlipped ? scroll.bounds.minY + 82 : scroll.bounds.maxY - 82), to: nil))
            try await Task.sleep(for: .milliseconds(600))
            precondition(model.items.first?.id != previousFirst, "The older-page button must load a page")
            precondition(model.items.count == min(40 + page * 40, 120))
            let after = scroll.contentView.convert(text.bounds, from: text).minY - scroll.contentView.bounds.minY
            precondition(abs(before - after) <= 1, "Prepending history must retain the visible message offset: \(before) -> \(after)")
        }
        precondition(model.hasNewer, "Native paging must expose evicted newer messages")
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.documentView!.bounds.height - scroll.contentView.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(150))
        let lastID = model.items.last!.id
        let surface = window.contentView!
        let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)!
        surface.cacheDisplay(in: surface.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/scroll-newer-button.png"))
        // Follow the current composer position, including its variable height, instead of the window bottom.
        // Editor top inset 10 + transcript tail 13 + page-button bottom padding 40 + half its height 14.
        clickAboveComposer(77)
        try await Task.sleep(for: .milliseconds(600))
        precondition(model.items.last?.id != lastID, "The newer-page button must recover the adjacent page")
        // The floating button must return to the latest persisted messages, not the end of an old page.
        // Editor top inset 10 + floating button gap 8 + half its height 16.
        clickAboveComposer(34)
        try await Task.sleep(for: .milliseconds(800))
        precondition(model.items.map(\.id) == latestIDs && !model.hasNewer)
        precondition(abs(scroll.documentView!.bounds.maxY - scroll.documentVisibleRect.maxY) <= 1)
        print("Scroll stability passed: repeated scrolling, visible text, native older/newer buttons, reading anchor and latest jump")
    }

    static func scrollPerfRegression(app: AppModel) async throws {
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Scroll perf")
        for index in 0..<120 {
            if index.isMultiple(of: 2) {
                try store.append(conversationID: cid, role: "user", text: "第 \(index) 轮问题：请结合代码说明 SwiftUI 和 AppKit 混排时的渲染开销，以及需要注意哪些细节？")
            } else {
                let md = """
                第 \(index) 轮分析如下：

                - **主线程布局**：检查 `updateNSView` 和 `sizeThatFits` 是否在滚动时被重复调用。
                - **图层合成**：检查 `CABackdropLayer` 与 `.glassEffect` 的合成面积。
                - **追踪区域**：确认 `NSTrackingArea` 与 `.onHover` 是否触发额外重绘。

                ```swift
                func measure() -> Int {
                    return \(index) * 2
                }
                ```

                | 项目 | 指标 | 说明 |
                | --- | --- | --- |
                | 帧耗时 | < 8.3ms | 120Hz 目标 |
                | 状态隔离 | 独立 Observable | 避免重建子树 |
                """
                try store.append(conversationID: cid, role: "assistant", text: md)
            }
        }
        let model = AgentModel(app: app)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.show()
        let window = NSApplication.shared.windows.last { $0.title == "Asky AI" && $0.isVisible }!
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(800))
        model.loadOlder()
        try await Task.sleep(for: .milliseconds(500))
        model.loadOlder()
        try await Task.sleep(for: .milliseconds(1200))

        func allViews(_ root: NSView) -> [NSView] {
            [root] + root.subviews.flatMap(allViews)
        }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.contentSize.height > 200 { return scroll }
            return view.subviews.compactMap(findScroll).first
        }
        let scroll = findScroll(window.contentView!)!
        let views = allViews(scroll)
        let textViews = views.compactMap { $0 as? NSTextView }
        let trackingAreas = views.reduce(0) { $0 + $1.trackingAreas.count }
        print("PERF STATS: items=\(model.items.count), totalNSViews=\(views.count), textViews=\(textViews.count), trackingAreas=\(trackingAreas), docHeight=\(scroll.documentView!.bounds.height), startY=\(scroll.contentView.bounds.minY)")

        // Measure main-thread tick jitter during active trackpad-style scroll events
        var frameIntervals: [Double] = []
        var eventDurationsMs: [Double] = []
        var lastTick = ProcessInfo.processInfo.systemUptime
        final class LinkObserver: NSObject {
            var onTick: (() -> Void)?
            @objc func step(_ link: CADisplayLink) { onTick?() }
        }
        let observer = LinkObserver()
        observer.onTick = {
            let now = ProcessInfo.processInfo.systemUptime
            frameIntervals.append((now - lastTick) * 1000.0)
            lastTick = now
        }
        let link = window.displayLink(target: observer, selector: #selector(LinkObserver.step(_:)))
        link.add(to: .main, forMode: .common)
        defer { link.invalidate() }

        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 900
        let cgLocation = CGPoint(x: window.frame.midX, y: mainScreenHeight - window.frame.midY)
        func makeWheel(dy: Double, phase: Int64, momentum: Int64 = 0) -> NSEvent {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy), wheel2: 0, wheel3: 0)!
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            cg.location = cgLocation
            cg.timestamp = DispatchTime.now().uptimeNanoseconds
            return NSEvent(cgEvent: cg)!
        }

        let centerInWindow = NSPoint(x: window.contentView!.bounds.midX, y: window.contentView!.bounds.midY)
        // Scroll up (positive dy) then down (negative dy) via hit-tested view inside scroll
        for pass in 0..<4 {
            let dy: Double = pass.isMultiple(of: 2) ? 45 : -45
            if let target = scroll.contentView.hitTest(scroll.contentView.convert(centerInWindow, from: nil)) {
                target.scrollWheel(with: makeWheel(dy: 0, phase: 128))
            }
            for i in 0..<80 {
                let phase: Int64 = i == 0 ? 1 : (i == 79 ? 4 : 2)
                let ev = makeWheel(dy: i == 79 ? 0 : dy, phase: phase)
                let t0 = ProcessInfo.processInfo.systemUptime
                if let target = scroll.contentView.hitTest(scroll.contentView.convert(centerInWindow, from: nil)) {
                    target.scrollWheel(with: ev)
                } else {
                    scroll.scrollWheel(with: ev)
                }
                if let move = NSEvent.mouseEvent(with: .mouseMoved, location: centerInWindow, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: i + 1, clickCount: 0, pressure: 0) {
                    window.sendEvent(move)
                }
                let dt = (ProcessInfo.processInfo.systemUptime - t0) * 1000.0
                eventDurationsMs.append(dt)
                try await Task.sleep(for: .milliseconds(8))
            }
            print("PERF PASS \(pass) endY=\(scroll.contentView.bounds.minY)")
            try await Task.sleep(for: .milliseconds(250))
        }
        let sortedFrames = frameIntervals.dropFirst().sorted()
        let p50Frame = sortedFrames[sortedFrames.count / 2]
        let p95Frame = sortedFrames[Int(Double(sortedFrames.count) * 0.95)]
        let maxFrame = sortedFrames.last ?? 0
        let droppedOver16 = sortedFrames.filter { $0 > 16.7 }.count
        let droppedOver33 = sortedFrames.filter { $0 > 33.3 }.count
        let sortedEv = eventDurationsMs.sorted()
        let p50Ev = sortedEv[sortedEv.count / 2]
        let p95Ev = sortedEv[Int(Double(sortedEv.count) * 0.95)]
        let maxEv = sortedEv.last ?? 0
        print(String(format: "PERF RESULT: frames=%d, p50=%.2fms, p95=%.2fms, max=%.2fms, >16.7ms=%d, >33.3ms=%d | event p50=%.2fms, p95=%.2fms, max=%.2fms",
                     sortedFrames.count, p50Frame, p95Frame, maxFrame, droppedOver16, droppedOver33, p50Ev, p95Ev, maxEv))
    }

    static func restoredTranscriptRegression(app: AppModel) async throws {
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Restored transcript")
        for index in 0..<38 {
            let text = (0...(index.isMultiple(of: 2) ? 0 : 8 + index % 9)).map {
                "历史消息 \(index)，段落 \($0)：恢复会话时直接显示消息，不需要点击窗口或回到底部。"
            }.joined(separator: "\n\n")
            try store.append(conversationID: cid, role: index.isMultiple(of: 2) ? "user" : "assistant", text: text)
        }
        try store.append(conversationID: cid, role: "user", text: "最后一个问题")
        let answer = CommandLine.arguments.contains("--restored-long-reply")
            ? (0..<24).map { "段落 \($0)：恢复时也要正确测量长回答。\n\n$$\\int_0^1 x^2 dx = \\frac{1}{3}$$\n\n| 写法 | 含义 |\n| --- | --- |\n| `x^2` | 平方 |" }.joined(separator: "\n\n")
            : "重新打开后应立即看到这条回答。"
        try store.append(conversationID: cid, role: "assistant", text: answer)
        let model = AgentModel(app: app)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApplication.shared.windows.first { $0.title == "Asky AI" }!
        defer { window.orderOut(nil) }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.contentSize.height > 200 { return scroll }
            return view.subviews.compactMap(findScroll).first
        }
        func findReply(_ view: NSView, id: String) -> NSView? {
            if view.identifier?.rawValue == ("transcript-reply-" + id) { return view }
            return view.subviews.compactMap { findReply($0, id: id) }.first
        }
        for attempt in 0..<3 {
            if attempt > 0 { window.close(); controller.show() }
            // No clicks, scroll events or forced layout before inspecting the initial frame.
            try await Task.sleep(for: .milliseconds(1000))
            let scroll = findScroll(window.contentView!)!
            let gap = scroll.documentView!.bounds.maxY - scroll.documentVisibleRect.maxY
            print("Restored transcript attempt=\(attempt), gap=\(gap), document=\(scroll.documentView!.frame), clip=\(scroll.contentView.bounds)")
            let reply = findReply(window.contentView!, id: model.items.last(where: { $0.kind == .assistant })!.id)!
            let rect = scroll.contentView.convert(reply.bounds, from: reply)
            if CommandLine.arguments.contains("--restored-long-reply") {
                precondition(abs(rect.minY - scroll.contentView.bounds.minY - 90) <= 1,
                             "A restored long answer must begin below the header with its bubble padding")
            } else {
                precondition(abs(gap) <= 1, "Restored short replies must stay at the natural bottom without a blank screen")
            }
            precondition(scroll.contentView.bounds.intersects(rect), "Restored reply must be visible without user interaction")
        }
        let scroll = findScroll(window.contentView!)!
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(350))
        precondition(scroll.documentView!.bounds.maxY - scroll.documentVisibleRect.maxY > 100,
                     "Initial layout following must stop as soon as the reader scrolls")
        print("Restored transcript passed: cold open, repeated close/reopen and manual reading takeover")
    }

    static func sendStabilityRegression(app: AppModel) async throws {
        app.preferences.automaticUpdates = false
        await app.start()
        app.modelConfiguration = ModelConfiguration(baseURL: URL(string: "http://127.0.0.1:1/v1")!,
            modelName: "send-stability", credentialRef: "Asky-send-stability-" + UUID().uuidString)
        let model = AgentModel(app: app)
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Send stability")
        for index in 0..<24 {
            try store.append(conversationID: cid, role: index.isMultiple(of: 2) ? "user" : "assistant",
                text: "历史消息 \(index)：" + String(repeating: "用于填充滚动高度的测试文案。", count: 6))
        }
        model.open(cid)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApplication.shared.windows.first { $0.title == "Asky AI" }!
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(600))
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.contentSize.height > 200 { return scroll }
            return view.subviews.compactMap(findScroll).first
        }
        func textViews(_ view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
        }
        let scroll = findScroll(window.contentView!)!
        let rootView = window.contentView!
        let rootLayer = rootView.layer!
        func measureSend(_ label: String, text: String) async throws {
            model.draft = text
            try await Task.sleep(for: .milliseconds(120))
            let expected = model.draft
            let t0 = ProcessInfo.processInfo.systemUptime
            model.send()
            var samples: [(ms: Int, modelWinY: CGFloat, presWinY: CGFloat, clipY: CGFloat, docH: CGFloat)] = []
            for _ in 0..<70 {
                if !model.isRunning || model.items.last?.kind == .error { break }
                let ms = Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
                if let tv = textViews(rootView).first(where: { !$0.isEditable && $0.string == expected }) {
                    let modelRect = tv.convert(tv.bounds, to: rootView)
                    let presRect: CGRect
                    if let pres = tv.layer?.presentation(), let target = rootLayer.presentation() {
                        presRect = pres.convert(pres.bounds, to: target)
                    } else {
                        presRect = modelRect
                    }
                    samples.append((ms, modelRect.minY, presRect.minY, scroll.contentView.bounds.minY,
                                    scroll.documentView?.bounds.height ?? 0))
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            while model.isRunning {
                model.stop()
                try await Task.sleep(for: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(150))
            guard let final = samples.last else {
                fatalError("[\(label)]: sent message bubble never rendered")
            }
            let maxModelY = samples.map(\.modelWinY).max() ?? final.modelWinY
            let maxPresY = samples.map(\.presWinY).max() ?? final.presWinY
            let overModel = maxModelY - final.modelWinY
            let overPres = maxPresY - final.presWinY
            print(String(format: "[%@] (%d samples): final=(m:%.1f p:%.1f) overUp=(m:%.1f p:%.1f)",
                label, samples.count, final.modelWinY, final.presWinY, overModel, overPres))
            if overModel > 2 || overPres > 2 {
                for s in samples.prefix(20) {
                    print(String(format: "  t=%3dms modelY=%.1f presY=%.1f clipY=%.1f docH=%.1f",
                        s.ms, s.modelWinY, s.presWinY, s.clipY, s.docH))
                }
            }
            precondition(overModel <= 2 && overPres <= 2,
                         "[\(label)] sent message jumped upward before settling: overModel=\(overModel), overPres=\(overPres)")
        }
        // Scenario A: normal overflowing chat
        try await measureSend("A1", text: "发送测试 A1")
        try await measureSend("A2-multiline", text: "发送测试 A2\n第二行\n第三行")

        // Scenario B: 120 items (window boundary + collapsed TranscriptGroupWindow)
        for index in 0..<100 {
            try store.append(conversationID: cid, role: index.isMultiple(of: 2) ? "user" : "assistant",
                text: "填充历史 \(index)：" + String(repeating: "用于达到120条窗口上限的长消息内容。", count: index.isMultiple(of: 2) ? 3 : 12))
        }
        model.open(cid)
        try await Task.sleep(for: .milliseconds(1000))
        try await measureSend("B1-120window", text: "窗口上限测试 B1")
        try await measureSend("B2-120window", text: "窗口上限测试 B2")
        try await measureSend("B3-120window", text: "窗口上限测试 B3")

        // Scenario C: after a long assistant reply (replyID set)
        let longCID = model.conversationID!
        model.beginResponse(taskID: "long-reply-test")
        try await Task.sleep(for: .milliseconds(50))
        model.handle(.message(taskID: "long-reply-test", String(repeating: "这是一段非常长的回复内容用于测试长回复后发送新消息的表现。\n", count: 40)), conversationID: longCID)
        model.handle(.taskState(taskID: "long-reply-test", .completed), conversationID: longCID)
        model.finishTask(conversationID: longCID)
        try await Task.sleep(for: .milliseconds(400))
        try await measureSend("C1-afterLongReply", text: "长回复后发送 C1")
        print("Send stability regression passed: no upward jump on normal, multiline, 120-window trim, or post-long-reply sends")
    }

    static func bottomPushRegression(app: AppModel) async throws {
        let model = AgentModel(app: app)
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Bottom push")
        try store.append(conversationID: cid, role: "user", text: "你好")
        try store.append(conversationID: cid, role: "assistant", text: "晚上好，今天有什么要做的？")
        model.open(cid)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApplication.shared.windows.first { $0.title == "Asky AI" }!
        defer { window.orderOut(nil) }
        precondition(window.frame.size == NSSize(width: 560, height: 680), "Chat must open at 560 × 680")
        precondition(!window.styleMask.contains(.resizable), "Chat must not allow user resizing")
        precondition(window.minSize == window.maxSize, "Chat size limits must be fixed")
        try await Task.sleep(for: .milliseconds(600))
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.contentSize.height > 200 { return scroll }
            return view.subviews.compactMap(findScroll).first
        }
        let scroll = findScroll(window.contentView!)!
        func capture(_ name: String) throws {
            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/bottom-push-" + name + ".png"))
        }
        try capture("before")
        precondition(abs(scroll.contentSize.height - window.contentLayoutRect.height) <= 1,
                     "The transcript must span the whole window behind the floating composer")
        precondition(scroll.documentView!.bounds.height >= scroll.contentSize.height - 1,
                     "The initial short conversation must occupy a top-aligned viewport")
        try store.append(conversationID: cid, role: "user", text: "晚上好")
        model.open(cid)
        model.beginResponse(taskID: "bottom-push")
        try await Task.sleep(for: .milliseconds(800))
        try capture("after")
        func textViews(_ view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
        }
        let greeting = textViews(window.contentView!).first { $0.string == "你好" }!
        let greetingRect = scroll.contentView.convert(greeting.bounds, from: greeting)
        precondition(greetingRect.minY >= scroll.contentView.bounds.minY + 64,
                     "A second short question must leave the first exchange visible, not start a new screen")
        precondition(scroll.documentView!.bounds.height <= scroll.contentSize.height + 1,
                     "Several short messages must share one screen without a full-height current turn")
        var gap = scroll.documentView!.bounds.maxY - scroll.documentVisibleRect.maxY
        precondition(abs(gap) <= 1, "New message and waiting bubble must be visible at the bottom: gap=\(gap)")
        model.handle(.taskState(taskID: "bottom-push", .cancelled), conversationID: cid)
        model.finishTask(conversationID: cid)
        for index in 0..<20 {
            try store.append(conversationID: cid, role: index.isMultiple(of: 2) ? "assistant" : "user",
                text: String(repeating: "历史内容应该向上推。", count: 8))
        }
        model.open(cid)
        try await Task.sleep(for: .milliseconds(800))
        try store.append(conversationID: cid, role: "user", text: "新的消息")
        model.open(cid)
        model.beginResponse(taskID: "bottom-push-overflow")
        try await Task.sleep(for: .milliseconds(1400))
        gap = scroll.documentView!.bounds.maxY - scroll.documentVisibleRect.maxY
        precondition(abs(gap) <= 1, "Overflowing chat must settle at the actual bottom: gap=\(gap)")
        try capture("overflow")
        precondition(scroll.documentView!.bounds.height > scroll.contentSize.height * 2, "History must really overflow")
        model.handle(.taskState(taskID: "bottom-push-overflow", .cancelled), conversationID: cid)
        model.finishTask(conversationID: cid)
        try store.append(conversationID: cid, role: "user", text: String(repeating: "这是很长的用户问题，回答出现后可以把它往上推。\n", count: 25))
        model.open(cid)
        model.beginResponse(taskID: "fast-reply")
        try await Task.sleep(for: .milliseconds(40))
        let answer = String(repeating: "回答应该从开头往下读，首次尽量填满可视区域，剩余内容向下阅读，完成时不能跳到结尾。", count: 80)
        model.handle(.message(taskID: "fast-reply", answer), conversationID: cid)
        model.handle(.taskState(taskID: "fast-reply", .completed), conversationID: cid)
        model.finishTask(conversationID: cid)
        try await Task.sleep(for: .milliseconds(1400))
        func replyMarker(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue.hasPrefix("transcript-reply-") == true { return view }
            return view.subviews.compactMap(replyMarker).last
        }
        let reply = replyMarker(window.contentView!)!
        let rect = scroll.contentView.convert(reply.bounds, from: reply)
        let visible = scroll.contentView.bounds.maxY - rect.minY
        precondition(visible > 250 && rect.height > visible,
                     "Long replies must fill the viewport from their beginning: visible=\(visible)")
        precondition(abs(rect.minY - scroll.contentView.bounds.minY - 90) <= 1,
                     "Long answers stop at the beginning of the bubble, allowing the user question to move above it")
        print("Long reply visible height: \(visible)")
        try capture("completed")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(350))
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber),
                                 "build/composer-overlay-\(appearance.rawValue).png"]
            try capture.run(); capture.waitUntilExit()
            precondition(capture.terminationStatus == 0)
        }
        window.appearance = NSAppearance(named: .aqua)
        try store.append(conversationID: cid, role: "user", text: "收到")
        model.open(cid)
        model.beginResponse(taskID: "short-reply")
        try await Task.sleep(for: .milliseconds(40))
        model.handle(.message(taskID: "short-reply", (1...7).map { "第 \($0) 行：这一屏能放下的回答应该完整展示。" }.joined(separator: "\n")), conversationID: cid)
        model.handle(.taskState(taskID: "short-reply", .completed), conversationID: cid)
        model.finishTask(conversationID: cid)
        try await Task.sleep(for: .milliseconds(1400))
        let shortReply = replyMarker(window.contentView!)!
        let shortRect = scroll.contentView.convert(shortReply.bounds, from: shortReply)
        gap = scroll.documentView!.bounds.maxY - scroll.documentVisibleRect.maxY
        precondition(abs(gap) <= 1, "Fitting replies must end at the natural bottom with no per-turn blank space")
        precondition(shortRect.height > 88, "The fitting reply must exceed the former four-line limit")
        precondition(shortRect.minY >= scroll.contentView.bounds.minY && shortRect.maxY <= scroll.contentView.bounds.maxY,
                     "Any reply fitting below the question must be fully visible")
        try capture("short")
        func assertReplyAboveComposer() {
            let editor = textViews(window.contentView!).first { $0.isEditable }!
            let editorRect = scroll.contentView.convert(editor.bounds, from: editor)
            let replyRect = scroll.contentView.convert(shortReply.bounds, from: shortReply)
            precondition(replyRect.maxY <= editorRect.minY - 10,
                         "The final reply must remain above the composer's top padding")
        }
        assertReplyAboveComposer()
        let compactHeight = scroll.documentView!.bounds.height
        model.draft = (1...20).map { "第 \($0) 行草稿：输入框达到最大高度后，滚动条靠近玻璃边缘。" }.joined(separator: "\n")
        try await Task.sleep(for: .milliseconds(600))
        try capture("expanded-before-scroll")
        precondition(scroll.documentView!.bounds.height > compactHeight + 40,
                     "A taller composer must reserve more scrollable space: before=\(compactHeight), after=\(scroll.documentView!.bounds.height), editor=\(textViews(window.contentView!).first { $0.isEditable }!.frame)")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.documentView!.bounds.maxY - scroll.contentSize.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(200))
        assertReplyAboveComposer()
        try capture("expanded-composer")
        let editor = textViews(window.contentView!).first { $0.isEditable }!
        let editorScroll = editor.enclosingScrollView!
        let viewport = window.contentView!.convert(editorScroll.bounds, from: editorScroll)
        let textOrigin = window.contentView!.convert(editor.textContainerOrigin, from: editor)
        precondition(abs(textOrigin.x - 24) < 1, "Composer text must keep its original left inset")
        precondition(abs(window.contentView!.bounds.maxX - viewport.maxX - 16) < 1,
                     "Scroll view must sit 4 pt inside the glass, which is 12 pt inside the window")
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            editorScroll.flashScrollers()
            try await Task.sleep(for: .milliseconds(150))
            try capture("composer-scroller-" + name)
        }
        print("Natural chat flow passed: short, overflowing and fitting replies, fixed window, waiting bubble")
    }

    static func readingScrollRegression(app: AppModel) async throws {
        let model = AgentModel(app: app)
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Reading position")
        if CommandLine.arguments.contains("--scroll-history") {
            for index in 0..<30 {
                let paragraphCount = index.isMultiple(of: 2) ? index % 3 : 12 + index % 17
                let text = (0...paragraphCount).map { "历史消息 \(index)，段落 \($0)：用于验证不同高度的对话气泡。包含换行的长内容需要在滚动过程中重新计算布局，不能只使用最初估算的高度。" }.joined(separator: "\n\n")
                try store.append(conversationID: cid, role: index.isMultiple(of: 2) ? "user" : "assistant", text: text)
            }
        }
        try store.append(conversationID: cid, role: "user", text: "请给我一篇长回答")
        model.open(cid)
        model.beginResponse(taskID: "reading-scroll")
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApplication.shared.windows.first { $0.title == "Asky AI" }!
        defer { window.orderOut(nil) }
        precondition(window.frame.size == NSSize(width: 560, height: 680), "Chat must open at 560 × 680")
        precondition(!window.styleMask.contains(.resizable), "Chat must not allow user resizing")
        precondition(window.minSize == window.maxSize, "Chat size limits must be fixed")
        try await Task.sleep(for: .milliseconds(500))
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.contentSize.height > 200 { return scroll }
            return view.subviews.compactMap(findScroll).first
        }
        let scroll = findScroll(window.contentView!)!
        precondition(!scroll.hasVerticalScroller, "Transcript hides its scrollbar")
        func historyButtonExists(_ view: NSView) -> Bool {
            if let button = view as? NSButton, button.toolTip == "历史对话" || button.toolTip == "Conversation history" { return true }
            return view.subviews.contains(where: historyButtonExists)
        }
        precondition(!historyButtonExists(window.contentView!), "Retired history entry must be absent")
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        let before = scroll.contentView.bounds.minY
        let answer = (1...70).map { "第 \($0) 段：这是一篇需要从上往下阅读的长回答。" }.joined(separator: "\n\n")
        model.handle(.message(taskID: "reading-scroll", answer), conversationID: cid)
        model.handle(.taskState(taskID: "reading-scroll", .completed), conversationID: cid)
        model.finishTask(conversationID: cid)
        try await Task.sleep(for: .milliseconds(900))
        window.contentView!.layoutSubtreeIfNeeded()
        precondition(scroll.documentView!.bounds.height > scroll.contentSize.height * 2, "Fixture must overflow")
        precondition(abs(scroll.contentView.bounds.minY - before) < 2, "Long answer must retain the reading position: before=\(before), after=\(scroll.contentView.bounds.minY)")
        // Revisit older rows repeatedly in the fixed production window.
        let sizes: [(Double, Double)] = Array(repeating: (560, 680), count: 3)
        for (attempt, size) in sizes.enumerated() {
            try await Task.sleep(for: .milliseconds(300))
            scroll.contentView.scroll(to: NSPoint(x: 0, y: attempt == 0 ? 200 : 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(150))
            if attempt == 0 && !CommandLine.arguments.contains("--scroll-history") {
                precondition(abs(scroll.contentView.bounds.minY - 200) < 2, "Reader must be able to scroll down manually")
            }
            // Lazy history rows can refine their estimated heights after the move.
            precondition(scroll.documentView!.bounds.maxY - scroll.documentVisibleRect.maxY > 100,
                         "The click must start well above the bottom")
            // Send a native click through the window to the visible bottom-center control.
            func composerEditor(_ view: NSView) -> NSTextView? {
                if let editor = view as? NSTextView, editor.isEditable { return editor }
                return view.subviews.compactMap(composerEditor).first
            }
            let editor = composerEditor(window.contentView!)!
            let editorRect = scroll.contentView.convert(editor.bounds, from: editor)
            // Composer top padding (10), button gap (8), and half its height (16).
            let point = scroll.contentView.convert(NSPoint(x: scroll.contentView.bounds.midX,
                                                           y: editorRect.minY - 34), to: nil)
            let startY = scroll.contentView.bounds.minY
            func clickBottom() {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                    window.sendEvent(event)
                }
            }
            if attempt == 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                clickBottom()
                try await Task.sleep(for: .milliseconds(70))
                NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: startY))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await Task.sleep(for: .milliseconds(400))
                precondition(abs(scroll.contentView.bounds.minY - startY) <= 1,
                             "Manual scrolling must immediately take over from the bottom animation")
            }
            clickBottom()
            var intermediatePositions = Set<CGFloat>()
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(16))
                let y = scroll.contentView.bounds.minY
                let distance = scroll.documentView!.bounds.maxY - scroll.contentView.bounds.height - startY
                let progress = (y - startY) / distance
                if (0.05...0.95).contains(progress) {
                    intermediatePositions.insert(y)
                }
            }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                precondition(intermediatePositions.count >= 3,
                             "Clicking the bottom button must animate through multiple positions: saw \(intermediatePositions.count)")
            }
            try await Task.sleep(for: .milliseconds(380))
            window.contentView!.layoutSubtreeIfNeeded()
            let gap = scroll.documentView!.bounds.maxY - scroll.documentVisibleRect.maxY
            precondition(abs(gap) <= 1, "One button press must reach the actual bottom, including padding: attempt=\(attempt), gap=\(gap), document=\(scroll.documentView!.frame), clip=\(scroll.contentView.bounds), visible=\(scroll.documentVisibleRect)")
            print("One-click bottom: attempt=\(attempt), size=\(size), intermediate positions=\(intermediatePositions.count), gap=\(gap)")
        }
        let settled = scroll.contentView.bounds.minY
        // Returning to the bottom must not enable ongoing automatic reply following.
        model.beginResponse(taskID: "reading-scroll-followup")
        model.handle(.message(taskID: "reading-scroll-followup", answer), conversationID: cid)
        model.handle(.taskState(taskID: "reading-scroll-followup", .completed), conversationID: cid)
        model.finishTask(conversationID: cid)
        try await Task.sleep(for: .milliseconds(900))
        precondition(abs(scroll.contentView.bounds.minY - settled) < 2, "Later replies must still preserve the reading position")
        print("Reading scroll regression passed: preserved reading position before and after manual bottom jumps")
    }

    static func selectionPreview(app: AppModel) async throws {
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "文字选区")
        let source = try store.append(conversationID: cid, role: "assistant", text: #"可以从最简单的例子开始理解：平方根和立方根是平方、立方的逆运算。平方根：`\sqrt{x}` → $\sqrt{x}$，立方根：$\sqrt[3]{x}$。先找到一个数，计算它的平方或立方，再对照原来的数，就容易理解这两个运算之间的关系。"#)
        let model = AgentModel(app: app)
        model.open(cid)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApplication.shared.windows.first { $0.title == "Asky AI" }!
        defer { window.orderOut(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func capture(_ name: String, window: NSWindow) throws {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", String(window.windowNumber), "build/selection-\(name).png"]
            try process.run(); process.waitUntilExit()
            precondition(process.terminationStatus == 0)
        }
        func click(_ window: NSWindow, point: NSPoint) async throws {
            let restingSize = window.frame.size
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApplication.shared.sendEvent(event)
                if type == .leftMouseDown {
                    try await Task.sleep(for: .milliseconds(140))
                    precondition(window.frame.size == restingSize, "Selection actions must keep their size while pressed")
                    try capture("pressed-menu", window: window)
                } else {
                    precondition(!window.isVisible, "Selection actions must dismiss immediately on release")
                }
            }
        }
        // Exercise the actual message action, including draft preservation and focus.
        try await Task.sleep(for: .milliseconds(400))
        model.draft = "继续解释这条回答"
        for _ in 0..<2 {
            let text = descendants(window.contentView!).compactMap { $0 as? ChatSelectableTextView }.first { $0.string.contains("平方根") }!
            let rect = text.convert(text.bounds, to: nil)
            // The second 28 pt action sits directly beside Copy below the bubble.
            let point = NSPoint(x: rect.minX - 18 + 28 + 14,
                                y: rect.minY - 14 - 6 - 14)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                window.sendEvent(event)
            }
            try await Task.sleep(for: .milliseconds(200))
            precondition(model.quotes.count == 1 && model.quotes[0].text == source.text,
                         "Reply must quote the complete answer exactly once")
            precondition(model.quotes[0].sourceMessageID == source.id && model.quotes[0].kind == .reply)
            precondition(model.draft == "继续解释这条回答", "Reply must preserve the prepared question")
            precondition(!model.isRunning, "Reply must not send automatically")
            precondition((window.firstResponder as? NSTextView)?.isEditable == true, "Reply must focus the composer")
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(700))
            try capture("whole-reply-" + appearance.rawValue, window: window)
        }
        model.quotes.removeAll()
        model.draft = ""
        for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            window.appearance = NSAppearance(named: appearance)
            for color in AgentAvatarColor.allCases {
                model.avatarColor = color
                try await Task.sleep(for: .milliseconds(200))
                let text = descendants(window.contentView!).compactMap { $0 as? ChatSelectableTextView }.first { $0.string.contains("平方根") }!
                window.makeFirstResponder(text)
                text.setSelectedRange(NSRange(location: 0, length: (text.string as NSString).length))
                precondition(text.selectedContent.contains(#"\sqrt[3]{x}"#), "Formula attachments must copy their source")
                precondition(!text.selectedContent.contains("\u{fffc}"), "Never quote attachment placeholders")
                let actual = text.selectedTextAttributes[.backgroundColor] as! NSColor
                precondition(actual == NSColor(color.tint).withAlphaComponent(0.45), "Selection must follow the current Agent color")
                text.showSelectionMenu()
                try await Task.sleep(for: .milliseconds(150))
                let cancelledMenu = window.childWindows!.first { $0 is SurfacePanel && $0.isVisible }!
                // Clicking unused transcript space must clear the actual NSTextView range.
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: window.frame.width - 24, y: window.frame.height / 2),
                        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                    NSApplication.shared.sendEvent(event)
                }
                precondition(text.selectedRange().length == 0 && !cancelledMenu.isVisible,
                             "Blank clicks must clear both selection and menu")
                text.setSelectedRange(NSRange(location: 0, length: (text.string as NSString).length))
                text.showSelectionMenu()
                let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
                NSApplication.shared.sendEvent(escape)
                precondition(text.selectedRange().length == 0 && window.isVisible, "Escape cancels selection without closing chat")
                text.setSelectedRange(NSRange(location: 0, length: (text.string as NSString).length))
                text.showSelectionMenu()
                try await Task.sleep(for: .milliseconds(150))
                let menu = window.childWindows!.first { $0 is SurfacePanel && $0.isVisible }!
                precondition(!menu.hasShadow, "Selection actions must not add the heavy window shadow")
                precondition(menu.frame.height < 60 && menu.frame.width < 320, "Selection menu is one compact horizontal row")
                precondition(window.screen!.visibleFrame.contains(menu.frame))
                if color == .purple {
                    try capture(name, window: window); try capture(name + "-menu", window: menu)
                    let down = NSEvent.mouseEvent(with: .leftMouseDown,
                        location: NSPoint(x: menu.frame.width * 0.25, y: menu.frame.height / 2), modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: menu.windowNumber,
                        context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                    NSApplication.shared.sendEvent(down)
                    try await Task.sleep(for: .milliseconds(140))
                    try capture(name + "-left-light", window: menu)
                    // Drag out to cancel Copy without modifying the user's clipboard.
                    for type in [NSEvent.EventType.leftMouseDragged, .leftMouseUp] {
                        let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: -30, y: -30), modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: menu.windowNumber,
                            context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDragged ? 1 : 0)!
                        NSApplication.shared.sendEvent(event)
                    }
                    try await Task.sleep(for: .milliseconds(250))
                    precondition(menu.isVisible && text.selectedRange().length > 0, "Dragging out cancels the action and preserves the selection")
                }
                try await click(menu, point: NSPoint(x: menu.frame.width * 0.72, y: menu.frame.height / 2))
                try await Task.sleep(for: .milliseconds(250))
                precondition(model.quotes.count == 1, "Add to Chat must add once and deduplicate repeated selections")
                precondition(!menu.isVisible)
                precondition((window.firstResponder as? NSTextView)?.isEditable == true, "Add to Chat must focus the composer")
            }
        }
        model.avatarColor = .purple
        model.draft = "这里的立方根是什么意思？"
        try await Task.sleep(for: .milliseconds(300))
        try capture("draft", window: window)
        // Configuration failure must preserve the prepared question and quote.
        model.send()
        precondition(model.quotes.count == 1 && !model.draft.isEmpty)
        app.preferences.automaticUpdates = false
        await app.start()
        app.modelConfiguration = ModelConfiguration(baseURL: URL(string: "http://127.0.0.1:1/v1")!,
            modelName: "quote-regression", credentialRef: "Asky-quote-unset-" + UUID().uuidString)
        let quote = model.quotes[0]
        precondition(quote.sourceMessageID == source.id)
        model.send()
        let submittedCID = model.conversationID!
        precondition(model.quotes.isEmpty && model.draft.isEmpty)
        let saved = store.messages(conversationID: submittedCID, limit: 40).first { $0.role == "user" }!
        precondition(saved.presentation?.quotes == [quote])
        precondition(saved.text == "这里的立方根是什么意思？")
        for _ in 0..<100 where model.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        model.open(submittedCID)
        precondition(model.items.first { $0.id == saved.id }?.quotes == [quote])
        try await Task.sleep(for: .milliseconds(300))
        try capture("sent", window: window)
        model.addQuote("待移除的片段", sourceMessageID: source.id)
        model.quotes.removeAll()
        precondition(model.quotes.isEmpty)
        print("Selection regression passed: 5 colors in light/dark, formula source, real menu action, deduplication, composer focus, failed-send preservation, send and history restore")
    }

    static func continuousSelectionPreview() async throws {
        let window = NSWindow(contentRect: NSRect(x: 140, y: 140, width: 680, height: 620),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Asky Continuous Selection"
        var quoted = ""
        let wrapped = String(repeating: "自动换行文字 ", count: 16).trimmingCharacters(in: .whitespaces)
        let fixture = """
        开始段落 Alpha

        - 第一项 Apple
        - 第二项 Banana \(wrapped)
          - 嵌套项 Cherry
        - 第三项 Date

        1. 有序一 Echo
        2. 有序二 Foxtrot

        结束段落 Omega 和 $x^2$。
        """
        window.contentView = NSHostingView(rootView: ChatMarkdownView(text: fixture)
            .environment(\.chatQuoteAction, { quoted = $0 }).padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(500))
        func descendants(_ node: NSView) -> [NSView] { [node] + node.subviews.flatMap(descendants) }
        let texts = descendants(window.contentView!).compactMap { $0 as? ChatSelectableTextView }
        for text in texts {
            precondition(abs(text.bounds.width - text.textContainer!.containerSize.width) < 1,
                         "Width probes must not alter the rendered text container")
        }
        let first = texts.first { $0.string.contains("开始段落") }!
        let last = texts.first { $0.string.contains("结束段落") }!
        precondition(texts.first { $0.string.contains("第二项") }!.bounds.height > first.bounds.height * 2)
        let group = first.selectionGroup!
        precondition(texts.allSatisfy { $0.selectionGroup === group })
        func point(_ view: ChatSelectableTextView, _ index: Int) -> NSPoint {
            let manager = view.layoutManager!, container = view.textContainer!
            let glyph = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyph, in: container)
            return view.convert(NSPoint(x: rect.minX + view.textContainerOrigin.x + 0.1,
                                        y: rect.midY + view.textContainerOrigin.y), to: nil)
        }
        func event(_ type: NSEvent.EventType, _ point: NSPoint, in target: NSWindow) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        func drag(_ from: ChatSelectableTextView, _ start: Int, _ to: ChatSelectableTextView, _ end: Int) {
            let destination = point(to, end)
            NSApplication.shared.postEvent(event(.leftMouseDragged, destination, in: window), atStart: false)
            NSApplication.shared.postEvent(event(.leftMouseUp, destination, in: window), atStart: false)
            from.mouseDown(with: event(.leftMouseDown, point(from, start), in: window))
        }
        drag(first, 5, last, 10)
        let expected = "Alpha\n•\t第一项 Apple\n•\t第二项 Banana \(wrapped)\n◦\t嵌套项 Cherry\n•\t第三项 Date\n1.\t有序一 Echo\n2.\t有序二 Foxtrot\n结束段落 Omega"
        precondition(group.selectedText == expected, "Forward drag mismatch: \(group.selectedText.debugDescription)")
        drag(last, 10, first, 5)
        precondition(group.selectedText == expected, "Reverse drag must preserve reading order")
        try await Task.sleep(for: .milliseconds(250))
        let menu = window.childWindows!.first { $0 is SurfacePanel && $0.isVisible }!
        if #available(macOS 26.0, *), let glass = menu.contentView as? NSGlassEffectView {
            precondition(abs(glass.cornerRadius - menu.frame.height / 2) < 0.01, "Menu must be a true capsule")
        }
        let capture = Process()
        capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), "build/continuous-selection.png"]
        try capture.run(); capture.waitUntilExit()
        precondition(capture.terminationStatus == 0)
        let actionPoint = NSPoint(x: menu.frame.width * 0.72, y: menu.frame.height / 2)
        NSApplication.shared.sendEvent(event(.leftMouseDown, actionPoint, in: menu))
        try await Task.sleep(for: .milliseconds(140))
        if #available(macOS 26.0, *), let glass = menu.contentView as? NSGlassEffectView {
            precondition(abs(glass.cornerRadius - menu.frame.height / 2) < 0.01, "Pressed glass must stay capsule-shaped")
        }
        NSApplication.shared.sendEvent(event(.leftMouseUp, actionPoint, in: menu))
        try await Task.sleep(for: .milliseconds(300))
        precondition(quoted == expected, "Add to Chat must receive the complete continuous selection")
        first.selectAll(nil)
        precondition(group.selectedText.contains("x^2"), "Select All must include inline formula source")
        precondition(group.orderedViews.allSatisfy { $0.selectedRange().length == ($0.string as NSString).length })
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            NSApplication.shared.sendEvent(event(type, NSPoint(x: 650, y: 20), in: window))
        }
        precondition(group.selectedText.isEmpty, "Blank click must clear every paragraph, including list markers")
        let apple = texts.first { $0.string.contains("第一项") }!
        let foxtrot = texts.first { $0.string.contains("有序二") }!
        drag(apple, 4, foxtrot, 7)
        precondition(group.selectedText.hasPrefix("Apple\n•\t第二项"))
        precondition(group.selectedText.hasSuffix("2.\t有序二 Fox"))
        group.clear()
        print("Continuous selection passed: forward/reverse native drags, nested and numbered lists, partial endpoints, quote payload, select-all, blank cancellation and capsule radius")
    }

    /// Exercise native cursor routing with a button overlapping NSTextView and a non-key menu.
    static func actionCursorPreview() async throws {
        let originalPointer = NSEvent.mouseLocation
        func movePointer(_ point: NSPoint) {
            let screenHeight = NSScreen.screens[0].frame.maxY
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: point.x, y: screenHeight - point.y), mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        func descendants(_ node: NSView) -> [NSView] { [node] + node.subviews.flatMap(descendants) }
        let window = NSWindow(contentRect: NSRect(x: 160, y: 200, width: 600, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        var quotes = 0
        var clicks = 0
        window.contentView = NSHostingView(rootView:
            ChatInlineText(markdown: String(repeating: "可选择的正文 Alpha Beta Gamma ", count: 8), literal: true)
                .environment(\.chatQuoteAction, { _ in quotes += 1 })
                .overlay {
                    Button { clicks += 1 } label: {
                        Image(systemName: "arrow.down").frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .glassPointerFeedback(pressed: false, in: Circle())
                }
                .frame(width: 560, height: 260).clipped().padding(20))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); movePointer(originalPointer) }
        try await Task.sleep(for: .milliseconds(600))
        let text = descendants(window.contentView!).compactMap { $0 as? ChatSelectableTextView }.first!
        let textPoint = window.convertPoint(toScreen: text.convert(NSPoint(x: 30, y: 10), to: nil))
        let buttonPoint = window.convertPoint(toScreen: NSPoint(x: 300, y: 150))
        movePointer(window.convertPoint(toScreen: NSPoint(x: 5, y: 5)))
        try await Task.sleep(for: .milliseconds(200))
        precondition(text.visibleRect.contains(NSPoint(x: 30, y: 10)), "Cursor probe must target visible text")
        for _ in 0..<3 {
            movePointer(textPoint)
            try await Task.sleep(for: .milliseconds(150))
            precondition(NSCursor.current == .iBeam, "Selectable body must retain the I-beam")
            movePointer(buttonPoint)
            try await Task.sleep(for: .milliseconds(150))
            precondition(NSCursor.current == .arrow, "An action overlapping body text must show the arrow")
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 300, y: 150), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            NSApp.sendEvent(event)
        }
        precondition(clicks == 1, "Cursor ownership must preserve button clicks")
        movePointer(textPoint)
        try await Task.sleep(for: .milliseconds(150))
        precondition(NSCursor.current == .iBeam)
        window.makeFirstResponder(text)
        text.setSelectedRange(NSRange(location: 0, length: 12))
        text.showSelectionMenu()
        try await Task.sleep(for: .milliseconds(200))
        let menu = window.childWindows!.first { $0 is SurfacePanel && $0.isVisible }!
        precondition(!menu.isKeyWindow)
        for fraction in [0.20, 0.70] {
            movePointer(menu.convertPoint(toScreen: NSPoint(x: menu.frame.width * fraction, y: menu.frame.height / 2)))
            try await Task.sleep(for: .milliseconds(150))
            precondition(NSCursor.current == .arrow, "Both floating selection actions must show the arrow")
        }
        movePointer(textPoint)
        try await Task.sleep(for: .milliseconds(150))
        precondition(NSCursor.current == .iBeam, "Leaving the action must restore the body cursor")
        precondition(quotes == 0 && text.selectedRange().length == 12, "Hover must preserve selection without invoking actions")
        menu.orderOut(nil)
        window.contentView = NSHostingView(rootView: ChatMarkdownView(
            text: "这是可选择的正文 [来源](https://example.com/kimi)")
            .padding(24).frame(width: 600, height: 300, alignment: .topLeading))
        try await Task.sleep(for: .milliseconds(400))
        let sourceText = descendants(window.contentView!).compactMap { $0 as? ChatSourceTextView }.first!
        var sourceIndex = 0
        sourceText.textStorage!.enumerateAttribute(.chatSources,
            in: NSRange(location: 0, length: sourceText.textStorage!.length)) { value, range, _ in
            if value != nil { sourceIndex = range.location }
        }
        let anchor = sourceText.sourceAnchor(at: sourceIndex)!
        let bodyPoint = window.convertPoint(toScreen: sourceText.convert(NSPoint(x: 8, y: 8), to: nil))
        for _ in 0..<3 {
            movePointer(bodyPoint)
            try await Task.sleep(for: .milliseconds(150))
            precondition(NSCursor.current == .iBeam, "Body beside source tag retains text cursor")
            movePointer(NSPoint(x: anchor.midX, y: anchor.midY))
            try await Task.sleep(for: .milliseconds(150))
            precondition(NSCursor.current == .arrow, "Source tag must show arrow through native event dispatch")
        }
        try await Task.sleep(for: .milliseconds(350))
        let card = sourceText.preview!.panel
        precondition(card.isVisible && card.frame.width == 300, "Source hover opens compact card")
        movePointer(card.convertPoint(toScreen: NSPoint(x: 24, y: card.frame.height / 2)))
        try await Task.sleep(for: .milliseconds(150))
        precondition(NSCursor.current == .arrow, "Source card row must retain the action cursor")
        movePointer(bodyPoint)
        try await Task.sleep(for: .milliseconds(150))
        precondition(NSCursor.current == .iBeam, "Leaving source card restores text cursor")
        sourceText.preview?.close()
        print("Action cursor passed: overlays, selection actions, source tags/cards and return to text")
    }

    /// Check synchronous cursor updates, not only the settled cursor after a run-loop delay.
    static func headerCursorPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-header-cursor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Header cursor")
        try store.append(conversationID: cid, role: "user", text: "顶部光标回归")
        try store.append(conversationID: cid, role: "assistant",
            text: String(repeating: "这段正文需要滚动到顶部拖动区域下方，鼠标移动时仍应保持箭头。\n\n", count: 30))
        let model = AgentModel(app: app)
        model.open(cid)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApp.windows.first { $0.title == "Asky AI" }!
        defer { window.orderOut(nil) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        try await Task.sleep(for: .milliseconds(600))
        let content = window.contentView!
        let scroll = descendants(content).compactMap { $0 as? NSScrollView }.first {
            ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 300
        }!
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.minY + 180))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(250))
        content.layoutSubtreeIfNeeded()
        let headerRect = NSRect(x: 90, y: window.frame.height - 60, width: 300, height: 48)
        let texts = descendants(content).compactMap { $0 as? ChatSelectableTextView }
        guard let text = texts.first(where: { $0.convert($0.visibleRect, to: nil).intersects(headerRect) }) else {
            preconditionFailure("Fixture must have selectable text underneath the real chat header")
        }
        let overlap = text.convert(text.visibleRect, to: nil).intersection(headerRect)
        for step in 0..<120 {
            let point = NSPoint(x: overlap.minX + overlap.width * (CGFloat(step % 20) + 0.5) / 20,
                                y: overlap.midY)
            let cursorEvent = NSEvent.enterExitEvent(with: .cursorUpdate, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: step, trackingNumber: 0, userData: nil)!
            let moveEvent = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: step, clickCount: 0, pressure: 0)!
            NSCursor.arrow.set()
            text.cursorUpdate(with: cursorEvent)
            precondition(NSCursor.current == .arrow, "Covered text must never transiently set the I-beam in cursorUpdate")
            text.mouseMoved(with: moveEvent)
            precondition(NSCursor.current == .arrow, "Covered text must never transiently set the I-beam in mouseMoved")
        }
        let bodyRect = NSRect(x: 90, y: 200, width: 300, height: window.frame.height - 280)
        let body = texts.first { $0.convert($0.visibleRect, to: nil).intersects(bodyRect) }!
        let bodyOverlap = body.convert(body.visibleRect, to: nil).intersection(bodyRect)
        let bodyEvent = NSEvent.enterExitEvent(with: .cursorUpdate,
            location: NSPoint(x: bodyOverlap.midX, y: bodyOverlap.midY), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        body.cursorUpdate(with: bodyEvent)
        precondition(NSCursor.current == .iBeam, "Uncovered body must retain its native text cursor")
        print("Header cursor passed: 120 synchronous cursor/move pairs over real scrolled chat text, return to body")
    }

    static func headerDragRegression() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-header-drag-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "Header drag")
        try store.append(conversationID: cid, role: "user", text: "顶部拖动测试")
        try store.append(conversationID: cid, role: "assistant",
            text: String(repeating: "顶部拖动区域下方的对话正文，用于验证点击顶部区域时命中拖动视图而不是滚动内容。\n\n", count: 20))
        let model = AgentModel(app: app)
        model.open(cid)
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
        let window = NSApp.windows.first { $0.title == "Asky AI" }!
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(600))
        let content = window.contentView!
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        if let scroll = descendants(content).compactMap({ $0 as? NSScrollView }).first(where: {
            ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 200
        }) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.minY + 160))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(200))
        }
        content.layoutSubtreeIfNeeded()
        for x in [120.0, Double(content.bounds.midX), Double(content.bounds.width - 140)] {
            let point = NSPoint(x: x, y: content.bounds.height - 28)
            let hit = content.hitTest(point)
            precondition(hit.map { String(describing: type(of: $0)).contains("DragView") } == true,
                         "Header point \(point) must hit WindowDragArea.DragView in non-empty conversation, got: \(String(describing: hit))")
        }
        let buttons = descendants(content).compactMap { $0 as? NSButton }.filter {
            !$0.isHiddenOrHasHiddenAncestor && $0.convert($0.bounds, to: nil).minY > content.bounds.height - 64
        }
        precondition(buttons.count >= 2, "Header toolbar buttons must remain mounted")
        for button in buttons {
            let rect = button.convert(button.bounds, to: nil)
            let hit = content.hitTest(NSPoint(x: rect.midX, y: rect.midY))
            precondition(hit === button || hit?.isDescendant(of: button) == true,
                         "Header toolbar button must remain clickable above DragView, got: \(String(describing: hit))")
        }
        let bodyPoint = NSPoint(x: content.bounds.midX, y: content.bounds.midY)
        let bodyHit = content.hitTest(bodyPoint)
        precondition(bodyHit.map { !String(describing: type(of: $0)).contains("DragView") } == true,
                     "Body transcript below header must not be covered by DragView, got: \(String(describing: bodyHit))")
        // Also verify empty conversation header dragging.
        let emptyRoot = FileManager.default.temporaryDirectory.appending(path: "Asky-header-drag-empty-\(UUID())")
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let emptyApp = try AppModel(root: emptyRoot)
        let emptyModel = AgentModel(app: emptyApp)
        let emptyController = AgentWindowController(model: emptyModel, presentation: WindowPresentation())
        emptyController.show()
        let emptyWindow = NSApp.windows.last { $0.title == "Asky AI" && $0 !== window }!
        defer { emptyWindow.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(350))
        let emptyContent = emptyWindow.contentView!
        emptyContent.layoutSubtreeIfNeeded()
        let emptyTopCenter = NSPoint(x: emptyContent.bounds.midX, y: emptyContent.bounds.height - 28)
        let emptyHit = emptyContent.hitTest(emptyTopCenter)
        precondition(emptyHit.map { String(describing: type(of: $0)).contains("DragView") } == true,
                     "Header top-center must hit WindowDragArea.DragView in empty conversation, got: \(String(describing: emptyHit))")
        print("Header drag passed: non-empty scrolled header, toolbar buttons, body transcript, and empty conversation header")
    }

    static func windowPresentationRegression() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-window-presentation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        defer { application.appearance = originalAppearance }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            application.appearance = NSAppearance(named: appearance)
            let presentation = WindowPresentation()
            let controller = AgentWindowController(model: AgentModel(app: app), presentation: presentation)
            application.deactivate()
            try await Task.sleep(for: .milliseconds(150))
            precondition(!application.isActive, "Exercise opening from an inactive accessory app")
            controller.show()
            let window = application.windows.first { $0.title == "Asky AI" }!
            window.title = "Chat presentation \(appearance.rawValue)"
            precondition(!window.isVisible || window.alphaValue == 0,
                "Chat must stay visually hidden until activation, without a dim first frame")
            let observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    precondition(application.isActive, "Chat must become key in the active app")
                    precondition(!window.isVisible || window.alphaValue == 0,
                        "Chat must acquire key appearance before revealing its glass")
                }
            }
            defer { NotificationCenter.default.removeObserver(observer); window.close() }
            for _ in 0..<50 {
                if window.isVisible && window.isKeyWindow { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            precondition(window.isVisible && window.isKeyWindow && application.isActive)
            precondition(window.alphaValue == 1, "Activation must reveal the prepared surface")
            precondition(window.animationBehavior == .none && window.level == .normal)
            precondition(window.contentView!.bounds.size == window.frame.size)
            window.close()
            controller.show()
            precondition(window.isVisible && window.isKeyWindow, "Reopening in the active app must be immediate")
            controller.show()
            precondition(window.isVisible && window.isKeyWindow, "Repeated show must retain focus")
            window.close()

            // Hold activation pending deterministically; a real activation can
            // complete synchronously on subsequent shows in the same process.
            application.setActivationPolicy(.prohibited)
            application.deactivate()
            try await Task.sleep(for: .milliseconds(150))
            controller.show()
            presentation.yieldToAuthentication()
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: application)
            precondition(!window.isVisible, "Cancelled activation must not reveal chat over authentication")
            precondition(window.alphaValue == 1, "Cancellation must restore the original alpha")
            controller.show()
            window.close()
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: application)
            precondition(!window.isVisible, "Closing a pending window must cancel its presentation")
            precondition(window.alphaValue == 1)
            application.setActivationPolicy(.accessory)
        }
        print("Chat presentation passed: inactive first show, key before visibility, light/dark, reopen, repeated show, authentication and close cancellation")
    }

    static func firstOpenStabilityRegression() async throws {
        func buildStore(at root: URL, longLastReply: Bool, richMarkdown: Bool) throws -> AppModel {
            let app = try AppModel(root: root)
            let store = ConversationStore(app.store)
            let cid = try store.create(title: "First open stability")
            for i in 1...22 {
                try store.append(conversationID: cid, role: "user", text: "第 \(i) 个问题：请帮我总结一下今天的工作重点和下一步安排。")
                if richMarkdown {
                    try store.append(conversationID: cid, role: "assistant", text: """
                    这是第 \(i) 条回复，包含多行内容、表格、公式与代码块：

                    - 第一项：完成核心功能开发与自测
                    - 第二项：整理回归测试与性能基线
                    - 第三项：准备发布说明和安装包

                    | 模块 | 状态 | 备注 |
                    | --- | --- | --- |
                    | 启动器 | 完成 | 延迟 12ms |
                    | 对话流 | 验证中 | 含 `code_snippet_\(i)()` |

                    ```swift
                    func step_\(i)(_ x: Int) -> Int {
                        return x * \(i) + 1
                    }
                    ```

                    $$\\int_0^1 x^2 dx = \\frac{1}{3}$$
                    """)
                } else {
                    try store.append(conversationID: cid, role: "assistant", text: """
                    这是第 \(i) 条回复，包含多行内容与列表：

                    - 第一项：完成核心功能开发与自测
                    - 第二项：整理回归测试与性能基线
                    - 第三项：准备发布说明和安装包

                    `code_snippet_\(i)()` 已经验证通过。
                    """)
                }
            }
            if longLastReply {
                try store.append(conversationID: cid, role: "user", text: "请给出一份完整的架构梳理和迁移清单。")
                let longAnswer = (1...16).map { idx in
                    """
                    ### 第 \(idx) 部分：状态与滚动稳定性

                    这里详细描述了第 \(idx) 个阶段的设计原则、边界条件与回归测试覆盖范围，确保打开窗口时不会出现跳动。

                    | 检查项 | 预期 |
                    | --- | --- |
                    | 阶段 \(idx) | 首帧即对齐 |
                    """
                }.joined(separator: "\n\n")
                try store.append(conversationID: cid, role: "assistant", text: longAnswer)
            } else {
                try store.append(conversationID: cid, role: "user", text: "最后一条短问题？")
                try store.append(conversationID: cid, role: "assistant", text: "这是一条简短的最终回复，用于验证首次打开时底部对齐。")
            }
            return app
        }

        let application = NSApplication.shared

        func assertStableFirstOpen(label: String, app: AppModel, activeBeforeShow: Bool, expectsReplyTop: Bool) async throws -> [String] {
            let presentation = WindowPresentation()
            let controller = AgentWindowController(model: AgentModel(app: app), presentation: presentation)
            if activeBeforeShow {
                application.activate(ignoringOtherApps: true)
                for _ in 0..<50 where !application.isActive {
                    try await Task.sleep(for: .milliseconds(10))
                }
            } else {
                application.deactivate()
                try await Task.sleep(for: .milliseconds(150))
            }
            controller.show()
            let window = application.windows.first { $0.title == "Asky AI" }!
            window.title = "First open \(label) \(activeBeforeShow ? "active" : "inactive")"
            defer { window.close() }

            if !activeBeforeShow {
                for _ in 0..<80 {
                    if window.isVisible && window.isKeyWindow && window.alphaValue == 1 { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            precondition(window.isVisible && window.isKeyWindow && window.alphaValue == 1, "Window must become visible and key")

            func findTranscriptScroll(_ view: NSView) -> NSScrollView? {
                if let s = view as? NSScrollView, s.contentSize.height > 200 { return s }
                for sub in view.subviews {
                    if let found = findTranscriptScroll(sub) { return found }
                }
                return nil
            }

            func findLastReplyMarker(_ view: NSView, id: String) -> NSView? {
                if view.identifier?.rawValue == "transcript-reply-" + id { return view }
                for sub in view.subviews {
                    if let found = findLastReplyMarker(sub, id: id) { return found }
                }
                return nil
            }

            let scroll = findTranscriptScroll(window.contentView!)
            let lastAssistantID = controller.model.items.last(where: { $0.kind == .assistant })?.id ?? ""

            func sample() -> (scrollY: CGFloat, bottomY: CGFloat, docH: CGFloat, markerScreenY: CGFloat?, replyClipMinY: CGFloat?) {
                let sy = scroll?.contentView.bounds.minY ?? -1
                let dh = scroll?.documentView?.bounds.height ?? -1
                let vh = scroll?.contentView.bounds.height ?? 0
                let by = max(0, dh - vh)
                let marker = findLastReplyMarker(window.contentView!, id: lastAssistantID)
                let my = marker.map { window.contentView!.convert($0.bounds, from: $0).minY }
                let rc = marker.flatMap { m in scroll.map { $0.contentView.convert(m.bounds, from: m).minY - $0.contentView.bounds.minY } }
                return (sy, by, dh, my, rc)
            }

            let first = sample()
            var maxMarkerDrift: CGFloat = 0
            var minMarkerY = first.markerScreenY ?? .greatestFiniteMagnitude
            var maxMarkerY = first.markerScreenY ?? -.greatestFiniteMagnitude
            let baselineY = first.markerScreenY
            var changes: [String] = [String(format: "t=0 sy=%.1f by=%.1f dh=%.1f my=%@ rc=%@", first.scrollY, first.bottomY, first.docH, first.markerScreenY.map { String(format: "%.1f", $0) } ?? "nil", first.replyClipMinY.map { String(format: "%.1f", $0) } ?? "nil")]
            var prev = first

            for frame in 1...40 {
                try await Task.sleep(for: .milliseconds(16))
                let s = sample()
                if let my = s.markerScreenY, let base = baselineY {
                    maxMarkerDrift = max(maxMarkerDrift, abs(my - base))
                    minMarkerY = min(minMarkerY, my)
                    maxMarkerY = max(maxMarkerY, my)
                }
                if abs(s.scrollY - prev.scrollY) > 0.5 || abs(s.docH - prev.docH) > 0.5 || abs((s.markerScreenY ?? -999) - (prev.markerScreenY ?? -999)) > 0.5 {
                    changes.append(String(format: "t=%d sy=%.1f by=%.1f dh=%.1f my=%@ rc=%@", frame * 16, s.scrollY, s.bottomY, s.docH, s.markerScreenY.map { String(format: "%.1f", $0) } ?? "nil", s.replyClipMinY.map { String(format: "%.1f", $0) } ?? "nil"))
                    prev = s
                }
            }
            print("FIRST-OPEN [\(label) active=\(activeBeforeShow)]: drift=\(String(format: "%.1f", maxMarkerDrift)) changes=\(changes.joined(separator: " | "))")
            var failures: [String] = []
            if baselineY == nil {
                failures.append("Last reply marker must already be mounted on first visible frame (\(label), active=\(activeBeforeShow))")
            }
            if expectsReplyTop {
                let firstTopGap = abs((first.replyClipMinY ?? -999) - 90)
                if firstTopGap > 2 {
                    failures.append("First visible frame for long reply must already align to reply top (\(label), active=\(activeBeforeShow), gap=\(firstTopGap))")
                }
            } else {
                let gapAtReveal = abs(first.scrollY - first.bottomY)
                if gapAtReveal > 2 {
                    failures.append("First visible frame must already be aligned to bottom (\(label), active=\(activeBeforeShow), gap=\(gapAtReveal))")
                }
            }
            if maxMarkerDrift > 2 {
                failures.append("Visible reply must not jitter after first reveal (\(label), active=\(activeBeforeShow), drift=\(maxMarkerDrift))")
            }
            return failures
        }

        let shortRoot = FileManager.default.temporaryDirectory.appending(path: "Asky-first-open-short-\(UUID())")
        let longRoot = FileManager.default.temporaryDirectory.appending(path: "Asky-first-open-long-\(UUID())")
        defer {
            try? FileManager.default.removeItem(at: shortRoot)
            try? FileManager.default.removeItem(at: longRoot)
        }
        let shortRich = try buildStore(at: shortRoot, longLastReply: false, richMarkdown: true)
        let longRich = try buildStore(at: longRoot, longLastReply: true, richMarkdown: true)
        var allFailures: [String] = []
        allFailures += try await assertStableFirstOpen(label: "short-rich", app: shortRich, activeBeforeShow: false, expectsReplyTop: false)
        allFailures += try await assertStableFirstOpen(label: "short-rich", app: shortRich, activeBeforeShow: true, expectsReplyTop: false)
        allFailures += try await assertStableFirstOpen(label: "long-rich", app: longRich, activeBeforeShow: false, expectsReplyTop: true)
        allFailures += try await assertStableFirstOpen(label: "long-rich", app: longRich, activeBeforeShow: true, expectsReplyTop: true)
        precondition(allFailures.isEmpty, allFailures.joined(separator: "\n"))
        print("First open stability passed: short-rich and long-rich (inactive and active) aligned with 0 drift")
    }

    static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--window-presentation") || CommandLine.arguments.contains("--first-open-stability") || CommandLine.arguments.contains("--header-cursor-preview") || CommandLine.arguments.contains("--header-drag") || CommandLine.arguments.contains("--action-cursor-preview") || CommandLine.arguments.contains("--user-bubble-hover") || CommandLine.arguments.contains("--approval-menu-hover") {
            var completed = false
            Task { @MainActor in
                do {
                    if CommandLine.arguments.contains("--window-presentation") { try await windowPresentationRegression() }
                    else if CommandLine.arguments.contains("--first-open-stability") { try await firstOpenStabilityRegression() }
                    else if CommandLine.arguments.contains("--header-cursor-preview") { try await headerCursorPreview() }
                    else if CommandLine.arguments.contains("--header-drag") { try await headerDragRegression() }
                    else if CommandLine.arguments.contains("--action-cursor-preview") { try await actionCursorPreview() }
                    else if CommandLine.arguments.contains("--approval-menu-hover") { try await approvalMenuHoverRegression() }
                    else { try await userBubbleHoverRegression() }
                } catch { preconditionFailure("Header/hover regression failed: \(error)") }
                completed = true
                application.stop(nil)
                application.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    subtype: 0, data1: 0, data2: 0)!, atStart: true)
            }
            application.run()
            precondition(completed)
            return
        }
        if CommandLine.arguments.contains("--continuous-selection-preview") {
            // Native mouse tracking changes run-loop modes; keep a real AppKit loop alive.
            var completed = false
            Task { @MainActor in
                do { try await continuousSelectionPreview() }
                catch { preconditionFailure("Continuous selection regression failed: \(error)") }
                completed = true
                application.stop(nil)
                application.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    subtype: 0, data1: 0, data2: 0)!, atStart: true)
            }
            application.run()
            precondition(completed, "Native selection regression must run to completion")
            return
        }
        if CommandLine.arguments.contains("--sources-preview") {
            try await sourcesPreview()
            return
        }
        if CommandLine.arguments.contains("--math-preview") {
            try await mathPreview()
            return
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-reply-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        if CommandLine.arguments.contains("--bubble-width-preview") {
            try await bubbleWidthPreview(app: app)
            return
        }
        if CommandLine.arguments.contains("--table-fade-preview") {
            try await tableFadePreview(app: app)
            return
        }
        try await reactionRegression(app: app, capture: CommandLine.arguments.contains("--reactions-preview"))
        if CommandLine.arguments.contains("--reactions-preview") { return }
        if CommandLine.arguments.contains("--avatar-preview") {
            let legacy = try JSONDecoder().decode(SettingsPreferences.self, from: Data(#"{"agentAvatarColor":"yellow","showDockIcon":true}"#.utf8))
            precondition(legacy.agentAvatarShape == "monster" && legacy.agentAvatarExpression == "smile")
            precondition(legacy.agentAvatarColor == "yellow" && legacy.showDockIcon)
            let model = AgentModel(app: app)
            app.preferences.agentAvatarColor = "pink"
            precondition(model.avatarColor == .pink)
            app.preferences.agentAvatarColor = "green"
            precondition(model.avatarColor == .green)
            model.avatarShape = .ghost
            model.avatarExpression = .sunglasses
            model.avatarColor = .yellow
            let saved = app.store.codableSetting(SettingsPreferences.key, as: SettingsPreferences.self)!
            precondition(saved.agentAvatarShape == "ghost" && saved.agentAvatarExpression == "sunglasses" && saved.agentAvatarColor == "yellow")
            let reopened = try AppModel(root: root)
            let restored = AgentModel(app: reopened)
            precondition(restored.avatarShape == .ghost && restored.avatarExpression == .sunglasses && restored.avatarColor == .yellow)
            model.avatarShape = .monster
            model.avatarExpression = .smile
            model.avatarColor = .blue
            print("Avatar preferences passed: old settings, legacy colors, independent choices and disk reload")
            let controller = AgentWindowController(model: model, presentation: WindowPresentation())
            controller.show()
            runPreview(controller, application: application)
            return
        }
        if CommandLine.arguments.contains("--selection-preview") {
            try await selectionPreview(app: app)
            return
        }
        if CommandLine.arguments.contains("--reply-navigation") {
            try await replyNavigationRegression(app: app)
            return
        }
        if CommandLine.arguments.contains("--paging") {
            try pagingRegression(app: app)
            return
        }
        if CommandLine.arguments.contains("--scroll-stability") {
            try await scrollStabilityRegression(app: app)
            return
        }
        if CommandLine.arguments.contains("--send-stability") {
            try await sendStabilityRegression(app: app)
            return
        }
        if CommandLine.arguments.contains("--scroll-perf") {
            try await scrollPerfRegression(app: app)
            return
        }
        if CommandLine.arguments.contains("--restored-transcript") {
            try await restoredTranscriptRegression(app: app)
            return
        }
        if CommandLine.arguments.contains("--latex-form-preview") {
            try await latexFormPreview(app: app)
            return
        }
        if CommandLine.arguments.contains("--prefill-preview") {
            try await formPrefillRegression(app: app)
            return
        }
        try await formLifecycleRegression(app: app)
        let model = AgentModel(app: app)
        if CommandLine.arguments.contains("--bottom-push") {
            try await bottomPushRegression(app: app)
            return
        }
        if CommandLine.arguments.contains("--reading-scroll") {
            try await readingScrollRegression(app: app)
            return
        }
        try await toolRepliesRegression(app: app, capture: CommandLine.arguments.contains("--reply-activity-preview"))
        if CommandLine.arguments.contains("--reply-activity-preview") { return }
        try historyRegression(app: app)
        if CommandLine.arguments.contains("--forms-preview") {
            try await formPreview(app: app, model: model)
            return
        }
        if CommandLine.arguments.contains("--macos14-checks") {
            precondition(SurfaceCompatibility.useMacOS14Compatibility)
            precondition(SurfaceCompatibility.useLegacyMaterial)
            let id = try ConversationStore(app.store).create(title: "Compatibility regression")
            for index in 0..<24 {
                try ConversationStore(app.store).append(conversationID: id,
                    role: index.isMultiple(of: 2) ? "user" : "assistant",
                    text: "Message \(index): transcript scrolling compatibility")
            }
            model.open(id)
            let controller = AgentWindowController(model: model, presentation: WindowPresentation())
            controller.show()
            let window = application.windows.first { $0.title == "Asky AI" }!
            defer { window.close() }
            func descendants(_ view: NSView) -> [NSView] {
                [view] + view.subviews.flatMap { descendants($0) }
            }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(350))
                guard let view = window.contentView else { fatalError("missing chat surface") }
                view.layoutSubtreeIfNeeded()
                let views = descendants(view)
                precondition(views.contains { $0 is NSVisualEffectView }, "legacy chat must retain native blur")
                precondition(views.contains { String(describing: type(of: $0)).contains("DragView") },
                             "legacy chat header must retain a native window drag area")
                guard let scroll = views.compactMap({ $0 as? NSScrollView }).first(where: {
                    ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height
                }) else { fatalError("legacy transcript must remain scrollable") }
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
                try await Task.sleep(for: .milliseconds(200))
                view.layoutSubtreeIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(
                        to: URL(filePath: "build/macos14-chat-\(appearance.rawValue).png"))
                }
            }
            print("macOS 14 branch: chat blur, native drag area, scrollable transcript and light/dark captures passed")
            return
        }
        if #available(macOS 26, *), CommandLine.arguments.contains("--window-glass") {
            func capture(_ window: NSWindow, name: String) throws {
                let frame = window.frame
                let top = NSScreen.screens[0].frame.maxY - frame.maxY
                let capture = Process()
                capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-R", "\(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))",
                    "build/\(name).png"]
                try capture.run()
                capture.waitUntilExit()
                precondition(capture.terminationStatus == 0)
            }
            let controller = AgentWindowController(model: model, presentation: WindowPresentation())
            controller.show()
            let window = application.windows.first { $0.title == "Asky AI" }!
            defer { window.close() }
            guard let glass = window.contentView as? GlassSurfaceView else {
                preconditionFailure("chat must use the search shell's AppKit glass")
            }
            precondition(glass.style == .regular && glass.tintColor == nil && window.hasShadow)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                for (name, size) in [("initial", window.frame.size), ("resized", NSSize(width: 820, height: 720))] {
                    window.setContentSize(size)
                    window.contentView!.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(350))
                    precondition(glass.frame.size == size, "glass must fill the resized window")
                    precondition(glass.contentView?.frame.size == size, "content wrapper must resize with glass")
                    try capture(window, name: "agent-window-glass-\(appearance.rawValue)-\(name)")
                }
            }
            window.orderOut(nil)
            try ClipboardStore(app.store).insert(ClipboardItem(kind: .text,
                text: "原生玻璃列表背景验证", byteSize: 33, contentHash: "window-glass-fixture"))
            let clipboard = ClipboardController(app: app)
            clipboard.pinned = true
            clipboard.show()
            let list = application.windows.first { $0.title == NSLocalizedString("剪贴板历史", comment: "") }!
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                list.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(400))
                guard let surface = list.contentView as? GlassSurfaceView else {
                    preconditionFailure("clipboard must share the native window glass")
                }
                precondition(surface.style == .regular && surface.tintColor == nil)
                try capture(list, name: "clipboard-window-glass-\(appearance.rawValue)")
            }
            clipboard.hide()
            print("Chat native Regular glass, untinted surface, light/dark capture and resizing passed")
            return
        }
        if CommandLine.arguments.contains("--compaction-preview") {
            let store = ConversationStore(app.store)
            let cid = try store.create(title: "上下文压缩")
            try store.append(conversationID: cid, role: "user", text: "继续刚才的对话")
            model.open(cid)
            model.beginResponse(taskID: "compaction")
            model.handle(.taskState(taskID: "compaction", .compacting), conversationID: cid)
            precondition(model.state == .compacting && model.isRunning)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                application.appearance = NSAppearance(named: appearance)
                let controller = AgentWindowController(model: model, presentation: WindowPresentation())
                controller.show()
                let window = application.windows.first { $0.title == "Asky AI" }!
                defer { window.close() }
                window.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(600))
                let capture = Process()
                capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String(window.windowNumber),
                    "build/agent-compaction-\(appearance.rawValue).png"]
                try capture.run()
                capture.waitUntilExit()
                precondition(capture.terminationStatus == 0)
            }
            model.handle(.taskState(taskID: "compaction", .running), conversationID: cid)
            precondition(model.state == .running && model.isRunning)
            model.handle(.taskState(taskID: "compaction", .compacting), conversationID: cid)
            model.handle(.taskState(taskID: "compaction", .cancelled), conversationID: cid)
            model.finishTask(conversationID: cid)
            precondition(!model.isRunning && model.state == .cancelled)
            print("Compaction UI: light/dark captures, resume and cancellation passed")
            return
        }
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "回复回归")
        model.open(cid)
        model.beginResponse(taskID: "clarification", now: Date().addingTimeInterval(-13))
        model.handle(.textDelta(taskID: "clarification", "之前的流式说明"), conversationID: cid)
        model.handle(.clarification(taskID: "clarification", question: "「年后啊」这句我没接上上下文，能补充一下你的意思吗？"), conversationID: cid)
        model.handle(.taskState(taskID: "clarification", .awaitingInput), conversationID: cid)
        let completedAt = Date()
        model.finishTask(conversationID: cid, now: completedAt)
        precondition(model.items[0].completedAt == completedAt)
        precondition(model.items[0].responseID == "clarification")
        precondition(model.items.count == 1, "clarification must have only one reply/copy button")
        precondition(model.items[0].workSeconds == 13, "finished reply retains elapsed time")
        precondition(store.messages(conversationID: cid, limit: 40).count == 1)
        model.open(cid)
        precondition(model.items.count == 1, "clarification must survive reopening")
        model.beginResponse(taskID: "normal")
        model.handle(.textDelta(taskID: "normal", "增量"), conversationID: cid)
        model.handle(.message(taskID: "normal", "完整回答"), conversationID: cid)
        model.finishTask(conversationID: cid)
        precondition(model.items.count == 2 && model.items.last?.text == "完整回答")
        precondition(model.items.last?.workSeconds != nil)
        model.beginResponse(taskID: "stopped")
        model.handle(.textDelta(taskID: "stopped", "停止时保留的部分回答"), conversationID: cid)
        model.handle(.taskState(taskID: "stopped", .cancelled), conversationID: cid)
        model.finishTask(conversationID: cid)
        precondition(model.items.count == 3 && model.items.last?.kind == .notice && model.items.last?.text == NSLocalizedString("已停止", comment: ""))
        precondition(model.taskStartedAt == nil && !model.isRunning)
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        for (age, key, value) in [(0, "刚刚", 0), (59, "刚刚", 0), (60, "%d 分钟前", 1),
                                  (3599, "%d 分钟前", 59), (3600, "%d 小时前", 1),
                                  (86399, "%d 小时前", 23), (86400, "%d 天前", 1),
                                  (259199, "%d 天前", 2)] {
            let expected = value == 0 ? NSLocalizedString(key, comment: "") : String(format: NSLocalizedString(key, comment: ""), value)
            precondition(ChatCompletionTime.label(clock.addingTimeInterval(-Double(age)), now: clock) == expected)
        }
        precondition(ChatCompletionTime.label(clock.addingTimeInterval(-259200), now: clock) == ChatCompletionTime.exact(clock.addingTimeInterval(-259200)))
        precondition(ChatCompletionTime.label(clock.addingTimeInterval(1), now: clock) == NSLocalizedString("刚刚", comment: ""))
        print("Completion time regression passed: minute, hour, day, three-day boundaries and clock skew")
        print("AgentReply regression passed: clarification, persisted question, final reply, cancellation, elapsed time")
        let attachmentID = try store.create(title: "附件消息回归")
        let file = root.appending(path: "PRD-Spotlight.md")
        try Data("附件回归".utf8).write(to: file)
        let document = try ComposerAttachmentService.importFile(file, into: app.store.attachmentsDirectory)
        var refs = [document.reference]
        if let index = CommandLine.arguments.firstIndex(of: "--attachment-preview"),
           CommandLine.arguments.indices.contains(index + 1) {
            let image = try ComposerAttachmentService.importFile(URL(filePath: CommandLine.arguments[index + 1]), into: app.store.attachmentsDirectory)
            refs.insert(image.reference, at: 0)
        }
        try store.append(conversationID: attachmentID, role: "user", text: "请分析这些附件", attachments: refs)
        model.open(attachmentID)
        precondition(model.items.first?.attachments == refs, "history must restore message attachments")
        model.open(nil)
        model.open(attachmentID)
        precondition(model.items.first?.attachments == refs, "reopening retains the selected attachment order")
        print("Message attachment regression passed: history restoration and attachment order")
        model.draft = "旧草稿"
        model.attachments = refs
        model.attachmentThumbnails = ["old": Data([1])]
        let revision = model.newConversationRevision
        await model.startNewConversation()
        precondition(model.conversationID == nil && model.items.isEmpty)
        precondition(model.draft.isEmpty && model.attachments.isEmpty && model.attachmentThumbnails.isEmpty)
        precondition(model.state == nil && model.newConversationRevision == revision + 1)
        precondition(!store.messages(conversationID: attachmentID, limit: 40).isEmpty, "new conversation preserves old history")
        print("New conversation regression passed: blank draft, cleared attachments, preserved history")
        let continuous = AgentModel(app: app)
        let timelineID = try store.create(title: "持续对话回归")
        let timelineMessage = try store.append(conversationID: timelineID, role: "user", text: "持续历史搜索标记")
        continuous.resumeTimeline()
        precondition(continuous.conversationID == nil)
        precondition(continuous.items.contains { $0.id == timelineMessage.id })
        precondition(store.search("持续历史搜索标记").contains { $0.id == timelineMessage.id })
        await app.deleteConversationRound(timelineMessage)
        precondition(store.search("持续历史搜索标记").isEmpty)
        precondition(!continuous.items.contains { $0.id == timelineMessage.id })
        print("Continuous timeline regression passed: resume, native search and deletion refresh")

        if CommandLine.arguments.contains("--tool-preview") {
            let toolID = try store.create(title: "工具调用样式")
            model.open(toolID)
            model.beginResponse(taskID: "tools", now: Date().addingTimeInterval(-13))
            for (id, tool, status, error) in [
                ("calendar", "calendar_search_events", ExecutionStatus.completed, Optional<String>.none),
                ("lark", "plugin_lark__help", .failed, "Error: unknown command \"message\" for \"lark-cli\"\n    at run (plugins/lark/index.mjs:21:5)"),
                ("search", "web_search", .completed, nil),
                ("notes", "notes_search", .completed, nil),
                ("reminders", "reminders_list", .completed, nil),
                ("contacts", "contacts_search", .completed, nil),
                ("messages", "messages_search", .completed, nil),
                ("chrome", "chrome_list_tabs", .completed, nil),
                ("shortcuts", "shortcuts_list", .completed, nil),
                ("memory", "memory_read", .completed, nil),
                ("plugin", "plugin_orca__help", .completed, nil),
                ("lark-success", "plugin_lark__help", .completed, nil),
                ("running", "notes_search", nil, nil)
            ] as [(String, String, ExecutionStatus?, String?)] {
                model.handle(.toolCall(taskID: "tools", ActionRequest(requestID: id, tool: tool, arguments: .object([:]), origin: .agent(sessionID: toolID), intent: .explicitRequest)), conversationID: toolID)
                if let status {
                    model.handle(.toolResult(taskID: "tools", ExecutionResult(requestID: id, status: status, error: error.map { ToolError(.invalidArguments, $0) })), conversationID: toolID)
                }
            }
            precondition(NSImage(named: "MingCute-tool") != nil, "plugins must use the bundled tool icon")
            precondition(model.items.filter { $0.pluginID != nil }.allSatisfy { $0.toolSymbol == "tool" },
                         "Orca and Feishu share the same tool icon")
            precondition(model.items.count == 13, "preview must include each tool family and execution state")
            precondition(model.items.first { $0.id == "search" }?.toolSymbol == "magnifyingglass",
                         "web search uses the MingCute search icon")
            precondition(model.items.first { $0.id == "memory" }?.toolSymbol == "brain",
                         "memory calls use the MingCute brain icon")
            precondition(!model.items[0].text.contains("已完成"))
            precondition(!model.items[1].text.contains("Error:"))
            precondition(model.items[1].toolError?.contains("unknown command") == true)
            precondition(model.items[1].pluginID == "lark")
            model.handle(.message(taskID: "tools", "已检查日历与相关工具，飞书调用失败，可展开工作时间查看详情。"), conversationID: toolID)
            if !CommandLine.arguments.contains("--running-preview") { model.finishTask(conversationID: toolID) }
            let controller = AgentWindowController(model: model, presentation: WindowPresentation())
            controller.show()
            runPreview(controller, application: application)
        }
        if CommandLine.arguments.contains("--attachment-preview") {
            model.open(attachmentID)
            let controller = AgentWindowController(model: model, presentation: WindowPresentation())
            controller.show()
            runPreview(controller, application: application)
        }
        if CommandLine.arguments.contains("--scroll-preview") {
            let scrollID = try store.create(title: "回到底部按钮验证")
            for index in 1...24 {
                try store.append(conversationID: scrollID, role: index.isMultiple(of: 2) ? "assistant" : "user",
                                 text: "第 \(index) 条消息：用于检查向上滚动后的回到底部按钮。")
            }
            model.open(scrollID)
            let controller = AgentWindowController(model: model, presentation: WindowPresentation())
            controller.show()
            runPreview(controller, application: application)
        }
        if CommandLine.arguments.contains("--preview") {
            let previewID = try store.create(title: "澄清回复回归")
            model.open(previewID)
            model.beginResponse(taskID: "preview", now: Date().addingTimeInterval(-13))
            model.handle(.textDelta(taskID: "preview", "不应成为第二条回复的文字"), conversationID: previewID)
            model.handle(.clarification(taskID: "preview", question: "「年后啊」这句我没接上上下文，能补充一下你的意思吗？"), conversationID: previewID)
            model.finishTask(conversationID: previewID)
            // Keep the controller alive while inspecting the actual SwiftUI window.
            let controller = AgentWindowController(model: model, presentation: WindowPresentation())
            controller.show()
            runPreview(controller, application: application)
        }
    }
    private static func runPreview(_ controller: AgentWindowController, application: NSApplication) {
        withExtendedLifetime(controller) { application.run() }
    }
}
