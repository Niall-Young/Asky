import Foundation
import Testing
import ToolService

struct SyntaxHighlighterTests {
    /// Returns the kind that covers the first occurrence of `token`, requiring the span to match it exactly.
    private func kind(of token: String, in text: String, _ language: SyntaxLanguage,
                      occurrence: Int = 0) -> SyntaxHighlight.Kind? {
        let source = text as NSString
        var range = source.range(of: token)
        for _ in 0..<occurrence {
            let start = range.location + range.length
            range = source.range(of: token, range: NSRange(location: start, length: source.length - start))
        }
        guard range.location != NSNotFound else { return nil }
        return SyntaxHighlighter.highlight(text, as: language).first { $0.range == range }?.kind
    }

    private func covered(_ token: String, in text: String, _ language: SyntaxLanguage) -> SyntaxHighlight.Kind? {
        let range = (text as NSString).range(of: token)
        return SyntaxHighlighter.highlight(text, as: language).first {
            NSIntersectionRange($0.range, range).length == range.length
        }?.kind
    }

    @Test(arguments: [
        ("main.swift", SyntaxLanguage.swift), ("App.TSX", .typescript), ("lib.rs", .rust), ("Dockerfile", .dockerfile),
        ("CMakeLists.txt", .cmake), ("config.yml", .yaml), ("fix.patch", .diff), ("index.vue", .html),
        ("settings.JSON", .json), (".zshrc", .shell), ("Makefile", .makefile), ("query.sql", .sql)
    ])
    func detectsLanguageFromFileName(_ name: String, _ language: SyntaxLanguage) {
        #expect(SyntaxLanguage(url: URL(filePath: "/tmp").appending(path: name)) == language)
    }

    @Test func detectsShebangAndSkipsProse() {
        let script = URL(filePath: "/tmp/deploy")
        #expect(SyntaxLanguage(url: script, text: "#!/usr/bin/env python3\nprint(1)") == .python)
        #expect(SyntaxLanguage(url: script, text: "#!/bin/zsh\necho hi") == .shell)
        #expect(SyntaxLanguage(url: script, text: "plain words") == nil)
        #expect(SyntaxLanguage(url: URL(filePath: "/tmp/notes.txt")) == nil)
        #expect(SyntaxLanguage(url: URL(filePath: "/tmp/table.csv")) == nil)
    }

    @Test func colorsSwiftTokens() {
        let text = """
        import Foundation
        // Greets someone
        @MainActor func greet(_ name: String, count: Int = 42) -> String {
            let value = "Hello, \\(name)"
            return value.isEmpty ? nil : format(value)
        }
        """
        #expect(kind(of: "import", in: text, .swift) == .keyword)
        #expect(kind(of: "// Greets someone", in: text, .swift) == .comment)
        #expect(kind(of: "@MainActor", in: text, .swift) == .attribute)
        #expect(kind(of: "greet", in: text, .swift) == .function)
        #expect(kind(of: "String", in: text, .swift) == .type)
        #expect(kind(of: "42", in: text, .swift) == .number)
        #expect(kind(of: "\"Hello, \\(name)\"", in: text, .swift) == .string)
        #expect(kind(of: "nil", in: text, .swift) == .literal)
        #expect(kind(of: "isEmpty", in: text, .swift) == nil)
    }

    @Test func keepsCommentsAndStringsSeparate() {
        let text = "let url = \"https://example.com\" // trailing\nlet tag = \"#not-comment\"\n/* block\n */ let x = 1"
        #expect(kind(of: "\"https://example.com\"", in: text, .swift) == .string)
        #expect(kind(of: "// trailing", in: text, .swift) == .comment)
        #expect(kind(of: "\"#not-comment\"", in: text, .swift) == .string)
        #expect(kind(of: "/* block\n */", in: text, .swift) == .comment)
        #expect(kind(of: "let", in: text, .swift, occurrence: 2) == .keyword)
    }

    @Test func colorsPythonAndShell() {
        let python = "@app.route('/')\ndef handler(request):\n    \"\"\"Doc\n    string\"\"\"\n    return f\"{request}\" # done\n"
        #expect(kind(of: "@app.route", in: python, .python) == .attribute)
        #expect(kind(of: "def", in: python, .python) == .keyword)
        #expect(kind(of: "\"\"\"Doc\n    string\"\"\"", in: python, .python) == .string)
        #expect(kind(of: "f\"{request}\"", in: python, .python) == .string)
        #expect(kind(of: "# done", in: python, .python) == .comment)

        let shell = "export PATH=\"$HOME/bin:$PATH\"\necho ${USER} $# done # note\nit's fine"
        #expect(kind(of: "export", in: shell, .shell) == .keyword)
        #expect(kind(of: "$#", in: shell, .shell) == .property)
        #expect(kind(of: "${USER}", in: shell, .shell) == .property)
        #expect(kind(of: "# note", in: shell, .shell) == .comment)
        #expect(covered("'s fine", in: shell, .shell) == nil)
    }

