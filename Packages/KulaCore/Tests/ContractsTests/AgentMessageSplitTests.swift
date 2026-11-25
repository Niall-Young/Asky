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

    @Test("Auto-splits multi-paragraph replies into natural chat bubbles")
    func autoSplitsParagraphs() {
        let input = """
        百度主站直接访问 baidu.com 就行。

        主要几个入口：
        - 搜索引擎：https://www.baidu.com
        - 百度智能云：https://cloud.baidu.com
        - 百度开发者中心：https://developer.baidu.com

        平时查资料用主站，接 API 或看文档就进后面两个。
        """
        #expect(AgentMessageSplit.split(input) == [
            "百度主站直接访问 baidu.com 就行。",
            "主要几个入口：\n- 搜索引擎：https://www.baidu.com\n- 百度智能云：https://cloud.baidu.com\n- 百度开发者中心：https://developer.baidu.com",
            "平时查资料用主站，接 API 或看文档就进后面两个。"
        ])
    }

    @Test("Keeps colon lead-in attached to following list, code, or table")
    func keepsColonLeadInAttached() {
        let input = """
        主要几个入口：

        - 搜索引擎：https://www.baidu.com
        - 百度开发者中心：https://developer.baidu.com
        """
        #expect(AgentMessageSplit.split(input) == [input])
    }

    @Test("Keeps loose list items in one bubble")
    func keepsLooseListTogether() {
        let input = """
        - 第一项说明

        - 第二项说明

        - 第三项说明
        """
        #expect(AgentMessageSplit.split(input) == [input])
    }

    @Test("Keeps headings attached to following content and citations attached to images")
    func keepsHeadingsAndImageCitationsAttached() {
        let headingReply = """
        ### 已启动 Claude Code

        - 项目：**Asky**
        - 打开方式：CLI 终端窗口
        """
        #expect(AgentMessageSplit.split(headingReply) == [headingReply])

        let imageReply = """
        水豚长得有点像放大的豚鼠。

        ![水豚](https://example.com/capybara.jpg)

        [来源](https://example.com/article)
        """
        #expect(AgentMessageSplit.split(imageReply) == [
            "水豚长得有点像放大的豚鼠。",
            "![水豚](https://example.com/capybara.jpg)\n\n[来源](https://example.com/article)"
        ])
    }

    @Test("Does not auto-split replies containing asky-form")
    func keepsFormReplyIntact() {
        let input = """
        还需要补一下会议时间：

        ```asky-form
        {"title":"会议安排"}
        {"id":"start","type":"time","label":"开始时间","required":true}
        ```
        """
        #expect(AgentMessageSplit.split(input) == [input])
    }

    @Test("Caps auto-split paragraphs at maxBubbles")
    func capsAutoSplitParagraphs() {
        let input = (1...6).map { "第 \($0) 段自然聊天内容。" }.joined(separator: "\n\n")
        let parts = AgentMessageSplit.split(input)
        #expect(parts.count == AgentMessageSplit.maxBubbles)
        #expect(parts.first == "第 1 段自然聊天内容。")
        #expect(parts.last?.contains("第 6 段自然聊天内容。") == true)
    }
}
