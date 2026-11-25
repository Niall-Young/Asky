import Foundation

/// A colored span in a previewed source file. Locations and lengths use UTF-16 units to match `NSRange`.
public struct SyntaxHighlight: Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case comment, string, number, keyword, literal, type, function, attribute, property, tag
        case inserted, deleted, meta
    }

    public let kind: Kind
    public let location: Int
    public let length: Int

    public init(_ kind: Kind, location: Int, length: Int) {
        self.kind = kind
        self.location = location
        self.length = length
    }

    public var range: NSRange { NSRange(location: location, length: length) }
}

/// Languages recognized by the quick preview. Detection uses the file name, extension, then a shebang line.
public enum SyntaxLanguage: String, Sendable, CaseIterable {
    case c, cpp, objectiveC, swift, java, kotlin, scala, csharp, go, rust, javascript, typescript, dart, php
    case python, ruby, shell, lua, r, sql, css, scss, html, xml, json, yaml, toml, ini, properties
    case makefile, dockerfile, cmake, diff, protobuf, graphql, ignore

    private static let names: [String: SyntaxLanguage] = [
        "dockerfile": .dockerfile, "containerfile": .dockerfile, "makefile": .makefile, "gnumakefile": .makefile,
        "gemfile": .ruby, "rakefile": .ruby, "podfile": .ruby, "cmakelists.txt": .cmake, ".env": .properties,
        ".gitignore": .ignore, ".gitattributes": .ignore, ".dockerignore": .ignore, ".editorconfig": .ini,
        ".npmrc": .ini, ".bashrc": .shell, ".zshrc": .shell, ".zprofile": .shell, ".bash_profile": .shell,
        ".profile": .shell
    ]

    private static let extensions: [String: SyntaxLanguage] = {
        var map: [String: SyntaxLanguage] = [:]
        let groups: [(SyntaxLanguage, String)] = [
            (.c, "c h"), (.cpp, "cc cpp cxx c++ hpp hh hxx ino"), (.objectiveC, "m mm"), (.swift, "swift"),
            (.java, "java groovy gradle"), (.kotlin, "kt kts"), (.scala, "scala sc"), (.csharp, "cs"),
            (.go, "go"), (.rust, "rs"), (.javascript, "js jsx mjs cjs"), (.typescript, "ts tsx mts cts"),
            (.dart, "dart"), (.php, "php"), (.python, "py pyw pyi"), (.ruby, "rb rake gemspec"),
            (.shell, "sh bash zsh fish command ksh"), (.lua, "lua"), (.r, "r"), (.sql, "sql"), (.css, "css"),
            (.scss, "scss sass less"), (.html, "html htm xhtml vue svelte"),
            (.xml, "xml plist xib storyboard entitlements csproj xsd xsl"),
            (.json, "json jsonc jsonl ndjson geojson"), (.yaml, "yaml yml"), (.toml, "toml"),
            (.ini, "ini conf cfg editorconfig"), (.properties, "properties env"), (.diff, "diff patch"),
            (.protobuf, "proto"), (.graphql, "graphql gql"), (.cmake, "cmake")
        ]
        for (language, list) in groups { for ext in list.split(separator: " ") { map[String(ext)] = language } }
        return map
    }()

    public init?(url: URL, text: String? = nil) {
        let name = url.lastPathComponent.lowercased()
        if let language = Self.names[name] ?? Self.extensions[url.pathExtension.lowercased()] {
            self = language
            return
        }
        guard let text, text.hasPrefix("#!") else { return nil }
        let line = text.prefix { $0 != "\n" }.lowercased()
        let interpreters: [(String, SyntaxLanguage)] = [
            ("python", .python), ("node", .javascript), ("deno", .typescript), ("bun", .typescript),
            ("ruby", .ruby), ("swift", .swift), ("lua", .lua), ("php", .php), ("zsh", .shell), ("bash", .shell),
            ("fish", .shell), ("sh", .shell)
        ]
        guard let match = interpreters.first(where: { line.contains($0.0) }) else { return nil }
        self = match.1
    }
}

public enum SyntaxHighlighter {
    /// Larger files stay readable as plain text instead of delaying the preview.
    public static let maxLength = 512 * 1024

    public static func highlight(_ text: String, as language: SyntaxLanguage) -> [SyntaxHighlight] {
        let units = Array(text.utf16)
        guard !units.isEmpty, units.count <= maxLength else { return [] }
        var scanner = SyntaxScanner(units: units)
        switch language {
        case .diff: scanner.diff()
        case .html, .xml: scanner.markup(embedded: language == .html)
        case .css, .scss: scanner.css(lo: 0, hi: units.count, lineComments: language == .scss)
        default: scanner.code(lo: 0, hi: units.count, grammar: SyntaxGrammar(language))
        }
        return scanner.output
    }
}

