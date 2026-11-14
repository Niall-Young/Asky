import Foundation

@main
enum ChatFormParserRegression {
    static func main() {
        let source = """
        先填写这些信息：
        ```asky-form
        {"title":"安排会议"}
        {"id":"title","type":"text","label":"名称","required":true}
        {"id":"duration","type":"select","label":"时长","options":["30 分钟","60 分钟"],"required":true}
        {"id":"topics","type":"multi","label":"议题","options":["设计","开发"]}
        {"id":"day","type":"date","label":"日期","required":true}
        ```
        填好后提交。
        """
        let complete = ChatFormParser.form(in: source)!
        precondition(complete.fields.count == 4 && complete.isComplete)
        precondition(!complete.accepts([:]))
        let timeForm = ChatFormParser.form(in: "```asky-form\n{\"title\":\"时间\"}\n{\"id\":\"start\",\"type\":\"time\",\"label\":\"开始时间\",\"required\":true}\n```")!
        precondition(!timeForm.accepts([:]))
        for value in ["00:00", "09:05", "14:30", "23:59"] {
            precondition(timeForm.accepts(["start": [value]]))
            precondition(timeForm.reply(["start": [value]]).contains(value))
        }
        for value in ["24:00", "12:60", "9:05", "上午九点", "14:30:00", " 14:30", "14:30 "] {
            precondition(!timeForm.accepts(["start": [value]]), value)
        }
        func temporalForm(_ type: String, _ components: String) -> ChatForm? {
            ChatFormParser.form(in: "```asky-form\n{\"title\":\"测试\"}\n{\"id\":\"value\",\"type\":\"\(type)\",\"label\":\"值\",\"components\":\(components)}\n```")
        }
        let fullClock = temporalForm("time", "[\"hour\",\"minute\",\"second\"]")!
        precondition(fullClock.accepts(["value": ["23:59:59"]]))
        precondition(!fullClock.accepts(["value": ["24:00:00"]]))
        precondition(!fullClock.accepts(["value": ["14:30"]]))
        let countdown = temporalForm("duration", "[\"minute\",\"second\"]")!
        precondition(countdown.accepts(["value": ["90:30"]]))
        precondition(!countdown.accepts(["value": ["03:60"]]))
        precondition(countdown.reply(["value": ["03:30"]]).contains("3 分钟 30 秒钟"))
        for unit in ["hour", "minute", "second"] {
            let single = temporalForm("duration", "[\"\(unit)\"]")!
            precondition(single.fields[0].timeUnits.count == 1)
            precondition(single.accepts(["value": ["90"]]))
            precondition(!single.accepts(["value": ["90:00"]]))
        }
        for invalidUnits in ["[]", "[\"second\",\"minute\"]", "[\"minute\",\"minute\"]", "[\"day\"]"] {
            precondition(temporalForm("time", invalidUnits) == nil)
        }
        let radio = ChatFormParser.form(in: "```asky-form\n{\"title\":\"单选\"}\n{\"id\":\"drink\",\"type\":\"radio\",\"label\":\"饮品\",\"options\":[\"茶\",\"咖啡\",\"水\"],\"required\":true}\n```")!
        precondition(!radio.accepts([:]))
        precondition(radio.accepts(["drink": ["茶"]]))
        precondition(!radio.accepts(["drink": ["茶", "水"]]))
        precondition(!radio.accepts(["drink": ["不存在的选项"]]))
        precondition(radio.reply(["drink": ["咖啡"]]).contains("饮品：咖啡"))
        for kind in ["radio", "select"] {
            let custom = ChatFormParser.form(in: "```asky-form\n{\"title\":\"确认方案\"}\n{\"id\":\"answer\",\"type\":\"\(kind)\",\"label\":\"怎么处理\",\"options\":[\"现在修改\",\"稍后处理\"],\"required\":true,\"allowCustom\":true}\n```")!
            precondition(!custom.accepts([:]))
            precondition(custom.accepts(["answer": ["现在修改"]]))
            let own = ["answer": ["先给我看改动，再决定"]]
            precondition(custom.accepts(own))
            precondition(custom.reply(own) == "确认方案\n怎么处理：先给我看改动，再决定")
            for invalid in [[""], [" \n "], [String(repeating: "字", count: 4001)], ["现在修改", "稍后处理"]] {
                precondition(!custom.accepts(["answer": invalid]))
            }
            precondition(custom.accepts(["answer": [String(repeating: "字", count: 4000)]]))
            let invalidType = "```asky-form\n{\"title\":\"测试\"}\n{\"id\":\"answer\",\"type\":\"multi\",\"label\":\"选择\",\"options\":[\"选项\"],\"allowCustom\":true}\n```"
            precondition(ChatFormParser.form(in: invalidType) == nil)
        }
        let values = ["title": ["评审"], "duration": ["30 分钟"], "topics": ["设计"], "day": ["2026-10-22"]]
        precondition(complete.accepts(values))
        precondition(complete.reply(values).contains("时长：30 分钟"))
        var invalid = values
        invalid["duration"] = ["注入的选项"]
        precondition(!complete.accepts(invalid))
        invalid = values; invalid["day"] = ["2026-02-30"]
        precondition(!complete.accepts(invalid))
        invalid = values; invalid["title"] = [" \n "]
        precondition(!complete.accepts(invalid))
        invalid = values; invalid["topics"] = ["设计", "设计"]
        precondition(!complete.accepts(invalid))

        // Every possible token boundary, including inside Chinese text and fence markers.
        var prefix = ""
        var firstFieldSeen = false
        let clock = ContinuousClock()
        let start = clock.now
        for character in source {
            prefix.append(character)
            let parts = ChatFormParser.parse(prefix, streaming: true)
            for part in parts {
                if case .form(let form) = part.content {
                    if !form.fields.isEmpty && !prefix.contains("\n```\n填") { firstFieldSeen = true }
                    precondition(form.fields.count <= 4)
                    if !prefix.contains("\n```\n填") { precondition(!form.accepts([:])) }
                } else if case .markdown(let text) = part.content, prefix.contains("```asky-form\n") {
                    precondition(!text.contains("\"id\""), "partial JSON must not flash in Markdown")
                }
            }
        }
        precondition(firstFieldSeen, "a field must appear before the closing fence")
        let headerAndField = source.components(separatedBy: "\n").prefix(4).joined(separator: "\n") + "\n"
        let partial = ChatFormParser.parse(headerAndField + "{\"id\":", streaming: true)
        precondition(partial.contains { if case .form(let f) = $0.content { f.fields.count == 1 && !f.isComplete } else { false } })
        let unclosed = ChatFormParser.form(in: headerAndField)!
        precondition(!unclosed.isComplete && !unclosed.accepts(values))
        for bad in [source.replacingOccurrences(of: "\"type\":\"text\"", with: "\"type\":\"html\""),
                    source.replacingOccurrences(of: "\"id\":\"duration\"", with: "\"id\":\"title\""),
                    "```asky-form\nnot json\n```",
                    "````markdown\n" + source + "\n````",
                    "~~~markdown\n" + source + "\n~~~"] {
            precondition(ChatFormParser.form(in: bad) == nil, bad)
        }
        precondition(ChatFormParser.parse(source + "\n" + source, streaming: false).filter {
            if case .form = $0.content { true } else { false }
        }.count == 1)
        precondition(ChatFormParser.parse("ordinary **Markdown**", streaming: false) == [.init(id: 0, content: .markdown("ordinary **Markdown**"))])
        print("Native forms: every-character streaming, early field rendering, schema validation, invalid/unfinished fallback, code fences and answer validation passed (\(start.duration(to: clock.now)))")
    }
}
