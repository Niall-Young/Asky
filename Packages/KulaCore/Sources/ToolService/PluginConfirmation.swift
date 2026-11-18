import Foundation
import Contracts

enum PluginConfirmation {
    static func preview(pluginName: String, arguments: JSONValue) -> ConfirmationPreview {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let details = (try? encoder.encode(arguments)).flatMap { String(data: $0, encoding: .utf8) }
        var changes: [String] = []
        var title = String(format: CoreLocalization.text("允许「%@」执行操作？"), pluginName)
        var target = String(format: CoreLocalization.text("将通过「%@」插件执行操作。"), pluginName)
        // Only describe values actually present in the request; never infer a destination
        // or claim a CLI operation was resolved from a generic execute tool.
        let labels = ["title": "标题", "summary": "标题", "text": "内容", "content": "内容",
                      "body": "正文", "url": "链接", "path": "路径", "name": "名称"]
        func append(_ key: String, _ value: JSONValue) {
            guard let label = labels[key], let text = value.stringValue, !text.isEmpty else { return }
            if let data = text.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
               decoded.objectValue != nil || decoded.arrayValue != nil { return }
            changes.append(label + "：" + String(text.prefix(400)))
        }
        for (key, value) in (arguments.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
            append(key, value)
        }
        if let argv = arguments["argv"]?.arrayValue?.compactMap(\.stringValue) {
            let route = Array(argv.prefix { !$0.hasPrefix("--") })
            let resources = ["wiki": "知识库内容", "docx": "文档内容", "calendar": "日历内容",
                             "task": "任务内容", "im": "聊天内容", "drive": "云空间内容", "sheets": "电子表格内容"]
            let actions = ["create": "创建", "node-create": "创建", "+create": "创建",
                           "update": "修改", "node-update": "修改", "+update": "修改",
                           "delete": "删除", "node-delete": "删除", "+delete": "删除",
                           "send": "发送", "+send": "发送", "copy": "复制", "move": "移动"]
            if let domain = route.first, let resource = resources[domain],
               let verb = route.last, let action = actions[verb] {
                let operation = String(format: CoreLocalization.text("%@%@"),
                                       CoreLocalization.text(action), CoreLocalization.text(resource))
                title = String(format: CoreLocalization.text("通过「%@」%@？"), pluginName, operation)
                target = String(format: CoreLocalization.text("将通过「%@」%@。"), pluginName, operation)
            }
            for index in argv.indices where argv[index].hasPrefix("--") && index + 1 < argv.count {
                let key = String(argv[index].dropFirst(2)), value = argv[index + 1]
                if key == "data", let data = value.data(using: .utf8),
                   let fields = try? JSONDecoder().decode(JSONValue.self, from: data).objectValue {
                    for (key, value) in fields.sorted(by: { $0.key < $1.key }) { append(key, value) }
                } else { append(key, .string(value)) }
            }
        }
        return ConfirmationPreview(
            target: target,
            changes: changes,
            title: title,
            details: details)
    }
}
