import Testing
import Foundation
import Contracts
@testable import Adapters

@Suite struct AdapterPolicyTests {
    @Test func appleScriptLiteralEscapesInjection() {
        #expect(AppleScript.literal(#"a"b\c"#) == #""a\"b\\c""#)
        let hostile = #"" & (do shell script "rm -rf ~") & ""#
        let lit = AppleScript.literal(hostile)
        // Every quote inside must be escaped, so the literal cannot be terminated early.
        let inner = lit.dropFirst().dropLast()
        var prev: Character = " "
        for ch in inner { if ch == "\"" { #expect(prev == "\\") }; prev = ch }
    }

    @Test func parsesRecordsAndDropsMalformed() {
        let s = "1\u{1F}2\u{1F}t\u{1F}u\u{1E}bad\u{1E}3\u{1F}4\u{1F}\u{1F}x"
        let r = AppleScript.parseRecords(s, fields: 4)
        #expect(r == [["1", "2", "t", "u"], ["3", "4", "", "x"]])
        #expect(AppleScript.mapError(code: -1743, message: "").code == .permissionDenied)
    }

    @Test func messagesHandleAndDraftURL() throws {
        #expect(MessagesDraftTool.isValidHandle("+86 138-0000-0000"))
        #expect(MessagesDraftTool.isValidHandle("a@b.com"))
        #expect(!MessagesDraftTool.isValidHandle("rm -rf"))
        let u = try #require(MessagesDraftTool.draftURL(handle: "+86 (138) 0000", body: "晚上7点见&带伞"))
        #expect(u.absoluteString.hasPrefix("sms:%2B861380000&body="))
        #expect(!u.absoluteString.contains("&带"))
        #expect(u.absoluteString.components(separatedBy: "&").count == 2)
    }

    @Test func notesHTMLIsEscaped() {
        #expect(NotesBridge.htmlParagraphs("<b>x</b>\n\nA&B") == "<div>&lt;b&gt;x&lt;/b&gt;</div><div><br></div><div>A&amp;B</div>")
    }

    @Test func registryFollowsExposurePolicy() {
        let tools = NativeTools(notesFolders: { [] }).adapters(memory: nil).map(\.definition)
        #expect(Set(tools.map(\.name)).count == tools.count)
        for t in tools {
            if t.effect == .write { #expect(t.writeKind != nil && t.confirmation != .never, "\(t.name)") }
            if ["messages_prepare_draft", "notes_append", "calendar_update_event"].contains(t.name) {
                #expect(t.confirmation == .explicitDirectOtherwiseConfirm)
            } else if t.writeKind == .modify || t.writeKind == .delete || t.writeKind == .handoff {
                #expect(t.confirmation == .always, "\(t.name)")
            }
            if [.shortcuts, .memory, .clipboard, .terminal].contains(t.source) { #expect(!t.externallyExposable, "\(t.name)") }
            #expect(t.inputSchema["additionalProperties"] == false, "\(t.name)")
        }
        #expect(!tools.contains { $0.name.contains("send") })
    }
}
