import Foundation
import Testing
import Contracts
@testable import LocalStore

@Suite struct AgentReactionStorageTests {
    @Test func legacyPresentationStillDecodes() throws {
        let legacy = Data(#"{"needsPermissionSettings":false,"quotes":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(MessagePresentation.self, from: legacy)
        #expect(decoded.agentReaction == nil)
        #expect(decoded.quotes == [])
    }

    @Test func reactionSurvivesReopeningWithoutChangingUserContent() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try LocalStore(root: root)
        let store = ConversationStore(database)
        let cid = try store.create(title: "Reaction")
        let user = try store.append(conversationID: cid, role: "user", text: "你真棒",
            presentation: MessagePresentation(submittedFormValues: ["answer": ["yes"]]))
        var presentation = user.presentation!
        presentation.agentReaction = "👍🏽"
        try store.updateMessage(user.id, conversationID: cid, text: user.text, presentation: presentation)
        let reopened = ConversationStore(try LocalStore(root: root))
        let saved = reopened.message(user.id, conversationID: cid)
        #expect(saved?.text == "你真棒")
        #expect(saved?.role == "user")
        #expect(saved?.presentation?.agentReaction == "👍🏽")
        #expect(saved?.presentation?.submittedFormValues == ["answer": ["yes"]])
        #expect(reopened.timeline(limit: 40).first?.presentation?.agentReaction == "👍🏽")
    }
}