    @Test func colorsDataAndConfigFiles() {
        let json = "{\n  \"name\": \"Asky\",\n  \"count\": 3,\n  \"ok\": true\n}"
        #expect(kind(of: "\"name\"", in: json, .json) == .property)
        #expect(kind(of: "\"Asky\"", in: json, .json) == .string)
        #expect(kind(of: "3", in: json, .json) == .number)
        #expect(kind(of: "true", in: json, .json) == .literal)

        let yaml = "# config\nserver:\n  - host: example.com\n    url: http://a.b\n    enabled: yes\n"
        #expect(kind(of: "server", in: yaml, .yaml) == .property)
        #expect(kind(of: "host", in: yaml, .yaml) == .property)
        #expect(kind(of: "yes", in: yaml, .yaml) == .literal)
        #expect(covered("//a.b", in: yaml, .yaml) == nil)

        let toml = "[package]\nname = \"asky\" # comment\nversion = 1\n"
        #expect(kind(of: "[package]", in: toml, .toml) == .type)
        #expect(kind(of: "name", in: toml, .toml) == .property)
        #expect(kind(of: "# comment", in: toml, .toml) == .comment)
    }

    @Test func colorsMarkupStylesAndDiffs() {
        let html = "<!-- note -->\n<div class=\"box\">&amp;<script>const a = 1</script>\n<style>.box { color: red; }</style>"
        #expect(kind(of: "<!-- note -->", in: html, .html) == .comment)
        #expect(kind(of: "<div", in: html, .html) == .tag)
        #expect(kind(of: "class", in: html, .html) == .property)
        #expect(kind(of: "\"box\"", in: html, .html) == .string)
        #expect(kind(of: "&amp;", in: html, .html) == .literal)
        #expect(kind(of: "const", in: html, .html) == .keyword)
        #expect(kind(of: ".box", in: html, .html) == .attribute)
        #expect(kind(of: "color", in: html, .html) == .property)

        let css = "a:hover, .card #main {\n  margin: 4px;\n  background: #fff;\n  --gap: rgb(0 0 0);\n}"
        #expect(kind(of: ":hover", in: css, .css) == .keyword)
        #expect(kind(of: "#main", in: css, .css) == .attribute)
        #expect(kind(of: "margin", in: css, .css) == .property)
        #expect(kind(of: "4px", in: css, .css) == .number)
        #expect(kind(of: "#fff", in: css, .css) == .number)
        #expect(kind(of: "--gap", in: css, .css) == .property)
        #expect(kind(of: "rgb", in: css, .css) == .function)

        let diff = "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n context"
        #expect(kind(of: "@@ -1 +1 @@", in: diff, .diff) == .meta)
        #expect(kind(of: "-old", in: diff, .diff) == .deleted)
        #expect(kind(of: "+new", in: diff, .diff) == .inserted)
        #expect(kind(of: "--- a/x", in: diff, .diff) == .keyword)
    }

    @Test func coversOtherLanguageFamilies() {
        let c = "#include <stdio.h>\nint main(void) { printf(\"%d\", 0x1F); return 0; }"
        #expect(kind(of: "#include", in: c, .c) == .attribute)
        #expect(kind(of: "<stdio.h>", in: c, .c) == .string)
        #expect(kind(of: "int", in: c, .c) == .type)
        #expect(kind(of: "0x1F", in: c, .c) == .number)

        let rust = "#[derive(Debug)]\nfn first<'a>(s: &'a str) -> Option<&'a str> { println!(\"{}\", 'x'); None }"
        #expect(kind(of: "#[derive(Debug)]", in: rust, .rust) == .attribute)
        #expect(kind(of: "'a", in: rust, .rust) == .attribute)
        #expect(kind(of: "println!", in: rust, .rust) == .function)
        #expect(kind(of: "'x'", in: rust, .rust) == .string)

        let sql = "SELECT name FROM users WHERE id = 1; -- latest"
        #expect(kind(of: "SELECT", in: sql, .sql) == .keyword)
        #expect(kind(of: "-- latest", in: sql, .sql) == .comment)

        let ts = "const total: number = items.map((x) => x * 2) // sum\nconst s = `a\nb`"
        #expect(kind(of: "number", in: ts, .typescript) == .type)
        #expect(kind(of: "map", in: ts, .typescript) == .function)
        #expect(kind(of: "`a\nb`", in: ts, .typescript) == .string)
    }

    @Test func toleratesMalformedAndLargeInput() {
        for language in SyntaxLanguage.allCases {
            for text in ["\"unterminated\nnext", "/* open", "<div class=\"x", "'", "#", "@", "$", "{", "中文 \"字符串\" 🙂"] {
                let length = (text as NSString).length
                for highlight in SyntaxHighlighter.highlight(text, as: language) {
                    #expect(highlight.length > 0 && highlight.location >= 0 && highlight.location + highlight.length <= length)
                }
            }
        }
        let large = String(repeating: "let x = 1\n", count: SyntaxHighlighter.maxLength / 10 + 1)
        #expect(SyntaxHighlighter.highlight(large, as: .swift).isEmpty)
        let nearLimit = String(repeating: "func f(_ a: Int) -> String { return \"v\" } // c\n",
                               count: SyntaxHighlighter.maxLength / 50)
        #expect(!SyntaxHighlighter.highlight(nearLimit, as: .swift).isEmpty)
    }
}
