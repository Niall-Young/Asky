import AppKit
import Contracts
import LocalStore

extension AgentReplyRegression {
    static func reactionRegression(app: AppModel, capture: Bool) async throws {
        let store = ConversationStore(app.store)
        let cid = try store.create(title: "表情回应回归")
        let model = AgentModel(app: app)
        let cases: [(String, String, String?, String?)] = [
            ("你好", "你好，有什么可以帮你？", nil, "你好，有什么可以帮你？"),
            ("你真棒", "<asky-reaction>😊</asky-reaction>", "😊", nil),
            ("谢谢！顺便告诉我 2 + 2 是多少", "<asky-reaction>❤️</asky-reaction>\n2 + 2 = 4。", "❤️", "2 + 2 = 4。")
        ]
        for (index, sample) in cases.enumerated() {
            let user = try store.append(conversationID: cid, role: "user", text: sample.0)
            model.open(cid)
            let task = "reaction-\(index)"
            model.beginResponse(taskID: task)
            model.handle(.textDelta(taskID: task, sample.1), conversationID: cid)
            precondition(model.items.last?.agentReaction == nil, "No partial reaction while streaming")
            model.handle(.message(taskID: task, sample.1), conversationID: cid)
            model.handle(.taskState(taskID: task, .completed), conversationID: cid)
            model.finishTask(conversationID: cid)
            precondition(!model.isRunning && model.streaming.isEmpty)
            precondition(model.items.first { $0.id == user.id }?.agentReaction == sample.2)
            let replies = model.items.filter { $0.responseID == task && $0.kind == .assistant }
            precondition(replies.map(\.text) == (sample.3.map { [$0] } ?? []), "Only textual replies create an assistant bubble")
            model.open(cid)
            precondition(model.items.first { $0.id == user.id }?.agentReaction == sample.2, "History preserves reactions")
            precondition(model.items.allSatisfy { !$0.text.contains("<asky-reaction>") })
            if capture {
                let controller = AgentWindowController(model: model, presentation: WindowPresentation())
                controller.show()
                guard let window = NSApp.windows.first(where: { String(describing: type(of: $0)) == "AgentWindow" && $0.isVisible }) else { fatalError("Missing reaction preview window") }
                for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    window.appearance = NSAppearance(named: appearance)
                    try await Task.sleep(for: .milliseconds(700))
                    window.contentView?.layoutSubtreeIfNeeded()
                    let process = Process()
                    process.executableURL = URL(filePath: "/usr/sbin/screencapture")
                    process.arguments = ["-x", "-o", "-l", String(window.windowNumber), "build/reactions-\(index)-\(name).png"]
                    try process.run(); process.waitUntilExit()
                    precondition(process.terminationStatus == 0)
                }
                window.orderOut(nil)
            }
        }
        for state in [AgentTaskState.cancelled, .failed, .pendingVerification] {
            let user = try store.append(conversationID: cid, role: "user", text: "取消这次回应")
            model.open(cid)
            model.beginResponse(taskID: "interrupted")
            model.handle(.message(taskID: "interrupted", "<asky-reaction>👍</asky-reaction>"), conversationID: cid)
            model.handle(.taskState(taskID: "interrupted", state), conversationID: cid)
            model.finishTask(conversationID: cid)
            precondition(store.message(user.id, conversationID: cid)?.presentation?.agentReaction == nil)
        }
        let longID = try store.create(title: "表情目标被分页移出")
        let longUser = try store.append(conversationID: longID, role: "user", text: "谢谢")
        model.open(longID)
        model.beginResponse(taskID: "long-reaction")
        for index in 0..<125 {
            let request = ActionRequest(requestID: "reaction-tool-\(index)", tool: "notes_search",
                arguments: [:], origin: .agent(sessionID: longID), intent: .explicitRequest)
            model.handle(.toolCall(taskID: "long-reaction", request), conversationID: longID)
            model.handle(.toolResult(taskID: "long-reaction", ExecutionResult(requestID: request.requestID, status: .completed)), conversationID: longID)
        }
        precondition(!model.items.contains { $0.id == longUser.id })
        model.handle(.message(taskID: "long-reaction", "<asky-reaction>👍🏽</asky-reaction>"), conversationID: longID)
        model.handle(.taskState(taskID: "long-reaction", .completed), conversationID: longID)
        model.finishTask(conversationID: longID)
        precondition(store.message(longUser.id, conversationID: longID)?.presentation?.agentReaction == "👍🏽")
        let other = try store.create(title: "不能贴到历史消息")
        model.open(other)
        model.beginResponse(taskID: "missing-target")
        model.handle(.message(taskID: "missing-target", "<asky-reaction>😊</asky-reaction>"), conversationID: other)
        model.handle(.taskState(taskID: "missing-target", .completed), conversationID: other)
        model.finishTask(conversationID: other)
        precondition(model.items.last?.text == "😊", "Missing target falls back to a visible reply")
        print("Reaction regression passed: all three modes, completed-only presentation, history, cancellation and target isolation")
    }
}
