import Foundation
import Testing
@testable import Contracts

@Suite("ToolResultCard")
struct ToolResultCardTests {
    private let fixedCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return cal
    }()

    @Test("Builds calendar event card from completed readback")
    func calendarCreateCard() {
        let result = ExecutionResult(
            requestID: "req-cal-1",
            status: .completed,
            targets: [TargetRef(kind: "event", identifier: "ev-1")],
            readback: [
                "id": "ev-1",
                "title": "项目周会",
                "start": "2026-11-25T14:00:00+08:00",
                "end": "2026-11-25T15:00:00+08:00",
                "allDay": false,
                "calendar": "工作",
                "location": "会议室 A"
            ]
        )

        let card = ToolResultCard.from(tool: "calendar_create_event", result: result, calendar: fixedCalendar)
        #expect(card != nil)
        #expect(card?.kind == .calendarEvent)
        #expect(card?.source == .calendar)
        #expect(card?.headline == "14:00 – 15:00")
        #expect(card?.title == "项目周会")
        #expect(card?.subtitle?.contains("工作") == true)
        #expect(card?.metadata == ["会议室 A"])
        #expect(card?.action?.kind == .openCalendar)
    }

    @Test("Does not build card for non-completed execution")
    func skipsIncompleteExecution() {
        let result = ExecutionResult(
            requestID: "req-fail",
            status: .rejected,
            output: ["title": "未执行"]
        )
        #expect(ToolResultCard.from(tool: "calendar_create_event", result: result, calendar: fixedCalendar) == nil)
    }

    @Test("Builds reminder card using readback due time without notes metadata or default list noise")
    func reminderCreateCard() {
        let result = ExecutionResult(
            requestID: "req-rem-1",
            status: .completed,
            readback: [
                "id": "r-1",
                "title": "起床",
                "due": "2026-11-22T06:50:00+08:00",
                "list": "提醒事项"
            ]
        )
        let args: JSONValue = [
            "title": "起床",
            "notes": "每天提醒，确定后再修改标题。"
        ]

        let card = ToolResultCard.from(tool: "reminders_create", arguments: args, result: result, calendar: fixedCalendar)
        #expect(card != nil)
        #expect(card?.kind == .reminder)
        #expect(card?.headline == "06:50")
        #expect(card?.title == "起床")
        #expect(card?.subtitle == "11月22日 周日")
        #expect(card?.metadata.isEmpty == true)
        #expect(card?.action?.kind == .openReminders)
    }

    @Test("Builds note card without folder path subtitle")
    func noteCreateCard() {
        let result = ExecutionResult(
            requestID: "req-note-1",
            status: .completed,
            targets: [TargetRef(kind: "note", identifier: "n-1")],
            output: ["id": "n-1", "folder": "iCloud › Notes"],
            readback: ["id": "n-1", "name": "asky"]
        )
        let args: JSONValue = ["title": "asky", "body": "定时任务"]

        let card = ToolResultCard.from(tool: "notes_create", arguments: args, result: result, calendar: fixedCalendar)
        #expect(card != nil)
        #expect(card?.kind == .note)
        #expect(card?.headline == "asky")
        #expect(card?.title == "定时任务")
        #expect(card?.subtitle == nil)
        #expect(card?.metadata.isEmpty == true)
        #expect(card?.action?.kind == .openNotes)
    }

    @Test("Builds single-day calendar schedule card with date headline and no redundant row subtitle")
    func calendarScheduleSingleDayCard() {
        let result = ExecutionResult(
            requestID: "req-sched-1",
            status: .completed,
            output: [
                [
                    "id": "ev-bday",
                    "title": "何瑞兆雪的24岁生日",
                    "start": "2026-11-28T00:00:00+08:00",
                    "allDay": true,
                    "calendar": "生日"
                ]
            ]
        )

        let card = ToolResultCard.from(tool: "calendar_search_events", result: result, calendar: fixedCalendar)
        #expect(card != nil)
        #expect(card?.kind == .calendarSchedule)
        #expect(card?.headline == "11月28日 周六")
        #expect(card?.rows.count == 1)
        #expect(card?.rows.first?.title == "何瑞兆雪的24岁生日")
        #expect(card?.rows.first?.subtitle == nil)
        #expect(card?.rows.first?.trailing == "全天")
    }

    @Test("Builds multi-day calendar schedule card with date range headline and inline row dates")
    func calendarScheduleMultiDayCard() {
        let result = ExecutionResult(
            requestID: "req-sched-2",
            status: .completed,
            output: [
                [
                    "id": "ev-1",
                    "title": "何瑞兆雪的24岁生日",
                    "start": "2026-11-28T00:00:00+08:00",
                    "allDay": true,
                    "calendar": "生日"
                ],
                [
                    "id": "ev-2",
                    "title": "产品设计评审",
                    "start": "2026-11-30T14:00:00+08:00",
                    "end": "2026-11-30T15:00:00+08:00",
                    "calendar": "工作",
                    "location": "3 号会议室"
                ]
            ]
        )

        let card = ToolResultCard.from(tool: "calendar_search_events", result: result, calendar: fixedCalendar)
        #expect(card != nil)
        #expect(card?.headline == "11月28日 – 30日")
        #expect(card?.rows.count == 2)
        #expect(card?.rows[0].subtitle == nil)
        #expect(card?.rows[0].trailing == "11月28日 全天")
        #expect(card?.rows[1].subtitle == "3 号会议室")
        #expect(card?.rows[1].trailing == "11月30日 14:00")
    }

    @Test("Builds reminder list card without list subtitles or count filler")
    func reminderListCard() {
        let undatedResult = ExecutionResult(
            requestID: "req-rems-1",
            status: .completed,
            output: [
                ["id": "r-1", "title": "买牛奶", "list": "提醒"],
                ["id": "r-2", "title": "交电费", "list": "提醒"]
            ]
        )
        let undatedCard = ToolResultCard.from(tool: "reminders_list", result: undatedResult, calendar: fixedCalendar)
        #expect(undatedCard?.headline == "")
        #expect(undatedCard?.rows.allSatisfy { $0.subtitle == nil } == true)

        let sameDayResult = ExecutionResult(
            requestID: "req-rems-2",
            status: .completed,
            output: [
                ["id": "r-3", "title": "定时任务", "due": "2026-11-26T09:00:00+08:00", "list": "提醒"]
            ]
        )
        let sameDayCard = ToolResultCard.from(tool: "reminders_list", result: sameDayResult, calendar: fixedCalendar)
        #expect(sameDayCard?.headline == "11月26日 周四")
        #expect(sameDayCard?.rows.first?.subtitle == nil)
        #expect(sameDayCard?.rows.first?.trailing == "09:00")
    }

    @Test("Builds memory card without file name subtitle")
    func memorySaveCard() {
        let result = ExecutionResult(
            requestID: "req-mem-1",
            status: .completed,
            output: ["file": "MEMORY.md"]
        )
        let card = ToolResultCard.from(tool: "memory_save", arguments: ["content": "偏好深色模式"], result: result, calendar: fixedCalendar)
        #expect(card?.headline == "已记住")
        #expect(card?.title == "偏好深色模式")
        #expect(card?.subtitle == nil)
        #expect(card?.action?.target == "MEMORY.md")
    }

    @Test("Builds maps routes comparison card")
    func mapsRoutesCard() {
        let result = ExecutionResult(
            requestID: "req-map-1",
            status: .completed,
            output: [
                "origin": ["name": "公司", "latitude": 39.9, "longitude": 116.4],
                "destination": ["name": "首都机场", "latitude": 40.08, "longitude": 116.58],
                "routes": [
                    ["mode": "driving", "durationSeconds": 2400, "distanceMeters": 28500],
                    ["mode": "transit", "durationSeconds": 3600, "distanceMeters": 30000]
                ]
            ]
        )

        let card = ToolResultCard.from(tool: "maps_routes", result: result, calendar: fixedCalendar)
        #expect(card != nil)
        #expect(card?.kind == .mapRoutes)
        #expect(card?.headline == "公司 → 首都机场")
        #expect(card?.rows.count == 2)
        #expect(card?.rows.first?.trailing == "40 分钟")
        #expect(card?.action?.kind == .openMaps)
    }

    @Test("Builds messages draft card with recipient and body")
    func messagesDraftCard() {
        let result = ExecutionResult(
            requestID: "req-msg-1",
            status: .completed,
            targets: [TargetRef(kind: "messagesDraft", identifier: "13800138000")],
            output: [
                "recipient": "张三（13800138000）",
                "handle": "13800138000",
                "body": "晚上七点见",
                "note": "已打开草稿；若正文未预填，可直接粘贴"
            ]
        )

        let card = ToolResultCard.from(tool: "messages_prepare_draft", result: result, calendar: fixedCalendar)
        #expect(card != nil)
        #expect(card?.kind == .messagesDraft)
        #expect(card?.headline == "张三（13800138000）")
        #expect(card?.title == "晚上七点见")
        #expect(card?.footnote == nil)
        #expect(card?.action?.kind == .openMessagesDraft)
    }
}
