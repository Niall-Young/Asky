import Testing
@testable import Contracts

@Suite("AgentMessageSplit")
struct AgentMessageSplitTests {
    @Test("Plain single message stays intact")
    func plainMessage() {
        #expect(AgentMessageSplit.split("明早六点五十的闹钟已经定好。") == ["明早六点五十的闹钟已经定好。"])
    }

    @Test("Splits on standalone marker lines")
    func splitOnMarker() {
        let input = """
        好了，明早六点五十的提醒已经定好。
        <asky-split/>
        到点会响，你可以安心休息了。
        """
        #expect(AgentMessageSplit.split(input) == [
            "好了，明早六点五十的提醒已经定好。",
            "到点会响，你可以安心休息了。"
        ])
    }

    @Test("Ignores marker inside fenced code blocks")
    func ignoresMarkerInCodeFence() {
        let input = """
        示例用法：
        ```markdown
        第一条
        <asky-split/>
        第二条
        ```
        """
        #expect(AgentMessageSplit.split(input) == [input])
    }

    @Test("Caps maximum number of bubbles")
    func capsBubbles() {
        let input = (1...6).map { "消息 \($0)" }.joined(separator: "\n<asky-split/>\n")
        let parts = AgentMessageSplit.split(input)
        #expect(parts.count == AgentMessageSplit.maxBubbles)
        #expect(parts.first == "消息 1")
        #expect(parts.last?.contains("消息 6") == true)
    }

    @Test("Strips markers from pre-tool narration")
    func stripsNarrationMarkers() {
        #expect(AgentMessageSplit.strippingMarkers("我来帮你查一下<asky-split/>") == "我来帮你查一下")
    }
}
