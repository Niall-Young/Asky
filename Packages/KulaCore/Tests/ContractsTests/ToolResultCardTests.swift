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
        #expect(card?.categoryTitle == "工作日程")
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
        #expect(card?.categoryTitle == "提醒事项")
        #expect(card?.headline == "06:50")
        #expect(card?.title == "起床")
        #expect(card?.subtitle == "11月22日 周日")
        #expect(card?.metadata.isEmpty == true)
        #expect(card?.action?.kind == .openReminders)
        #expect(card?.action?.label == "查看事项")

        let workResult = ExecutionResult(
            requestID: "req-rem-work",
            status: .completed,
            readback: [
                "id": "r-2",
                "title": "提交季度项目复盘报告",
                "due": "2026-11-30T09:00:00+08:00",
                "list": "工作"
            ]
        )
        let workCard = ToolResultCard.from(tool: "reminders_create", result: workResult, calendar: fixedCalendar)
        #expect(workCard?.categoryTitle == "工作事项提醒")
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
        #expect(card?.categoryTitle == "生日日程")
        #expect(card?.headline == "11月28日 周六")
        #expect(card?.rows.count == 1)
        #expect(card?.rows.first?.title == "何瑞兆雪的24岁生日")
        #expect(card?.rows.first?.subtitle == nil)
        #expect(card?.rows.first?.trailing == "全天")
        #expect(card?.rows.first?.badge == "全天")
        #expect(card?.rows.first?.dateLabel == "11月28日 周六")
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
        #expect(card?.categoryTitle == "日历日程")
        #expect(card?.headline == "11月28日 – 30日")
        #expect(card?.rows.count == 2)
        #expect(card?.rows[0].subtitle == nil)
        #expect(card?.rows[0].trailing == "11月28日 全天")
        #expect(card?.rows[1].subtitle == "3 号会议室")
        #expect(card?.rows[1].trailing == "11月30日 14:00")
        #expect(card?.rows[1].badge == "14:00 - 15:00")
        #expect(card?.rows[1].dateLabel == "11月30日 周一")
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
        #expect(sameDayCard?.rows.first?.dateLabel == "11月26日 周四")
        #expect(sameDayCard?.rows.first?.badge == nil)
        #expect(sameDayCard?.action?.label == "查看事项")

        let customListResult = ExecutionResult(
            requestID: "req-rems-3",
            status: .completed,
            output: [
                ["id": "r-4", "title": "购买全脂牛奶和燕麦片", "list": "购物清单"]
            ]
        )
        let customListCard = ToolResultCard.from(tool: "reminders_list", result: customListResult, calendar: fixedCalendar)
        #expect(customListCard?.categoryTitle == "购物清单事项提醒")
        #expect(customListCard?.rows.first?.subtitle == nil)
        #expect(customListCard?.rows.first?.badge == "购物清单")
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

        let corrected = ToolResultCard.from(tool: "memory_correct", arguments: ["content": "工作会议尽量安排在下午两点之后"], result: result, calendar: fixedCalendar)
        #expect(corrected?.categoryTitle == "更新记忆")
        #expect(corrected?.headline == "记忆已更新")
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
        #expect(card?.categoryTitle == "路线规划")
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

    @Test("Normalizes legacy persisted note, reminder, memory, and mapPlaces cards for display")
    func normalizesLegacyNoteReminderMemoryAndPlacesCards() {
        let legacyNote = ToolResultCard(
            id: "note-legacy",
            kind: .note,
            source: .notes,
            categoryTitle: "备忘录",
            headline: "asky",
            title: "定时任务",
            subtitle: "iCloud › Notes",
            action: .init(kind: .openNotes, label: "打开备忘录", target: "n-1")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(legacyNote.headline == "asky")
        #expect(legacyNote.title == "定时任务")
        #expect(legacyNote.subtitle == nil)
        #expect(legacyNote.metadata.isEmpty)

        let earliestLegacyNote = ToolResultCard(
            id: "note-v1",
            kind: .note,
            source: .notes,
            categoryTitle: "备忘录",
            headline: "asky",
            title: "",
            subtitle: "iCloud › Notes",
            footnote: "定时任务",
            action: .init(kind: .openNotes, label: "打开备忘录", target: "n-1")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(earliestLegacyNote.title == "定时任务")
        #expect(earliestLegacyNote.subtitle == nil)
        #expect(earliestLegacyNote.footnote == nil)

        let legacyReminder = ToolResultCard(
            id: "rem-legacy",
            kind: .reminder,
            source: .reminders,
            categoryTitle: "提醒事项",
            headline: "09:00",
            title: "定时任务（内容待定）",
            subtitle: "11月26日 周四 · 提醒",
            metadata: ["每天 9:00 提醒。具体要做什么还没定，确定后可修改标题或拆成多条提醒。"],
            action: .init(kind: .openReminders, label: "查看提醒事项")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(legacyReminder.headline == "09:00")
        #expect(legacyReminder.title == "定时任务（内容待定）")
        #expect(legacyReminder.subtitle == "11月26日 周四")
        #expect(legacyReminder.metadata.isEmpty)

        let customListReminder = ToolResultCard(
            id: "rem-custom-list",
            kind: .reminder,
            source: .reminders,
            categoryTitle: "提醒事项",
            headline: "09:00",
            title: "交周报",
            subtitle: "11月26日 周四 · 工作",
            metadata: ["备注"],
            action: .init(kind: .openReminders, label: "查看提醒事项")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(customListReminder.subtitle == "11月26日 周四 · 工作")
        #expect(customListReminder.metadata.isEmpty)

        let legacyMemory = ToolResultCard(
            id: "mem-legacy",
            kind: .memory,
            source: .memory,
            categoryTitle: "记忆",
            headline: "已记住",
            title: "偏好深色模式",
            subtitle: "MEMORY.md",
            action: .init(kind: .openMemoryFile, label: "查看记忆", target: "MEMORY.md")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(legacyMemory.subtitle == nil)

        let legacyPlaces = ToolResultCard(
            id: "places-legacy",
            kind: .mapPlaces,
            source: .maps,
            categoryTitle: "地点",
            headline: "2 个地点",
            rows: [
                .init(id: "p1", title: "首都机场", subtitle: "顺义区"),
                .init(id: "p2", title: "大兴机场", subtitle: "大兴区")
            ],
            action: .init(kind: .openMaps, label: "在地图中查看")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(legacyPlaces.headline == "")
        #expect(legacyPlaces.rows.count == 2)
    }

    @Test("Normalizes legacy persisted calendar schedule, all-day event, and reminder list cards without altering new cards")
    func normalizesLegacyScheduleAndReminderListCards() {
        let legacySingleSchedule = ToolResultCard(
            id: "sched-legacy-1",
            kind: .calendarSchedule,
            source: .calendar,
            categoryTitle: "日历日程",
            headline: "1 个日程",
            rows: [
                .init(id: "ev-1", title: "何瑞兆雪的24岁生日", subtitle: "11月28日 · 生日", trailing: "全天")
            ],
            action: .init(kind: .openCalendar, label: "查看日历", target: "2026-11-28T00:00:00+08:00")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(legacySingleSchedule.headline == "11月28日 周六")
        #expect(legacySingleSchedule.rows.first?.subtitle == nil)
        #expect(legacySingleSchedule.rows.first?.trailing == "全天")

        let legacyMultiSchedule = ToolResultCard(
            id: "sched-legacy-2",
            kind: .calendarSchedule,
            source: .calendar,
            categoryTitle: "日历日程",
            headline: "2 个日程",
            rows: [
                .init(id: "ev-1", title: "何瑞兆雪的24岁生日", subtitle: "11月28日 · 生日", trailing: "全天"),
                .init(id: "ev-2", title: "产品设计评审", subtitle: "11月30日 · 工作", trailing: "14:00–15:00")
            ],
            action: .init(kind: .openCalendar, label: "查看日历", target: "2026-11-28T00:00:00+08:00")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(legacyMultiSchedule.headline == "11月28日 – 30日")
        #expect(legacyMultiSchedule.rows[0].subtitle == nil)
        #expect(legacyMultiSchedule.rows[0].trailing == "11月28日 全天")
        #expect(legacyMultiSchedule.rows[1].subtitle == nil)
        #expect(legacyMultiSchedule.rows[1].trailing == "11月30日 14:00")

        let modernScheduleWithLocation = ToolResultCard(
            id: "sched-modern",
            kind: .calendarSchedule,
            source: .calendar,
            categoryTitle: "日历日程",
            headline: "11月30日 周一",
            rows: [
                .init(id: "ev-2", title: "产品设计评审", subtitle: "3 号会议室", trailing: "14:00–15:00")
            ],
            action: .init(kind: .openCalendar, label: "查看日历", target: "2026-11-30T14:00:00+08:00")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(modernScheduleWithLocation.headline == "11月30日 周一")
        #expect(modernScheduleWithLocation.rows.first?.subtitle == "3 号会议室")

        let legacyAllDay = ToolResultCard(
            id: "cal-allday-legacy",
            kind: .calendarEvent,
            source: .calendar,
            categoryTitle: "日历",
            headline: "全天",
            title: "何瑞兆雪的24岁生日",
            subtitle: "11月28日 周六 · 生日",
            action: .init(kind: .openCalendar, label: "查看日历", target: "2026-11-28T00:00:00+08:00")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(legacyAllDay.headline == "11月28日 周六")
        #expect(legacyAllDay.subtitle == "全天 · 生日")

        let legacyReminderList = ToolResultCard(
            id: "remlist-legacy",
            kind: .reminderList,
            source: .reminders,
            categoryTitle: "提醒事项",
            headline: "2 条待办",
            rows: [
                .init(id: "r1", title: "买牛奶", subtitle: "提醒", trailing: "11月26日 09:00"),
                .init(id: "r2", title: "交电费", subtitle: "提醒", trailing: "11月26日 18:00")
            ],
            action: .init(kind: .openReminders, label: "查看提醒事项")
        ).normalizedForDisplay(calendar: fixedCalendar)
        #expect(legacyReminderList.headline == "11月26日")
        #expect(legacyReminderList.rows.allSatisfy { $0.subtitle == nil })
        #expect(legacyReminderList.rows[0].trailing == "09:00")
        #expect(legacyReminderList.rows[1].trailing == "18:00")
    }
}
