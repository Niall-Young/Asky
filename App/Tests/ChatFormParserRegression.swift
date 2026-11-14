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
        // Regression: one unescaped LaTeX delimiter in an option used to turn the
        // entire otherwise valid form into a code block (including reopened history).
        let latexSource = #"""
        ```asky-form
        {"title":"LaTeX 公式"}
        {"id":"goal","type":"radio","label":"你想要什么","options":["查看示例","输入具体式子"],"required":true,"allowCustom":true}
        {"id":"detail","type":"text","label":"具体式子（可选）"}
        {"id":"display","type":"radio","label":"输出形式","options":["行内 $...$","独立公式块 $$...$$ 或 \[...\]","两者都给"],"allowCustom":true}
        ```
        """#
        let latexForm = ChatFormParser.form(in: latexSource)!
        precondition(latexForm.isComplete && latexForm.fields.count == 3)
        precondition(latexForm.fields[2].options?[1] == #"独立公式块 $$...$$ 或 \[...\]"#)
        let latexAnswer = ["goal": ["查看示例"], "display": [#"独立公式块 $$...$$ 或 \[...\]"#]]
        precondition(latexForm.accepts(latexAnswer))
        precondition(latexForm.reply(latexAnswer).contains(#"\[...\]"#))
        var latexPrefix = ""
        for character in latexSource {
            latexPrefix.append(character)
            for part in ChatFormParser.parse(latexPrefix, streaming: true) {
                if case .markdown(let text) = part.content {
                    precondition(!text.contains("\"id\""), "LaTeX escapes must not expose form JSON while streaming")
                }
            }
        }
        let escapedLabel = #"\(x\), \"quoted\", \\frac{a}{b}, \\n, \u4E2D"#
        let mixedEscapes = latexSource.replacingOccurrences(of: "具体式子（可选）", with: escapedLabel)
        precondition(ChatFormParser.form(in: mixedEscapes)?.fields[1].label == #"\(x\), "quoted", \frac{a}{b}, \n, 中"#,
                     "Repair must preserve valid quotes, backslashes and Unicode escapes")
        let validJSON = latexSource.replacingOccurrences(of: #"\[...\]"#, with: #"\\[...\\]"#)
        precondition(ChatFormParser.form(in: validJSON) == latexForm, "Valid JSON must decode unchanged")
        for invalid in [latexSource.replacingOccurrences(of: "\"radio\"", with: "\"unknown\""),
                        latexSource.replacingOccurrences(of: "\"allowCustom\":true", with: "\"allowCustom\" true"),
                        latexSource.replacingOccurrences(of: "具体式子（可选）", with: #"\uZZZZ"#)] {
            precondition(ChatFormParser.form(in: invalid) == nil, "Invalid structure/schema must still fall back")
        }
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
        let prefilledSource = """
        ```asky-form
        {"title":"会议安排"}
        {"id":"title","type":"text","label":"名称","required":true,"defaultValue":"项目周会"}
        {"id":"format","type":"radio","label":"形式","options":["线上","线下"],"defaultValue":"线上"}
        {"id":"length","type":"select","label":"时长","options":["30 分钟","60 分钟"],"defaultValue":"30 分钟"}
        {"id":"topics","type":"multi","label":"议题","options":["设计","开发"],"defaultValue":["设计","开发"]}
        {"id":"day","type":"date","label":"日期","defaultValue":"2026-11-15"}
        {"id":"time","type":"time","label":"开始","defaultValue":"15:00"}
        {"id":"duration","type":"duration","label":"倒计时","components":["minute","second"],"defaultValue":"05:30"}
        {"id":"custom","type":"radio","label":"地点","options":["会议室"],"allowCustom":true,"defaultValue":"视频通话"}
        ```
        """
        let prefilled = ChatFormParser.form(in: prefilledSource)!
        let defaults = prefilled.prefilling([:])
        precondition(defaults.count == 8 && prefilled.accepts(defaults))
        precondition(defaults["topics"] == ["设计", "开发"] && defaults["custom"] == ["视频通话"])
        precondition(prefilled.reply(defaults).contains("倒计时：5 分钟 30 秒钟"))
        let cleared = prefilled.prefilling(["title": [""], "topics": [], "format": []])
        precondition(cleared["title"] == [""] && cleared["topics"] == [] && cleared["format"] == [])
        precondition(!prefilled.accepts(cleared), "Clearing a required default must disable submission")
        let edited = prefilled.prefilling(["title": ["新的标题"], "time": ["16:00"]])
        precondition(edited["title"] == ["新的标题"] && edited["time"] == ["16:00"])
        precondition(prefilled.prefilling(edited) == edited, "Repeated rendering must preserve edits")
        var unfinished = prefilled; unfinished.isComplete = false
        precondition(unfinished.prefilling([:]).isEmpty && !unfinished.accepts(defaults))
        // Bad defaults are discarded independently; the field remains available to correct.
        for (type, value, extra) in [
            ("text", "42", ""), ("text", "true", ""), ("text", "{}", ""),
            ("text", "null", ""), ("text", "[\"wrong shape\"]", ""),
            ("text", "\"" + String(repeating: "字", count: 4001) + "\"", ""),
            ("radio", "\"不存在\"", ",\"options\":[\"线上\",\"线下\"]"),
            ("multi", "[\"设计\",\"设计\"]", ",\"options\":[\"设计\",\"开发\"]"),
            ("multi", "[\"不存在\"]", ",\"options\":[\"设计\",\"开发\"]"),
            ("multi", "\"设计\"", ",\"options\":[\"设计\",\"开发\"]"),
            ("date", "\"2026-02-30\"", ""), ("time", "\"24:00\"", ""),
            ("duration", "\"05:60\"", ""), ("duration", "\"05:00\"", ",\"components\":[\"second\"]")
        ] {
            let schema = "```asky-form\n{\"title\":\"测试\"}\n{\"id\":\"field\",\"type\":\"\(type)\",\"label\":\"值\",\"defaultValue\":\(value)\(extra)}\n```"
            let form = ChatFormParser.form(in: schema)!
            precondition(form.prefilling([:]).isEmpty, schema)
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
