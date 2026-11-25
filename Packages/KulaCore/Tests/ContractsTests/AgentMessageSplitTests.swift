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
        千岛湖那页改好了，现在是 22 张照片，三组并列。
        <asky-split/>
        霞浦那页还在做，做好了再拿给你看。
        """
        #expect(AgentMessageSplit.split(input) == [
            "千岛湖那页改好了，现在是 22 张照片，三组并列。",
            "霞浦那页还在做，做好了再拿给你看。"
        ])
    }

    @Test("Splits on inline markers outside code fences")
    func splitOnInlineMarker() {
        let input = "第一件事搞定了。<asky-split/>另一件事还在跑。"
        #expect(AgentMessageSplit.split(input) == [
            "第一件事搞定了。",
            "另一件事还在跑。"
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

    @Test("Keeps multi-paragraph analysis and structured digests in a single bubble without explicit markers")
    func keepsStructuredLongReplyIntact() {
        let digest = """
        ### 大厂 AI 设计工程

        1. AWS 给编码 Agent 加了沙箱与决策小模型，用来做低延迟路由。
        2. 国产巨头也在跟进 Code + Work 两条线。

        ### AI 公司动态

        3. GPT-6.2 进了日常对话页。
        4. Anthropic 企业零留存安全方案进入公测。
        """
        #expect(AgentMessageSplit.split(digest) == [digest])

        let multiParagraphAnalysis = (1...6).map { "第 \($0) 段连贯分析内容。" }.joined(separator: "\n\n")
        #expect(AgentMessageSplit.split(multiParagraphAnalysis) == [multiParagraphAnalysis])
    }

    @Test("Does not split replies containing asky-form even if markers appear")
    func keepsFormReplyIntact() {
        let input = """
        还需要补一下会议时间：
        <asky-split/>
        ```asky-form
        {"title":"会议安排"}
        {"id":"start","type":"time","label":"开始时间","required":true}
        ```
        """
        let parts = AgentMessageSplit.split(input)
        #expect(parts.count == 1)
        #expect(!parts[0].contains(AgentMessageSplit.marker))
        #expect(parts[0].contains("```asky-form"))
    }
}
