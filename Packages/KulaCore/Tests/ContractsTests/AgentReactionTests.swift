import XCTest
@testable import Contracts

final class AgentReactionTests: XCTestCase {
    func testThreeReplyModesAndComposedEmoji() {
        XCTAssertEqual(AgentReactionReply("你好 😊").text, "你好 😊")
        XCTAssertNil(AgentReactionReply("你好 😊").emoji)
        for emoji in ["😊", "❤️", "👍🏽", "👩‍💻", "🇨🇳", "1️⃣", "👨‍👩‍👧‍👦"] {
            let only = AgentReactionReply("<asky-reaction>\(emoji)</asky-reaction>")
            XCTAssertEqual(only.emoji, emoji)
            XCTAssertEqual(only.text, "")
            let both = AgentReactionReply("<asky-reaction>\(emoji)</asky-reaction>\r\n这是回答。")
            XCTAssertEqual(both.emoji, emoji)
            XCTAssertEqual(both.text, "这是回答。")
        }
    }

    func testMalformedAndQuotedMarkersRemainText() {
        for source in [
            "<asky-reaction>hello</asky-reaction>", "<asky-reaction>😊😊</asky-reaction>",
            "<asky-reaction>1</asky-reaction>", "<asky-reaction></asky-reaction>",
            "<asky-reaction>😊", "<asky-reaction>😊</asky-reaction>同一行",
            "```xml\n<asky-reaction>😊</asky-reaction>\n```",
            "示例：\n<asky-reaction>😊</asky-reaction>"
        ] {
            XCTAssertNil(AgentReactionReply(source).emoji)
            XCTAssertEqual(AgentReactionReply(source).text, source)
        }
    }

    func testReactionPreservesFormBody() {
        let form = "```asky-form\n{\"title\":\"选一个\"}\n```"
        XCTAssertEqual(AgentReactionReply("<asky-reaction>👍</asky-reaction>\n" + form).text, form)
    }
}
