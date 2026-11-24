import Foundation
import Testing
@testable import LocalStore
@testable import Contracts

@Suite("ToolResultCardStorage")
struct ToolResultCardStorageTests {
    @Test("Persists and restores resultCard in MessagePresentation")
    func roundTripsResultCard() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try LocalStore(root: dir)
        let conversations = ConversationStore(store)
        let cid = try conversations.create(title: "测试卡片")

        let card = ToolResultCard(
            id: "req-1",
            kind: .reminder,
            source: .reminders,
            categoryTitle: "提醒事项",
            headline: "06:50",
            title: "起床",
            subtitle: "11月22日 周日 · 提醒事项",
            action: ToolResultCard.Action(kind: .openReminders, label: "查看提醒事项")
        )
        let presentation = MessagePresentation(
            responseID: "task-1",
            toolName: "reminders_create",
            toolStatus: .completed,
            resultCard: card
        )

        let saved = try conversations.append(
            conversationID: cid,
            role: "tool",
            text: "调用 reminders_create",
            id: "req-1",
            presentation: presentation
        )

        let loaded = conversations.message(saved.id, conversationID: cid)
        #expect(loaded?.presentation?.resultCard == card)
    }
}
