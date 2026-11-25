import AppKit
import Contracts
import ToolService

/// Native confirmation for every write that needs it, regardless of caller (Launcher, Pi, external MCP).
/// Requests are shown one at a time using the system alert layout.
@MainActor @Observable
final class ConfirmationCenter {
    struct Pending: Identifiable {
        let request: ConfirmationRequest
        let continuation: CheckedContinuation<ConfirmationDecision, Never>
        var id: String { request.id }
    }

    private(set) var queue: [Pending] = []
    private var alert: NSAlert?

    nonisolated init() {}

    func present(_ request: ConfirmationRequest) async -> ConfirmationDecision {
        await withCheckedContinuation { continuation in
            queue.append(Pending(request: request, continuation: continuation))
            showNextAlert()
        }
    }

    func rejectAll() {
        let pending = queue
        queue.removeAll()
        pending.forEach { $0.continuation.resume(returning: .rejected) }
        if let alert { AppDialog.dismiss(alert) }
    }

    /// Present the resolved target and changes as one paragraph, rather than exposing
    /// the adapter's field list or raw tool arguments in the alert.
    static func message(for request: ConfirmationRequest, remaining: Int) -> String {
        let english = Bundle.main.preferredLocalizations.first == "en"
        func format(_ key: String, _ values: CVarArg...) -> String {
            String(format: NSLocalizedString(key, comment: "Confirmation description"), arguments: values)
        }
        func text(_ value: String) -> String {
            value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        func clause(_ value: String) -> String {
            var result = text(value)
            while let last = result.last, "。！？.!?；;".contains(last) { result.removeLast() }
            return result
        }
        var showsDates = false
        func date(_ value: String) -> String {
            let iso = ISO8601DateFormatter()
            var parsed = iso.date(from: value)
            if parsed == nil {
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                parsed = iso.date(from: value)
            }
            guard let parsed else { return value }
            showsDates = true
            let display = DateFormatter()
            display.locale = Locale(identifier: english ? "en" : "zh_CN")
            display.timeZone = .current
            if english { display.setLocalizedDateFormatFromTemplate("yMMMd HHmm") }
            else { display.dateFormat = "yyyy年M月d日 HH:mm" }
            return display.string(from: parsed)
        }
        func change(_ value: String) -> String {
            let value = text(value)
            guard let separator = value.firstIndex(of: "：") else {
                if value == "无输入" { return NSLocalizedString("不传入任何内容", comment: "") }
                if value.hasPrefix("删除 "), value.hasSuffix(" 的这次日程") {
                    return format("时间为%@", date(String(value.dropFirst(3).dropLast(6))))
                }
                let range = value.components(separatedBy: " – ")
                if request.tool == "calendar_create_event", range.count == 2 { return format("时间为%@至%@", date(range[0]), date(range[1])) }
                for (prefix, key) in [("新建提醒「", "新建提醒「%@」"), ("新建「", "新建「%@」"), ("切换到「", "切换到「%@」")] {
                    if value.hasPrefix(prefix), value.hasSuffix("」") {
                        return format(key, String(value.dropFirst(prefix.count).dropLast()))
                    }
                }
                return clause(value)
            }
            let field = String(value[..<separator])
            let content = String(value[value.index(after: separator)...])
            let names = ["开始": "开始时间", "结束": "结束时间", "到期": "到期时间"]
            let name = NSLocalizedString(names[field] ?? field, comment: "")
            let fields = ["标题", "内容", "正文", "链接", "路径", "名称", "开始", "结束", "到期", "地点", "追加", "添加", "改为", "草稿", "输入"]
            guard fields.contains(field) else { return clause(value) }
            if request.tool == "calendar_update_event", let arrow = content.range(of: " → ") {
                var before = String(content[..<arrow.lowerBound])
                var after = String(content[arrow.upperBound...])
                if field == "开始" || field == "结束" {
                    before = date(before)
                    after = date(after)
                }
                return format("%@将从「%@」改为「%@」", name, before, after)
            }
            if field == "到期" { return format("到期时间为%@", date(content)) }
            switch field {
            case "追加": return format("追加内容「%@」", content)
            case "添加": return format("添加内容「%@」", content)
            case "改为": return format("改为「%@」", content)
            case "草稿": return format("草稿内容为「%@」", content)
            case "输入": return format("输入内容为「%@」", content)
            default: return format("%@为「%@」", name, content)
            }
        }
        var target = clause(request.target)
        if request.tool == "messages_prepare_draft", target.hasPrefix("Messages：") {
            target = String(target.dropFirst("Messages：".count))
        } else if request.tool == "notes_create", target.hasPrefix("Notes「") {
            target = "备忘录文件夹「" + target.dropFirst("Notes「".count)
        } else if request.tool == "calendar_create_event", target.hasPrefix("苹果日历 ·") {
            target = "苹果日历的" + target.dropFirst("苹果日历 ·".count)
        } else if request.tool == "memory_save", target.hasPrefix("记忆 ") {
            target = "记忆文件「" + target.dropFirst("记忆 ".count) + "」"
        }
        if english {
            for (prefix, key) in [("备忘录文件夹「", "备忘录文件夹"), ("备忘录「", "备忘录"),
                                  ("苹果日历的", "日历"), ("日程「", "日程"), ("提醒列表「", "提醒列表"),
                                  ("记忆文件「", "记忆文件"), ("记忆「", "记忆"), ("快捷指令「", "快捷指令")] {
                if target.hasPrefix(prefix) {
                    let suffix = String(target.dropFirst(prefix.count))
                    target = NSLocalizedString(key, comment: "Confirmation target type") + " " + (prefix.hasSuffix("「") ? "「" : "") + suffix
                    break
                }
            }
            if target == "Chrome 标签页" { target = NSLocalizedString(target, comment: "") }
        }
        let operation: String
        switch request.tool {
        case "calendar_create_event", "reminders_create", "notes_create", "notes_append", "memory_save":
            operation = format("将在%@中", target)
        case "calendar_update_event": operation = format("将修改%@，", target)
        case "calendar_delete_event": operation = format("将删除%@，", target)
        case "memory_correct": operation = format("将把%@的内容", target)
        case "memory_forget": operation = format("将删除%@", target)
        case "messages_prepare_draft": operation = format("将为%@准备信息草稿，", target)
        case "shortcuts_run": operation = format("将运行%@，", target)
        case "chrome_activate_tab": operation = NSLocalizedString("将在 Chrome 中", comment: "")
        default: operation = target + (request.changes.isEmpty ? "" : english ? ", " : "，")
        }
        let changes = request.tool == "memory_forget" ? "" : request.changes.enumerated().map { index, value in
            if request.tool == "notes_create" {
                if index > 0 { return format("内容为「%@」", text(value)) }
                if value.hasPrefix("新建「") { return format("新建备忘录「%@」", String(value.dropFirst("新建「".count).dropLast())) }
            }
            if request.tool == "calendar_create_event", index == 0, value.hasPrefix("新建「") {
                return format("新建日程「%@」", String(value.dropFirst("新建「".count).dropLast()))
            }
            if request.tool == "chrome_activate_tab", index > 0 { return format("页面地址为「%@」", text(value)) }
            return change(value)
        }.joined(separator: english ? "; " : "，")
        var body = clause(operation + changes) + (english ? ". " : "。")
        if case .mcp = request.origin { body = NSLocalizedString("外部应用请求执行这项操作。", comment: "") + (english ? " " : "") + body }
        if let note = request.note, !note.isEmpty {
            let notes = ["重复日程：仅修改本次": "此次只修改重复日程中的这一次",
                         "重复日程：仅删除本次": "此次只删除重复日程中的这一次"]
            let overlap = note.components(separatedBy: " ")
            let localizedNote: String
            if overlap.count == 3, overlap[0] == "与", overlap[2] == "个日程时间重叠", let count = Int(overlap[1]) {
                localizedNote = format("与 %d 个日程时间重叠", count)
            } else {
                localizedNote = NSLocalizedString(notes[note] ?? clause(note), comment: "")
            }
            body += localizedNote + (english ? ". " : "。")
        }
        if showsDates {
            let zone = TimeZone.current
            let name = zone.localizedName(for: .generic, locale: Locale(identifier: english ? "en" : "zh_CN")) ?? zone.identifier
            body += format("以上时间均按%@显示。", name)
        }
        if remaining > 0 { body += format("另外还有%d项操作需要你确认。", remaining) }
        if body.hasSuffix("。") { body.removeLast() }
        if english { body = body.trimmingCharacters(in: .whitespaces) }
        return body
    }

    private func showNextAlert() {
        guard alert == nil, let pending = queue.first else { return }
        let request = pending.request
        let alert = AppDialog.make()
        let titles = [
            "calendar_create_event": "创建日程？", "calendar_update_event": "修改日程？",
            "calendar_delete_event": "删除日程？", "reminders_create": "创建提醒事项？",
            "notes_create": "创建备忘录？", "notes_append": "追加备忘录内容？",
            "messages_prepare_draft": "准备信息草稿？", "shortcuts_run": "运行快捷指令？",
            "chrome_activate_tab": "切换浏览器标签页？", "memory_save": "保存这条记忆？",
            "memory_correct": "修改这条记忆？", "memory_forget": "删除这条记忆？"
        ]
        alert.messageText = request.title ?? NSLocalizedString(titles[request.tool] ?? "执行这项操作？", comment: "")
        alert.informativeText = Self.message(for: request, remaining: queue.count - 1)
        let confirm = alert.addButton(withTitle: NSLocalizedString("确认执行", comment: ""))
        confirm.keyEquivalent = "\r"
        if request.tool == "calendar_delete_event" || request.tool == "memory_forget" {
            confirm.hasDestructiveAction = true
        }
        alert.addButton(withTitle: NSLocalizedString("不执行", comment: "")).keyEquivalent = "\u{1b}"
        self.alert = alert

        // Schedule presentation after the continuation has been registered. AppKit owns
        // focus, layout, appearance, and keyboard handling, just like a system permission alert.
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.queue.contains(where: { $0.id == pending.id }) else {
                self.alert = nil
                self.showNextAlert()
                return
            }
            NSApp.activate()
            let response = await AppDialog.present(alert)
            alert.window.orderOut(nil)
            self.alert = nil
            if let index = self.queue.firstIndex(where: { $0.id == pending.id }) {
                self.queue.remove(at: index).continuation.resume(
                    returning: response == .alertFirstButtonReturn ? .approved : .rejected)
            }
            self.showNextAlert()
        }
    }
}
