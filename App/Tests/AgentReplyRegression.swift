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
                    if sourceText == nil { sourceText = text }
                    var firstSource: Int?
                    storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                        guard value is NSTextAttachment else { return }
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
                precondition(text.textView(text, clickedOnLink: URL(string: "https://devin.ai/")!, at: linkRange.location),
                             "Clicking a grouped source tag opens its list rather than navigating to the first URL")
                precondition(text.preview?.isShown == true)
                text.preview?.close()
            }

        }
        let many = (0..<12).map { URL(string: "https://example.com/article/\($0)")! }
        let list = NSHostingView(rootView: ScrollView { ChatSourcePreview(sources: many) }.frame(width: 380, height: 460))
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
        precondition(!model.formIsActive(messageID), "a later user message must retire an old form across storage segments")
        model.open(cid)
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
        let submittedCID = model.conversationID!
        precondition(submittedCID != cid && model.items.last!.text == reply, "timeline replies use a fresh storage segment")
        precondition(model.items.last!.attachments.isEmpty, "form submission must not send composer attachments")
        precondition(model.draft == "保留输入框草稿" && model.attachments == [attachment])
        precondition(!model.submitForm(messageID), "double submission must be rejected")
        for _ in 0..<100 where model.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        precondition(!model.isRunning)
        model.resumeTimeline()
        precondition(!model.formIsActive(messageID) && !model.submitForm(messageID))
        try await Task.sleep(for: .milliseconds(150))
        try capture("field-dark-disabled")
        // The intentionally missing credential appends an error after the submitted reply.
        precondition(model.state == .failed, "The test credential must fail without a real model call")
        precondition(model.items.filter { $0.kind == .user && $0.text == reply }.count == 1,
                     "The form reply must survive history exactly once, including when the request fails")
        precondition(ChatFormParser.form(in: model.items.first { $0.id == messageID }!.text)?.fields.count == (testingTime || testingRadio ? 5 : 4))
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
        precondition(scroll.documentView!.bounds.height >= scroll.contentSize.height - 1,
                     "Short chat must fill the viewport so messages rest at its bottom")
        try store.append(conversationID: cid, role: "user", text: "晚上好")
        model.open(cid)
        model.beginResponse(taskID: "bottom-push")
        try await Task.sleep(for: .milliseconds(800))
        try capture("after")
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
        try store.append(conversationID: cid, role: "user", text: "请给我一篇长回答")
        model.open(cid)
        model.beginResponse(taskID: "fast-reply")
        try await Task.sleep(for: .milliseconds(40))
        let answer = String(repeating: "回答应该从开头往下读，首次展示四行，剩余内容向下阅读，完成时不能跳到结尾。", count: 80)
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
        let fourLines = CGFloat(88)
        try capture("completed")
        precondition(abs(visible - fourLines) < 2,
                     "Long replies must reveal the first four lines, not their ending: visible=\(visible), expected=\(fourLines)")
        try capture("completed")
        try store.append(conversationID: cid, role: "user", text: "收到")
        model.open(cid)
        model.beginResponse(taskID: "short-reply")
        try await Task.sleep(for: .milliseconds(40))
        model.handle(.message(taskID: "short-reply", "好的，晚上好。"), conversationID: cid)
        model.handle(.taskState(taskID: "short-reply", .completed), conversationID: cid)
        model.finishTask(conversationID: cid)
        try await Task.sleep(for: .milliseconds(1400))
        let shortReply = replyMarker(window.contentView!)!
        let shortRect = scroll.contentView.convert(shortReply.bounds, from: shortReply)
        precondition(shortRect.height < fourLines, "Short fixture must be fewer than four lines")
        precondition(shortRect.minY >= scroll.contentView.bounds.minY && shortRect.maxY <= scroll.contentView.bounds.maxY,
                     "Replies shorter than four lines must be fully visible")
        try capture("short")
        print("Bottom push passed: short and overflowing chat, new message and waiting bubble, bottom gap=\(gap)")
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
            let point = scroll.convert(NSPoint(x: scroll.bounds.midX,
                y: scroll.isFlipped ? scroll.bounds.maxY - 24 : scroll.bounds.minY + 24), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                window.sendEvent(event)
            }
            try await Task.sleep(for: .milliseconds(700))
            window.contentView!.layoutSubtreeIfNeeded()
            let gap = scroll.documentView!.bounds.maxY - scroll.documentVisibleRect.maxY
            precondition(abs(gap) <= 1, "One button press must reach the actual bottom, including padding: attempt=\(attempt), gap=\(gap), document=\(scroll.documentView!.frame), clip=\(scroll.contentView.bounds), visible=\(scroll.documentVisibleRect)")
            print("One-click bottom: attempt=\(attempt), size=\(size), gap=\(gap)")
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
        if CommandLine.arguments.contains("--latex-form-preview") {
            try await latexFormPreview(app: app)
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
