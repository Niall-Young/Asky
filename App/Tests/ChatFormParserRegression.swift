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
        precondition(complete.fields[1].type == .radio, "legacy select must decode as radio")
        precondition(!complete.accepts([:]))
        let orderedParts = ChatFormParser.parse(source, streaming: false)
        precondition(orderedParts.count == 2, "leading and trailing markdown must merge above the form")
        if case .markdown(let prose) = orderedParts[0].content, case .form = orderedParts[1].content {
            precondition(prose == "先填写这些信息：\n\n填好后提交。", "trailing prose must move above the form")
        } else {
            preconditionFailure("form must always be the final part in a reply")
        }
        let trailingOnlyParts = ChatFormParser.parse("```asky-form\n{\"title\":\"仅尾文\"}\n{\"id\":\"a\",\"type\":\"text\",\"label\":\"项\"}\n```\n补充说明。", streaming: false)
        precondition(trailingOnlyParts.count == 2)
        if case .markdown(let prose) = trailingOnlyParts[0].content, case .form = trailingOnlyParts[1].content {
            precondition(prose == "补充说明。")
        } else {
            preconditionFailure("trailing prose must render before the form even without leading text")
        }
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
        let startField = timeForm.fields[0]
        precondition(startField.parseTemporalInput("9:5") == [9, 5])
        precondition(startField.parseTemporalInput("14：30") == [14, 30])
        precondition(startField.parseTemporalInput("1430") == [14, 30])
        precondition(startField.parseTemporalInput("24:00") == nil)
        precondition(ChatForm.parseDateInput("2026/11/5").map(ChatForm.dateString) == "2026-11-05")
        precondition(ChatForm.parseDateInput("20261124").map(ChatForm.dateString) == "2026-11-24")
        precondition(ChatForm.parseDateInput("2026-02-30") == nil)
        let dateTimeForm = ChatFormParser.form(in: "```asky-form\n{\"title\":\"日程\"}\n{\"id\":\"when\",\"type\":\"datetime\",\"label\":\"开始时间\",\"required\":true,\"defaultValue\":\"2026-11-25 14:30\"}\n```")!
        precondition(dateTimeForm.fields[0].type == .datetime)
        precondition(dateTimeForm.prefilling([:]) == ["when": ["2026-11-25 14:30"]])
        precondition(dateTimeForm.accepts(["when": ["2026-11-25 14:30"]]))
        precondition(!dateTimeForm.accepts(["when": ["2026-11-25"]]))
        precondition(!dateTimeForm.accepts(["when": ["2026-02-30 14:30"]]))
        precondition(!dateTimeForm.accepts(["when": ["2026-11-25 24:00"]]))
        precondition(dateTimeForm.reply(["when": ["2026-11-25 14:30"]]) == "2026-11-25 14:30")
        let dtField = dateTimeForm.fields[0]
        let parsedDT1 = dtField.parseDateTimeInput("2026/11/5 9:5")!
        precondition(dtField.dateTimeString(date: parsedDT1.date, time: parsedDT1.time) == "2026-11-05 09:05")
        let parsedDT2 = dtField.parseDateTimeInput("20261125 1430")!
        precondition(dtField.dateTimeString(date: parsedDT2.date, time: parsedDT2.time) == "2026-11-25 14:30")
        let parsedDT3 = dtField.parseDateTimeInput("2026-11-25T08:05")!
        precondition(dtField.dateTimeString(date: parsedDT3.date, time: parsedDT3.time) == "2026-11-25 08:05")
        precondition(dtField.parseDateTimeInput("2026-02-30 14:30") == nil)
        let fullDateTime = ChatFormParser.form(in: "```asky-form\n{\"title\":\"精确时间\"}\n{\"id\":\"ts\",\"type\":\"datetime\",\"label\":\"时刻\",\"components\":[\"hour\",\"minute\",\"second\"]}\n```")!
        precondition(fullDateTime.accepts(["ts": ["2026-11-25 23:59:59"]]))
        precondition(!fullDateTime.accepts(["ts": ["2026-11-25 23:59"]]))
        let rangeForm = ChatFormParser.form(in: """
            ```asky-form
            {"title":"会议与出差"}
            {"id":"slot","type":"datetime_range","label":"会议时间","required":true,"defaultValue":"2026-11-26 19:00 - 2026-11-26 20:00"}
            {"id":"trip","type":"date_range","label":"出差日期","defaultValue":"2026-11-26 - 2026-11-28"}
            {"id":"dnd","type":"time_range","label":"勿扰时段","defaultValue":"09:00-18:00"}
            ```
            """)!
        precondition(rangeForm.fields.map(\.type) == [.datetimeRange, .dateRange, .timeRange])
        precondition(rangeForm.prefilling([:]) == [
            "slot": ["2026-11-26 19:00 – 20:00"],
            "trip": ["2026-11-26 – 2026-11-28"],
            "dnd": ["09:00 – 18:00"]
        ])
        precondition(rangeForm.accepts(["slot": ["2026-11-26 19:00 – 20:00"]]))
        precondition(rangeForm.accepts(["slot": ["2026-11-26 19:00 – 2026-11-27 10:00"]]))
        precondition(!rangeForm.accepts(["slot": ["2026-11-26 20:00 – 19:00"]]))
        precondition(!rangeForm.accepts(["slot": ["2026-11-26 19:00 – 19:00"]]))
        let slotField = rangeForm.fields[0]
        let parsedRange1 = slotField.parseDateTimeRangeInput("2026/11/26 9:5 ~ 10:30")!
        precondition(slotField.dateTimeRangeString(startDate: parsedRange1.startDate, startTime: parsedRange1.startTime,
                                                   endDate: parsedRange1.endDate, endTime: parsedRange1.endTime) == "2026-11-26 09:05 – 10:30")
        let parsedRange2 = slotField.parseDateTimeRangeInput("20261126 1900 - 20261127 0930")!
        precondition(slotField.dateTimeRangeString(startDate: parsedRange2.startDate, startTime: parsedRange2.startTime,
                                                   endDate: parsedRange2.endDate, endTime: parsedRange2.endTime) == "2026-11-26 19:00 – 2026-11-27 09:30")
        precondition(rangeForm.accepts(["slot": ["2026-11-26 19:00 – 20:00"], "trip": ["2026-11-26 – 2026-11-26"]]))
        precondition(!rangeForm.accepts(["slot": ["2026-11-26 19:00 – 20:00"], "trip": ["2026-11-28 – 2026-11-26"]]))
        precondition(!rangeForm.accepts(["slot": ["2026-11-26 19:00 – 20:00"], "dnd": ["18:00 – 09:00"]]))
        // Partial ranges (start selected, end cleared awaiting re-selection) must parse start and block submission.
        let partialDateTime = slotField.partialDateTimeRangeString(startDate: parsedRange1.startDate, startTime: [11, 0])
        precondition(partialDateTime == "2026-11-26 11:00 – ")
        precondition(!rangeForm.accepts(["slot": [partialDateTime]]))
        let parsedPartialDT = slotField.partialDateTimeRangeStart(partialDateTime)!
        precondition(ChatForm.dateString(parsedPartialDT.startDate) == "2026-11-26" && parsedPartialDT.startTime == [11, 0])
        let tripField = rangeForm.fields[1]
        let partialDate = tripField.partialDateRangeString(start: parsedRange1.startDate)
        precondition(partialDate == "2026-11-26 – ")
        precondition(!rangeForm.accepts(["slot": ["2026-11-26 19:00 – 20:00"], "trip": [partialDate]]))
        precondition(tripField.partialDateRangeStart(partialDate).map(ChatForm.dateString) == "2026-11-26")
        let dndField = rangeForm.fields[2]
        let partialTime = dndField.partialTimeRangeString(start: [11, 0])
        precondition(partialTime == "11:00 – ")
        precondition(!rangeForm.accepts(["slot": ["2026-11-26 19:00 – 20:00"], "dnd": [partialTime]]))
        precondition(dndField.partialTimeRangeStart(partialTime) == [11, 0])
        let aliasForm = ChatFormParser.form(in: "```asky-form\n{\"title\":\"别名\"}\n{\"id\":\"a\",\"type\":\"datetime-range\",\"label\":\"A\"}\n{\"id\":\"b\",\"type\":\"date-range\",\"label\":\"B\"}\n{\"id\":\"c\",\"type\":\"timerange\",\"label\":\"C\"}\n```")!
        precondition(aliasForm.fields.map(\.type) == [.datetimeRange, .dateRange, .timeRange])
        // Auto-coalesce split start/end fields into unified range pickers.
        let splitDateTimeForm = ChatFormParser.form(in: """
            ```asky-form
            {"title":"新建日程"}
            {"id":"title","type":"text","label":"日程标题","required":true}
            {"id":"start_time","type":"datetime","label":"会议开始时间","required":true,"defaultValue":"2026-11-26 14:00"}
            {"id":"end_time","type":"datetime","label":"会议结束时间","required":true,"defaultValue":"2026-11-26 15:30"}
            ```
            """)!
        precondition(splitDateTimeForm.fields.count == 2)
        precondition(splitDateTimeForm.fields[1].type == .datetimeRange)
        precondition(splitDateTimeForm.fields[1].label == "会议时间")
        precondition(splitDateTimeForm.prefilling([:])["start_time"] == ["2026-11-26 14:00 – 15:30"])
        let splitTripleForm = ChatFormParser.form(in: """
            ```asky-form
            {"title":"安排日程"}
            {"id":"date","type":"date","label":"日程日期","required":true,"defaultValue":"2026-11-27"}
            {"id":"start","type":"time","label":"开始时间","required":true,"defaultValue":"09:30"}
            {"id":"end","type":"time","label":"结束时间","required":true,"defaultValue":"11:00"}
            ```
            """)!
        precondition(splitTripleForm.fields.count == 1)
        precondition(splitTripleForm.fields[0].type == .datetimeRange)
        precondition(splitTripleForm.fields[0].label == "日程时间")
        precondition(splitTripleForm.prefilling([:])["date"] == ["2026-11-27 09:30 – 11:00"])
        let splitQuadForm = ChatFormParser.form(in: """
            ```asky-form
            {"title":"跨日行程"}
            {"id":"start_date","type":"date","label":"开始日期","defaultValue":"2026-11-27"}
            {"id":"start_time","type":"time","label":"开始时间","defaultValue":"18:00"}
            {"id":"end_date","type":"date","label":"结束日期","defaultValue":"2026-11-28"}
            {"id":"end_time","type":"time","label":"结束时间","defaultValue":"10:00"}
            ```
            """)!
        precondition(splitQuadForm.fields.count == 1)
        precondition(splitQuadForm.fields[0].type == .datetimeRange)
        precondition(splitQuadForm.fields[0].label == "时间段")
        precondition(splitQuadForm.prefilling([:])["start_date"] == ["2026-11-27 18:00 – 2026-11-28 10:00"])
        let splitDateAndTimeForm = ChatFormParser.form(in: """
            ```asky-form
            {"title":"请假与勿扰"}
            {"id":"leave_start","type":"date","label":"请假开始日期","defaultValue":"2026-11-26"}
            {"id":"leave_end","type":"date","label":"请假结束日期","defaultValue":"2026-11-28"}
            {"id":"workStart","type":"time","label":"工作开始时间","defaultValue":"09:00"}
            {"id":"workEnd","type":"time","label":"工作结束时间","defaultValue":"18:00"}
            {"id":"startDate","type":"date","label":"Start Date","defaultValue":"2026-12-01"}
            {"id":"endDate","type":"date","label":"End Date","defaultValue":"2026-12-03"}
            ```
            """)!
        precondition(splitDateAndTimeForm.fields.map(\.type) == [.dateRange, .timeRange, .dateRange])
        precondition(splitDateAndTimeForm.fields.map(\.label) == ["请假日期", "工作时间", "Date Range"])
        precondition(splitDateAndTimeForm.prefilling([:]) == [
            "leave_start": ["2026-11-26 – 2026-11-28"],
            "workStart": ["09:00 – 18:00"],
            "startDate": ["2026-12-01 – 2026-12-03"]
        ])
        let mismatchedPrefixForm = ChatFormParser.form(in: """
            ```asky-form
            {"title":"不同前缀不合并"}
            {"id":"outbound_start","type":"datetime","label":"去程开始时间"}
            {"id":"return_end","type":"datetime","label":"返程结束时间"}
            ```
            """)!
        precondition(mismatchedPrefixForm.fields.map(\.type) == [.datetime, .datetime],
                     "Mismatched prefixes must not be falsely merged")
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
        let radio = ChatFormParser.form(in: "```asky-form\n{\"id\":\"drink\",\"type\":\"radio\",\"label\":\"饮品\",\"options\":[\"茶\",\"咖啡\",\"水\"],\"required\":true}\n```")!
        precondition(radio.title == nil)
        precondition(!radio.accepts([:]))
        precondition(radio.accepts(["drink": ["茶"]]))
        precondition(!radio.accepts(["drink": ["茶", "水"]]))
        precondition(!radio.accepts(["drink": ["不存在的选项"]]))
        precondition(radio.reply(["drink": ["咖啡"]]) == "咖啡")
        for kind in ["radio", "select"] {
            let custom = ChatFormParser.form(in: "```asky-form\n{\"title\":\"确认方案\"}\n{\"id\":\"answer\",\"type\":\"\(kind)\",\"label\":\"怎么处理\",\"options\":[\"现在修改\",\"稍后处理\"],\"required\":true,\"allowCustom\":true}\n```")!
            precondition(!custom.accepts([:]))
            precondition(custom.accepts(["answer": ["现在修改"]]))
            let own = ["answer": ["先给我看改动，再决定"]]
            precondition(custom.accepts(own))
            precondition(custom.reply(own) == "先给我看改动，再决定")
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
        precondition(!complete.reply(values).hasPrefix("安排会议"), "form reply must not prepend redundant title")
        let titlelessSource = """
        你遇到了什么问题？
        ```asky-form
        {"id":"issue","type":"radio","label":"遇到的问题","options":["无法登录","页面卡顿","数据未同步"],"required":true}
        ```
        """
        let titlelessForm = ChatFormParser.form(in: titlelessSource)!
        precondition(titlelessForm.title == nil && titlelessForm.isComplete && titlelessForm.fields.count == 1)
        precondition(titlelessForm.reply(["issue": ["页面卡顿"]]) == "页面卡顿")
        var titlelessPrefix = ""
        for ch in titlelessSource {
            titlelessPrefix.append(ch)
            for part in ChatFormParser.parse(titlelessPrefix, streaming: true) {
                if case .markdown(let text) = part.content {
                    precondition(!text.contains("\"id\""), "title-less form JSON must not flash in Markdown")
                }
            }
        }
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