// MARK: - Grammar

private func ch(_ scalar: Unicode.Scalar) -> UInt16 { UInt16(scalar.value) }
private func words(_ list: String) -> Set<String> { Set(list.split(separator: " ").map(String.init)) }
private func utf16(_ text: String) -> [UInt16] { Array(text.utf16) }

private struct SyntaxGrammar {
    var lineComments: [[UInt16]] = []
    var blockComments: [([UInt16], [UInt16])] = []
    var quotes: Set<UInt16> = [ch("\""), ch("'")]
    var multilineQuotes: Set<UInt16> = []
    var tripleQuotes = false
    var keywords: Set<String> = []
    var literals: Set<String> = []
    var types: Set<String> = []
    var caseInsensitive = false
    var capitalizedTypes = false
    var attributePrefixes: Set<UInt16> = []
    var preprocessor = false
    var variablePrefix: UInt16?
    var dollarIdentifiers = false
    var lineKeys: Set<UInt16> = []
    var sectionHeaders = false
    var macroBang = false
    var lifetimes = false
    var stringPrefixes: Set<String> = []
    var jsonKeys = false
    var rustAttributes = false

    private static let slash = [utf16("//")], cBlock = [(utf16("/*"), utf16("*/"))], hash = [utf16("#")]
    private static let cTypes = words("""
        int char void float double long short unsigned signed bool size_t ssize_t int8_t int16_t int32_t int64_t \
        uint8_t uint16_t uint32_t uint64_t uintptr_t intptr_t wchar_t auto
        """)
    private static let cKeywords = words("""
        break case const continue default do else enum extern for goto if inline register restrict return sizeof \
        static struct switch typedef union volatile while _Bool _Atomic _Noreturn
        """)
    private static let cppKeywords = words("""
        class namespace template typename public private protected virtual override final using new delete this \
        throw try catch operator friend explicit constexpr consteval constinit noexcept static_cast dynamic_cast \
        reinterpret_cast const_cast decltype mutable concept requires co_await co_return co_yield alignas alignof \
        thread_local static_assert export import module
        """)
    private static let jsKeywords = words("""
        break case catch class const continue debugger default delete do else export extends finally for function \
        if import in instanceof let new return super switch this throw try typeof var void while with yield async \
        await of static get set from as
        """)

