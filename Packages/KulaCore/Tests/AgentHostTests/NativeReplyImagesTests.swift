import Foundation
import Testing
import Contracts
@testable import AgentHost

@Suite struct NativeReplyImagesTests {
    @Test func parsesAndRemovesImagesWithoutChangingProseOrCode() throws {
        let markdown = """
        山峰 **正文** ![山峰](https://example.com/a_(b).jpg "标题") 尾巴。
        ![引用][photo]
        [![](https://example.com/empty.jpg)](https://example.com/source)

        [photo]: https://example.com/ref.jpg
        `![代码](https://example.com/code.jpg)`
        ```markdown
        ![围栏](https://example.com/fence.jpg)
        ```
        \\![转义](https://example.com/escaped.jpg)
        """
        let images = NativeReplyImages.images(in: markdown)
        #expect(images.map(\.url.absoluteString) == ["https://example.com/a_(b).jpg", "https://example.com/ref.jpg", "https://example.com/empty.jpg"])
        let removed = NativeReplyImages.removing(Set(images.map(\.url)), from: markdown)
        #expect(removed.contains("山峰 **正文**  尾巴。"))
        #expect(removed.contains("`![代码]"))
        #expect(removed.contains("![围栏]"))
        #expect(removed.contains("\\![转义]"))
        #expect(NativeReplyImages.images(in: removed).isEmpty)
    }

    @Test func filteringKeepsSiblingContentAndRemovesEmptyLinkWrappers() {
        let a = URL(string: "https://example.com/a")!, b = URL(string: "https://example.com/b")!
        let text = "![a](\(a))\n[来源](https://example.com/source) [![b](\(b))](https://example.com/link)"
        #expect(NativeReplyImages.removing([a,b], from: text) == "\n[来源](https://example.com/source) ")
        let nested = "![outer ![first](\(a)) ![second](\(b))]"
        #expect(Set(NativeReplyImages.images(in: nested).map(\.url)) == [a,b])
        #expect(NativeReplyImages.removing([b], from: nested) == "![outer ![first](\(a)) ]")
    }

    @Test func onlySuccessfulImageEvidenceAndExplicitUserURLsAreAllowed() {
        func tool(_ value: JSONValue) -> JSONValue {
            ["role": "tool", "content": .string(String(decoding: value.canonicalData(), as: UTF8.self))]
        }
        let messages: [JSONValue] = [
            ["role": "assistant", "content": "![假的](https://example.com/fake.jpg)"],
            tool(["status": "completed", "output": ["images": [["url": "https://example.com/photo.jpg"]],
                "text": "正文 ![原图](https://example.com/body.jpg)"]]),
            tool(["status": "failed", "output": ["images": [["url": "https://example.com/failure.jpg"]]]])]
        let urls = NativeReplyImages.allowedURLs(messages: messages, userText: "用 https://example.com/user.jpg")
        #expect(Set(urls.map(\.absoluteString)) == ["https://example.com/photo.jpg", "https://example.com/body.jpg", "https://example.com/user.jpg"])
    }

    @Test func removedPhotoDoesNotLeaveAnOrphanedSourceLink() {
        let text = "正文\n\n![图](https://example.com/bad.jpg)\n\n[来源](https://example.com/page)\n\n后文 [来源](https://example.com/fact)"
        let clean = NativeReplyImages.removing([URL(string: "https://example.com/bad.jpg")!], from: text)
        #expect(!clean.contains("https://example.com/page"))
        #expect(clean.contains("后文 [来源](https://example.com/fact)"))
    }
}
