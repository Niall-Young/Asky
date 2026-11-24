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

    @Test("Builds reminder card using readback due time and list")
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

        let card = ToolResultCard.from(tool: "reminders_create", result: result, calendar: fixedCalendar)
        #expect(card != nil)
        #expect(card?.kind == .reminder)
        #expect(card?.headline == "06:50")
        #expect(card?.title == "起床")
        #expect(card?.subtitle?.contains("11月22日") == true)
        #expect(card?.action?.kind == .openReminders)
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