    init(_ language: SyntaxLanguage) {
        switch language {
        case .c, .cpp, .objectiveC:
            lineComments = Self.slash; blockComments = Self.cBlock; preprocessor = true; capitalizedTypes = language != .c
            types = Self.cTypes
            keywords = Self.cKeywords
            if language != .c { keywords.formUnion(Self.cppKeywords) }
            literals = words("true false NULL nullptr")
            stringPrefixes = words("L u U u8 R LR uR UR u8R")
            if language == .objectiveC {
                attributePrefixes = [ch("@")]
                keywords.formUnion(words("self super id instancetype nonatomic atomic strong weak copy assign readonly readwrite nullable nonnull"))
                literals.formUnion(words("nil Nil YES NO"))
                types.formUnion(words("BOOL SEL IMP Class NSInteger NSUInteger CGFloat"))
            }
        case .swift:
            lineComments = Self.slash; blockComments = Self.cBlock; tripleQuotes = true; capitalizedTypes = true
            attributePrefixes = [ch("@"), ch("#")]
            keywords = words("""
                associatedtype class deinit enum extension fileprivate func import init inout internal let open \
                operator private precedencegroup protocol public rethrows static struct subscript typealias var break \
                case catch continue default defer do else fallthrough for guard if in repeat return throw switch where \
                while as is try await async throws super self Self actor some any nonisolated isolated mutating \
                nonmutating override final lazy weak unowned required convenience dynamic indirect get set willSet \
                didSet consume borrowing consuming macro package sending optional
                """)
            literals = words("true false nil")
        case .java, .kotlin, .scala, .csharp, .dart:
            lineComments = Self.slash; blockComments = Self.cBlock; capitalizedTypes = true
            attributePrefixes = [ch("@")]
            literals = words("true false null")
            tripleQuotes = language != .csharp
            switch language {
            case .java:
                keywords = words("""
                    abstract assert break case catch class const continue default do else enum extends final finally \
                    for goto if implements import instanceof interface native new package private protected public \
                    return static strictfp super switch synchronized this throw throws transient try volatile while \
                    var record sealed permits yield def
                    """)
                types = words("boolean byte char double float int long short void")
            case .kotlin:
                keywords = words("""
                    as break class continue do else for fun if in interface is object package return super this throw \
                    try typealias typeof val var when while by catch constructor delegate dynamic field file finally \
                    get import init param property receiver set setparam where actual abstract annotation companion \
                    const crossinline data enum expect external final infix inline inner internal lateinit noinline \
                    open operator out override private protected public reified sealed suspend tailrec vararg value
                    """)
            case .scala:
                keywords = words("""
                    abstract case catch class def do else extends final finally for forSome if implicit import lazy \
                    match new object override package private protected return sealed super this throw trait try type \
                    val var while with yield given using enum then export end
                    """)
            case .csharp:
                keywords = words("""
                    abstract as base break case catch checked class const continue default delegate do else enum event \
                    explicit extern finally fixed for foreach goto if implicit in interface internal is lock namespace \
                    new operator out override params private protected public readonly ref return sealed sizeof \
                    stackalloc static struct switch this throw try typeof unchecked unsafe using virtual volatile while \
                    var async await dynamic get set value yield record init where nameof partial
                    """)
                types = words("bool byte char decimal double float int long object sbyte short string uint ulong ushort void")
                stringPrefixes = ["@", "$"]
            default:
                keywords = words("""
                    abstract as assert async await break case catch class const continue covariant default deferred do \
                    dynamic else enum export extends extension external factory final finally for get hide if \
                    implements import in interface is late library mixin new on operator part required rethrow return \
                    sealed set show static super switch sync this throw try typedef var when while with yield base
                    """)
                types = words("void int double num bool")
            }
        case .go:
            lineComments = Self.slash; blockComments = Self.cBlock; multilineQuotes = [ch("`")]
            quotes.insert(ch("`"))
            keywords = words("""
                break case chan const continue default defer else fallthrough for func go goto if import interface \
                map package range return select struct switch type var
                """)
            types = words("""
                bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 \
                uint16 uint32 uint64 uintptr any comparable
                """)
            literals = words("true false nil iota")
        case .rust:
            lineComments = Self.slash; blockComments = Self.cBlock; capitalizedTypes = true; macroBang = true
            lifetimes = true; rustAttributes = true; stringPrefixes = words("b r br")
            keywords = words("""
                as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod \
                move mut pub ref return self Self static struct super trait type unsafe use where while macro_rules union
                """)
            types = words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str")
            literals = words("true false None Some Ok Err")
        case .javascript, .typescript:
            lineComments = Self.slash; blockComments = Self.cBlock; capitalizedTypes = true; dollarIdentifiers = true
            quotes.insert(ch("`")); multilineQuotes = [ch("`")]; attributePrefixes = [ch("@")]
            keywords = Self.jsKeywords
            literals = words("true false null undefined NaN Infinity")
            if language == .typescript {
                keywords.formUnion(words("""
                    interface type enum implements namespace declare abstract private protected public readonly keyof \
                    infer is satisfies module unique override asserts accessor
                    """))
                types = words("string number boolean any unknown never object symbol bigint void")
            }
        case .php:
            lineComments = Self.slash + Self.hash; blockComments = Self.cBlock; variablePrefix = ch("$")
            capitalizedTypes = true; caseInsensitive = true
            keywords = words("""
                abstract and array as break callable case catch class clone const continue declare default do echo \
                else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for \
                foreach function global goto if implements include include_once instanceof insteadof interface isset \
                list match namespace new or print private protected public readonly require require_once return static \
                switch throw trait try unset use var while xor yield enum
                """)
            literals = words("true false null")
        case .python:
            lineComments = Self.hash; tripleQuotes = true; attributePrefixes = [ch("@")]; capitalizedTypes = true
            stringPrefixes = words("f r b u rb br fr rf F R B U")
            keywords = words("""
                and as assert async await break class continue def del elif else except finally for from global if \
                import in is lambda nonlocal not or pass raise return try while with yield match case self cls
                """)
            literals = words("True False None")
            types = words("int str float bool list dict set tuple bytes object type complex frozenset")
        case .ruby:
            lineComments = Self.hash; attributePrefixes = [ch("@")]; capitalizedTypes = true
            keywords = words("""
                BEGIN END alias and begin break case class def do else elsif end ensure for if in module next not or \
                redo rescue retry return self super then undef unless until when while yield require require_relative \
                attr_accessor attr_reader attr_writer include extend private protected public lambda proc puts raise
                """)
            literals = words("true false nil")
        case .shell:
            lineComments = Self.hash; variablePrefix = ch("$"); multilineQuotes = quotes
            keywords = words("""
                if then else elif fi case esac for while until do done in function select time return exit break \
                continue local export readonly declare typeset unset source alias set shift trap eval exec end not and \
                or switch begin echo cd printf test
                """)
            literals = words("true false")
        case .lua:
            lineComments = [utf16("--")]; blockComments = [(utf16("--[["), utf16("]]"))]
            keywords = words("""
                and break do else elseif end for function goto if in local not or repeat return then until while self
                """)
            literals = words("true false nil")
        case .r:
            lineComments = Self.hash
            keywords = words("if else repeat while function for in next break library require return")
            literals = words("TRUE FALSE NULL Inf NaN NA T F")
        case .sql:
            lineComments = [utf16("--")]; blockComments = Self.cBlock; caseInsensitive = true
            keywords = words("""
                select from where insert into values update set delete create table alter drop index view join inner \
                left right outer full cross on as and or not is in exists between like limit offset order by group \
                having distinct union all case when then else end primary key foreign references default unique check \
                constraint begin commit rollback transaction with returning if replace trigger database schema grant \
                revoke cast asc desc add column rename to using pragma explain
                """)
            types = words("""
                integer int text varchar char boolean date datetime timestamp real blob float double numeric decimal \
                serial bigint smallint json jsonb uuid
                """)
            literals = words("null true false")
        case .json:
            lineComments = Self.slash; blockComments = Self.cBlock; jsonKeys = true; quotes = [ch("\"")]
            literals = words("true false null")
        case .yaml:
            lineComments = Self.hash; lineKeys = [ch(":")]; attributePrefixes = [ch("&"), ch("*")]
            literals = words("true false null yes no on off True False Null Yes No TRUE FALSE NULL ~")
        case .toml, .ini, .properties:
            lineComments = language == .toml ? Self.hash : Self.hash + [utf16(";")]
            lineKeys = language == .properties ? [ch("="), ch(":")] : [ch("=")]
            sectionHeaders = true
            literals = words("true false yes no on off")
            if language == .properties { quotes = [ch("\""), ch("'")] }
        case .makefile:
            lineComments = Self.hash; lineKeys = [ch(":")]; variablePrefix = ch("$")
            keywords = words("ifeq ifneq ifdef ifndef else endif include define endef export override")
        case .dockerfile:
            lineComments = Self.hash; variablePrefix = ch("$")
            keywords = words("""
                FROM RUN CMD COPY ADD ENV ARG WORKDIR EXPOSE ENTRYPOINT LABEL USER VOLUME HEALTHCHECK SHELL ONBUILD \
                STOPSIGNAL MAINTAINER AS
                """)
        case .cmake:
            lineComments = Self.hash; variablePrefix = ch("$"); caseInsensitive = true
            keywords = words("""
                if elseif else endif foreach endforeach while endwhile function endfunction macro endmacro return set \
                unset option project
                """)
            literals = words("on off true false yes no")
        case .protobuf:
            lineComments = Self.slash; blockComments = Self.cBlock; capitalizedTypes = true
            keywords = words("""
                syntax edition message enum service rpc returns option import package repeated optional required oneof \
                map reserved stream extend public weak
                """)
            types = words("""
                double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes
                """)
            literals = words("true false")
        case .graphql:
            lineComments = Self.hash; variablePrefix = ch("$"); attributePrefixes = [ch("@")]; capitalizedTypes = true
            tripleQuotes = true
            keywords = words("""
                query mutation subscription fragment on type interface union enum input scalar schema extend \
                implements directive repeatable
                """)
            literals = words("true false null")
        case .ignore:
            lineComments = Self.hash; quotes = []
        case .diff, .html, .xml, .css, .scss:
            break
        }
    }
}

