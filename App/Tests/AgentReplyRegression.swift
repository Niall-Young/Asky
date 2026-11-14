import AppKit
import AgentHost
import LocalStore
import SwiftUI
import Contracts
import ToolService

@main
@MainActor
enum AgentReplyRegression {
    static func sourcesPreview() async throws {
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
            安全仪表盘可以查看扫描结果、风险和修复进度。[1](https://devin.ai/)

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
                    if sourceText == nil { sourceText = text }
                    var firstSource: Int?
                    storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                        guard value is NSTextAttachment else { return }
                        badges += 1
                        if firstSource == nil { firstSource = range.location }
                        precondition(storage.attribute(.link, at: range.location, effectiveRange: nil) as? URL != nil)
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
                storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
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
            }

        }
        window.orderOut(nil)
        print("Source badges, retained links, list layout and light/dark window captures passed")
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

    static func formPreview(app: AppModel, model: AgentModel) async throws {
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "原生流式表单")
        try store.append(conversationID: cid, role: "user", text: "帮我安排会议，先让我选择时间和议题。")
        model.open(cid)
        let prefix = "请补充会议信息：\n\n```asky-form\n{\"title\":\"会议安排\"}\n{\"id\":\"title\",\"type\":\"text\",\"label\":\"会议名称\",\"required\":true}\n"
        var rest = """
        {"id":"duration","type":"select","label":"会议时长","options":["30 分钟","60 分钟"],"required":true}
        {"id":"topics","type":"multi","label":"讨论议题","options":["设计方案","开发计划"]}
        {"id":"day","type":"date","label":"会议日期","required":true}
        ```
        """
        let testingRadio = CommandLine.arguments.contains("--radio-preview")
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
        let controller = AgentWindowController(model: model, presentation: WindowPresentation())
        controller.show()
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
        try await Task.sleep(for: .milliseconds(500))
        precondition(ChatFormParser.parse(model.streaming, streaming: true).contains {
            if case .form(let f) = $0.content { f.fields.count == 1 && !f.isComplete } else { false }
        })
        func editableField(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.compactMap { editableField($0) }.first
        }
        // Edit the real native field while the reply is still streaming.
        let streamingField = editableField(window.contentView!)
        if let field = editableField(window.contentView!), window.makeFirstResponder(field), let editor = field.currentEditor() {
            editor.insertText("原生输入回归")
            try await Task.sleep(for: .milliseconds(100))
            precondition(model.formValues["streaming"]?["title"] == ["原生输入回归"])
        } else { preconditionFailure("the streaming form must expose an editable native text field") }
        try capture("streaming")
        model.handle(.textDelta(taskID: "form-stream", rest), conversationID: cid)
        try await Task.sleep(for: .milliseconds(100))
        func popup(_ view: NSView) -> NSPopUpButton? {
            if let button = view as? NSPopUpButton, button.numberOfItems == 3 { return button }
            return view.subviews.compactMap { popup($0) }.first
        }
        let picker = popup(window.contentView!)!
        picker.selectItem(at: 1)
        NSApplication.shared.sendAction(picker.action!, to: picker.target, from: picker)
        precondition(model.formValues["streaming"]?["duration"] == ["30 分钟"], "native popup selection must update the answer")
        model.formValues["streaming"]?["topics"] = ["设计方案"]
        model.formValues["streaming"]?["day"] = ["2026-10-22"]
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
            precondition(model.formValues["streaming"]?["plan"] == ["方案 A"])
            choose(c)
            try await Task.sleep(for: .milliseconds(50))
            precondition(model.formValues["streaming"]?["plan"] == ["方案 C"])
            precondition(a.state == .off && b.state == .off && c.state == .on, "a radio group must keep only one selection")
            choose(later)
            try await Task.sleep(for: .milliseconds(50))
            precondition(c.state == .on && later.state == .on, "separate groups must not clear each other")
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
                precondition(model.formValues["streaming"]?["countdown"] == ["03:30"])
                precondition(model.formValues["streaming"]?["seconds"] == ["30"])
            }
            precondition(model.formValues["streaming"]?["time"] == [testingComponents ? "14:30:45" : "14:30"], "only requested time components must be submitted")
        }
        precondition(!model.submitForm("streaming"), "cannot submit a running response")
        model.handle(.message(taskID: "form-stream", prefix + rest), conversationID: cid)
        let messageID = model.items.last!.id
        precondition(model.formValues[messageID]?["title"] == ["原生输入回归"], "completion must preserve typed input")
        precondition(!model.submitForm(messageID), "wait for task completion before submitting")
        model.finishTask(conversationID: cid)
        try await Task.sleep(for: .milliseconds(150))
        precondition(editableField(window.contentView!) === streamingField, "completion must preserve the native field instance")
        precondition(streamingField?.currentEditor() != nil, "completion must preserve input focus")
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
        let reply = ChatFormParser.form(in: prefix + rest)!.reply(model.formValues[messageID]!)
        app.preferences.automaticUpdates = false
        await app.start()
        precondition(app.agent != nil, "test bundle must locate the actual runtime")
        app.modelConfiguration = ModelConfiguration(baseURL: URL(string: "http://127.0.0.1:1/v1")!,
            modelName: "form-regression", credentialRef: "Asky-form-unset-" + UUID().uuidString)
        model.draft = "保留输入框草稿"
        let attachment = AttachmentRef(id: "draft-only", kind: .file, path: "/draft-only", mimeType: "text/plain", byteSize: 0, temporary: false)
        model.attachments = [attachment]
        precondition(model.submitForm(messageID), "valid form must enter the normal submit path")
        precondition(model.conversationID == cid && model.items.last!.text == reply)
        precondition(model.items.last!.attachments.isEmpty, "form submission must not send composer attachments")
        precondition(model.draft == "保留输入框草稿" && model.attachments == [attachment])
        precondition(!model.submitForm(messageID), "double submission must be rejected")
        for _ in 0..<100 where model.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        precondition(!model.isRunning)
        model.open(cid)
        precondition(!model.formIsActive(messageID) && !model.submitForm(messageID))
        try await Task.sleep(for: .milliseconds(150))
        try capture("field-dark-disabled")
        precondition(model.items.last!.text == reply)
        precondition(ChatFormParser.form(in: model.items[1].text)?.fields.count == (testingTime || testingRadio ? 5 : 4))
        // New session and opening history are native-only; no model calls are needed for rendering.
        await model.startNewConversation()
        precondition(model.formValues.isEmpty)
        await app.shutdown()
        print("Native form UI: early editable field, real native typing, completion transfer, light/dark/narrow captures, history, replay prevention and conversation cleanup passed")
    }

    static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
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
        let model = AgentModel(app: app)
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
        precondition(model.streaming.isEmpty)
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
        precondition(model.items.count == 3 && model.items.last?.workSeconds != nil)
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
        precondition(model.conversationID == nil && model.items.isEmpty && model.streaming.isEmpty)
        precondition(model.draft.isEmpty && model.attachments.isEmpty && model.attachmentThumbnails.isEmpty)
        precondition(model.state == nil && model.newConversationRevision == revision + 1)
        precondition(!store.messages(conversationID: attachmentID, limit: 40).isEmpty, "new conversation preserves old history")
        print("New conversation regression passed: blank draft, cleared attachments, preserved history")
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