// MARK: - Scanner

private struct SyntaxScanner {
    let units: [UInt16]
    var output: [SyntaxHighlight] = []

    private static let newline = ch("\n"), cr = ch("\r"), space = ch(" "), tab = ch("\t")
    private static let backslash = ch("\\"), quote = ch("\""), apostrophe = ch("'")

    init(units: [UInt16]) { self.units = units }

    private var count: Int { units.count }

    private func at(_ index: Int) -> UInt16 { index < count ? units[index] : 0 }

    private mutating func add(_ kind: SyntaxHighlight.Kind, _ start: Int, _ end: Int) {
        if end > start { output.append(SyntaxHighlight(kind, location: start, length: end - start)) }
    }

    private static func isLetter(_ c: UInt16) -> Bool {
        (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x5F || c >= 0x80
    }
    private static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
    private static func isUpper(_ c: UInt16) -> Bool { c >= 0x41 && c <= 0x5A }
    private static func isLower(_ c: UInt16) -> Bool { c >= 0x61 && c <= 0x7A }
    private static func isSpace(_ c: UInt16) -> Bool { c == space || c == tab || c == newline || c == cr }

    private func isIdentifierPart(_ c: UInt16, dollar: Bool = false) -> Bool {
        Self.isLetter(c) || Self.isDigit(c) || (dollar && c == ch("$"))
    }

    private func matches(_ token: [UInt16], at index: Int) -> Bool {
        guard !token.isEmpty, index + token.count <= count else { return false }
        for offset in token.indices where units[index + offset] != token[offset] { return false }
        return true
    }

    private func lineEnd(from index: Int, limit: Int) -> Int {
        var end = index
        while end < limit, units[end] != Self.newline { end += 1 }
        return end
    }

    private func find(_ token: [UInt16], from index: Int, limit: Int) -> Int? {
        var cursor = index
        while cursor + token.count <= limit {
            if matches(token, at: cursor) { return cursor }
            cursor += 1
        }
        return nil
    }

    private func word(_ start: Int, _ end: Int) -> String {
        String(decoding: units[start..<end], as: UTF16.self)
    }

    /// Returns the index after a quoted string. Unterminated single-line strings stop at the line end.
    private func stringEnd(from start: Int, limit: Int, quote: UInt16, multiline: Bool, triple: Bool,
                           escapes: Bool = true) -> Int {
        if triple {
            let close = [quote, quote, quote]
            var cursor = start + 3
            while cursor < limit {
                if escapes, units[cursor] == Self.backslash { cursor += 2; continue }
                if matches(close, at: cursor) { return cursor + 3 }
                cursor += 1
            }
            return limit
        }
        var cursor = start + 1
        while cursor < limit {
            let c = units[cursor]
            if escapes, c == Self.backslash { cursor += 2; continue }
            if c == quote { return cursor + 1 }
            if c == Self.newline, !multiline { return cursor }
            cursor += 1
        }
        return limit
    }

    private func numberEnd(from start: Int, limit: Int, allowUnits: Bool = false) -> Int {
        let hex = at(start) == ch("0") && (at(start + 1) == ch("x") || at(start + 1) == ch("X"))
        var cursor = start + 1
        while cursor < limit {
            let c = units[cursor]
            if Self.isLetter(c) && c < 0x80 || Self.isDigit(c) {
                cursor += 1
                if !hex, c == ch("e") || c == ch("E"), cursor < limit, units[cursor] == ch("+") || units[cursor] == ch("-"),
                   Self.isDigit(at(cursor + 1)) {
                    cursor += 1
                }
            } else if c == ch("."), Self.isDigit(at(cursor + 1)) {
                cursor += 1
            } else if allowUnits, c == ch("%") || c == ch("-") && Self.isLetter(at(cursor + 1)) {
                cursor += 1
            } else {
                break
            }
        }
        return min(cursor, limit)
    }

    // MARK: Code

    mutating func code(lo: Int, hi: Int, grammar g: SyntaxGrammar) {
        var i = lo
        var lineStart = true
        while i < hi {
            let c = units[i]
            if c == Self.newline { lineStart = true; i += 1; continue }
            if c == Self.space || c == Self.tab || c == Self.cr { i += 1; continue }
            let atLineStart = lineStart
            lineStart = false
            let previous = i > lo ? units[i - 1] : Self.newline

            if let (open, close) = g.blockComments.first(where: { matches($0.0, at: i) }) {
                let end = find(close, from: i + open.count, limit: hi).map { $0 + close.count } ?? hi
                add(.comment, i, end); i = end; continue
            }
            if let comment = g.lineComments.first(where: { matches($0, at: i) }),
               comment.count > 1 || Self.isSpace(previous) && (comment[0] != ch(";") || atLineStart) {
                let end = lineEnd(from: i, limit: hi)
                add(.comment, i, end); i = end; continue
            }
            if atLineStart, let next = lineStartToken(at: i, hi: hi, grammar: g) { i = next; continue }
            if g.preprocessor, atLineStart, c == ch("#") {
                var end = i + 1
                while end < hi, units[end] == Self.space || units[end] == Self.tab { end += 1 }
                while end < hi, Self.isLetter(units[end]) { end += 1 }
                add(.attribute, i, end)
                var cursor = end
                while cursor < hi, units[cursor] == Self.space { cursor += 1 }
                if at(cursor) == ch("<"), let close = find([ch(">")], from: cursor, limit: lineEnd(from: cursor, limit: hi)) {
                    add(.string, cursor, close + 1); end = close + 1
                }
                i = end; continue
            }
            if g.rustAttributes, c == ch("#"), at(i + 1) == ch("[") || at(i + 1) == ch("!") && at(i + 2) == ch("[") {
                let limit = lineEnd(from: i, limit: hi)
                var depth = 0, end = i + 1
                while end < limit {
                    if units[end] == ch("[") { depth += 1 } else if units[end] == ch("]") { depth -= 1; if depth == 0 { end += 1; break } }
                    end += 1
                }
                add(.attribute, i, end); i = end; continue
            }
            if g.quotes.contains(c) {
                if g.lifetimes, c == Self.apostrophe, Self.isLetter(at(i + 1)), at(i + 2) != Self.apostrophe {
                    var end = i + 1
                    while end < hi, isIdentifierPart(units[end]) { end += 1 }
                    if at(end) != Self.apostrophe { add(.attribute, i, end); i = end; continue }
                }
                if !isIdentifierPart(previous) {
                    i = string(at: i, start: i, hi: hi, grammar: g); continue
                }
                i += 1; continue
            }
            if Self.isDigit(c), !isIdentifierPart(previous, dollar: g.dollarIdentifiers) {
                let end = numberEnd(from: i, limit: hi)
                add(.number, i, end); i = end; continue
            }
            if g.attributePrefixes.contains(c), Self.isLetter(at(i + 1)) {
                var end = i + 1
                while end < hi, isIdentifierPart(units[end]) || units[end] == ch(".") && Self.isLetter(at(end + 1)) { end += 1 }
                add(.attribute, i, end); i = end; continue
            }
            if let prefix = g.variablePrefix, c == prefix {
                let next = at(i + 1)
                if next == ch("{") || next == ch("(") {
                    let close = next == ch("{") ? ch("}") : ch(")")
                    let end = find([close], from: i + 2, limit: lineEnd(from: i, limit: hi)).map { $0 + 1 } ?? i + 2
                    add(.property, i, end); i = end; continue
                }
                if Self.isLetter(next) {
                    var end = i + 1
                    while end < hi, isIdentifierPart(units[end]) { end += 1 }
                    add(.property, i, end); i = end; continue
                }
                if Self.isDigit(next) || [ch("@"), ch("?"), ch("#"), ch("*"), ch("!"), ch("$"), ch("-")].contains(next) {
                    add(.property, i, i + 2); i += 2; continue
                }
            }
            if Self.isLetter(c) || g.dollarIdentifiers && c == ch("$") {
                var end = i + 1
                while end < hi, isIdentifierPart(units[end], dollar: g.dollarIdentifiers) { end += 1 }
                i = identifier(start: i, end: end, hi: hi, previous: previous, grammar: g); continue
            }
            if c < 0x80, g.quotes.contains(at(i + 1)), let scalar = Unicode.Scalar(c),
               g.stringPrefixes.contains(String(Character(scalar))) {
                i = string(at: i + 1, start: i, hi: hi, grammar: g); continue
            }
            i += 1
        }
    }

    private mutating func string(at quoteIndex: Int, start: Int, hi: Int, grammar g: SyntaxGrammar) -> Int {
        let q = units[quoteIndex]
        let triple = g.tripleQuotes && at(quoteIndex + 1) == q && at(quoteIndex + 2) == q
        let end = stringEnd(from: quoteIndex, limit: hi, quote: q, multiline: g.multilineQuotes.contains(q), triple: triple)
        var kind = SyntaxHighlight.Kind.string
        if g.jsonKeys {
            var cursor = end
            while cursor < hi, Self.isSpace(units[cursor]) { cursor += 1 }
            if at(cursor) == ch(":") { kind = .property }
        }
        add(kind, start, end)
        return end
    }

    private mutating func identifier(start: Int, end: Int, hi: Int, previous: UInt16, grammar g: SyntaxGrammar) -> Int {
        let text = word(start, end)
        if g.stringPrefixes.contains(text), g.quotes.contains(at(end)) {
            return string(at: end, start: start, hi: hi, grammar: g)
        }
        let key = g.caseInsensitive ? text.lowercased() : text
        let member = previous == ch(".") && !(start >= 2 && units[start - 2] == ch("."))
        if g.macroBang, at(end) == ch("!"), at(end + 1) != ch("=") {
            add(.function, start, end + 1); return end + 1
        }
        if !member {
            if g.keywords.contains(key) { add(.keyword, start, end); return end }
            if g.literals.contains(key) { add(.literal, start, end); return end }
            if g.types.contains(key) { add(.type, start, end); return end }
        }
        if at(end) == ch("(") { add(.function, start, end); return end }
        if g.capitalizedTypes, Self.isUpper(units[start]), units[start..<end].contains(where: Self.isLower) {
            add(.type, start, end)
        }
        return end
    }

    /// Highlights `key:` / `key =` and `[section]` at the start of configuration lines.
    private mutating func lineStartToken(at i: Int, hi: Int, grammar g: SyntaxGrammar) -> Int? {
        let lineLimit = lineEnd(from: i, limit: hi)
        if g.sectionHeaders, units[i] == ch("[") {
            guard var end = find([ch("]")], from: i + 1, limit: lineLimit) else { return nil }
            end += 1
            if at(end) == ch("]") { end += 1 }
            add(.type, i, end); return end
        }
        guard !g.lineKeys.isEmpty else { return nil }
        var start = i
        if units[start] == ch("-"), at(start + 1) == Self.space {
            start += 2
            while start < lineLimit, units[start] == Self.space { start += 1 }
        }
        var end = start
        while end < lineLimit, isIdentifierPart(units[end]) || [ch("."), ch("-"), ch("/")].contains(units[end]) { end += 1 }
        guard end > start else { return nil }
        var separator = end
        while separator < lineLimit, units[separator] == Self.space || units[separator] == Self.tab { separator += 1 }
        guard separator < lineLimit, g.lineKeys.contains(units[separator]) else { return nil }
        if units[separator] == ch(":") {
            let next = at(separator + 1)
            guard separator + 1 >= lineLimit || Self.isSpace(next) || next == ch("=") else { return nil }
        }
        add(.property, start, end)
        return separator + 1
    }

    // MARK: Diff

    mutating func diff() {
        var i = 0
        while i < count {
            let end = lineEnd(from: i, limit: count)
            let line = units[i..<end]
            let starts: (String) -> Bool = { prefix in line.starts(with: prefix.utf16) }
            if starts("+++ ") || starts("--- ") || starts("diff ") || starts("index ") {
                add(.keyword, i, end)
            } else if starts("@@") {
                add(.meta, i, end)
            } else if starts("+") {
                add(.inserted, i, end)
            } else if starts("-") {
                add(.deleted, i, end)
            }
            i = end + 1
        }
    }

    // MARK: Markup

    mutating func markup(embedded: Bool) {
        var i = 0
        while i < count {
            let c = units[i]
            if matches(utf16("<!--"), at: i) {
                let end = find(utf16("-->"), from: i + 4, limit: count).map { $0 + 3 } ?? count
                add(.comment, i, end); i = end; continue
            }
            if matches(utf16("<![CDATA["), at: i) {
                let end = find(utf16("]]>"), from: i + 9, limit: count).map { $0 + 3 } ?? count
                add(.string, i, end); i = end; continue
            }
            if c == ch("<"), at(i + 1) == ch("!") || at(i + 1) == ch("?") {
                let end = find([ch(">")], from: i, limit: count).map { $0 + 1 } ?? count
                add(.meta, i, end); i = end; continue
            }
            if c == ch("<"), Self.isLetter(at(i + 1)) || at(i + 1) == ch("/") && Self.isLetter(at(i + 2)) {
                i = tag(at: i, embedded: embedded); continue
            }
            if c == ch("&") {
                var end = i + 1
                while end < min(count, i + 12), isIdentifierPart(units[end]) || units[end] == ch("#") { end += 1 }
                if at(end) == ch(";"), end > i + 1 { add(.literal, i, end + 1); i = end + 1; continue }
            }
            i += 1
        }
    }

    private mutating func tag(at start: Int, embedded: Bool) -> Int {
        let closing = units[start + 1] == ch("/")
        var nameEnd = start + (closing ? 2 : 1)
        let nameStart = nameEnd
        while nameEnd < count, isIdentifierPart(units[nameEnd]) || [ch("-"), ch(":"), ch(".")].contains(units[nameEnd]) {
            nameEnd += 1
        }
        let name = word(nameStart, nameEnd).lowercased()
        add(.tag, start, nameEnd)
        var i = nameEnd
        while i < count {
            let c = units[i]
            if c == ch("<") { break }
            if c == ch(">") || c == ch("/") && at(i + 1) == ch(">") {
                let end = c == ch(">") ? i + 1 : i + 2
                add(.tag, i, end)
                i = end
                break
            }
            if c == Self.quote || c == Self.apostrophe {
                let end = stringEnd(from: i, limit: count, quote: c, multiline: true, triple: false, escapes: false)
                add(.string, i, end); i = end; continue
            }
            if Self.isSpace(c) || c == ch("=") { i += 1; continue }
            var end = i
            while end < count, !Self.isSpace(units[end]),
                  ![ch("="), ch(">"), Self.quote, Self.apostrophe].contains(units[end]),
                  !(units[end] == ch("/") && at(end + 1) == ch(">")) { end += 1 }
            let previous = i > 0 ? units[i - 1] : 0
            add(previous == ch("=") ? .string : .property, i, max(end, i + 1))
            i = max(end, i + 1)
        }
        guard embedded, !closing, name == "script" || name == "style" else { return i }
        let close = find(utf16("</\(name)"), from: i, limit: count) ?? count
        if name == "style" {
            css(lo: i, hi: close, lineComments: false)
        } else {
            code(lo: i, hi: close, grammar: SyntaxGrammar(.typescript))
        }
        return close
    }

    // MARK: CSS

    /// Whether the rest of a CSS statement opens a block, which marks it as a selector instead of a declaration.
    private func opensBlock(from index: Int, limit: Int) -> Bool {
        var cursor = index
        while cursor < limit {
            switch units[cursor] {
            case ch("{"): return true
            case ch(";"), ch("}"), Self.newline: return false
            default: cursor += 1
            }
        }
        return false
    }

    mutating func css(lo: Int, hi: Int, lineComments: Bool) {
        var i = lo
        var depth = 0
        while i < hi {
            let c = units[i]
            let previous = i > lo ? units[i - 1] : Self.newline
            let next = at(i + 1)
            if matches(utf16("/*"), at: i) {
                let end = find(utf16("*/"), from: i + 2, limit: hi).map { $0 + 2 } ?? hi
                add(.comment, i, end); i = end; continue
            }
            if lineComments, matches(utf16("//"), at: i), previous != ch(":") {
                let end = lineEnd(from: i, limit: hi)
                add(.comment, i, end); i = end; continue
            }
            if c == Self.quote || c == Self.apostrophe {
                let end = stringEnd(from: i, limit: hi, quote: c, multiline: false, triple: false)
                add(.string, i, end); i = end; continue
            }
            if c == ch("{") { depth += 1; i += 1; continue }
            if c == ch("}") { depth = max(0, depth - 1); i += 1; continue }
            let selector = depth == 0 || opensBlock(from: i, limit: hi)
            let kind: SyntaxHighlight.Kind? = switch c {
            case ch("@") where Self.isLetter(next), ch("!") where Self.isLetter(next): .keyword
            case ch("$") where Self.isLetter(next): .property
            case ch("-") where next == ch("-") && Self.isLetter(at(i + 2)): .property
            case ch("#") where !selector && (Self.isLetter(next) || Self.isDigit(next)): .number
            case ch("#") where Self.isLetter(next), ch(".") where Self.isLetter(next) && selector: .attribute
            case ch(":") where Self.isLetter(next) && selector: .keyword
            default: nil
            }
            if let kind {
                var end = i + 1
                if c == ch(":"), at(end) == ch(":") { end += 1 }
                while end < hi, isIdentifierPart(units[end]) || units[end] == ch("-") { end += 1 }
                add(kind, i, end); i = end; continue
            }
            if Self.isDigit(c) || c == ch(".") && Self.isDigit(next), !isIdentifierPart(previous) {
                let end = numberEnd(from: i, limit: hi, allowUnits: true)
                add(.number, i, end); i = end; continue
            }
            if Self.isLetter(c) {
                var end = i + 1
                while end < hi, isIdentifierPart(units[end]) || units[end] == ch("-") { end += 1 }
                var cursor = end
                while cursor < hi, units[cursor] == Self.space || units[cursor] == Self.tab { cursor += 1 }
                if at(end) == ch("(") {
                    add(.function, i, end)
                } else if selector {
                    add(.tag, i, end)
                } else if at(cursor) == ch(":") {
                    add(.property, i, end)
                }
                i = end; continue
            }
            i += 1
        }
    }
}
