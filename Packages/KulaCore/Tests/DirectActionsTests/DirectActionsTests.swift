import Testing
import Foundation
@testable import DirectActions

@Suite struct CalculatorTests {
    @Test(arguments: [("2+3*4", 14.0), ("(2+3)*4", 20), ("2^10", 1024), ("10/4", 2.5), ("1,000*2", 2000),
                      ("3×4", 12), ("-2+5", 3), ("2^3^2", 512), ("10 % 3", 1),
                      ("(12-1)*3", 33), ("(12–1)*3", 33), ("(12−1)×3", 33),
                      ("(12—1)*3", 33), ("（１２－１）＊３", 33),
                      ("((12−1)×3+7)÷2", 20), ("（12－1）×（2＋3）", 55),
                      ("【 (12-12) +1】*12", 12), ("[(12-12)+1]*12", 12),
                      ("{[2+3]*(4-1)}", 15), ("［（１２－１２）＋１］＊１２", 12),
                      ("2(3+4)", 14), ("(2+3) (4-1)", 15), ("(2+3) 4", 20),
                      ("-2^2", -4), ("(-2)^2", 4), ("2^-3", 0.125), ("2*-3", -6),
                      (".5 + 1.25", 1.75), ("1e3+2.5E-1", 1000.25),
                      ("√9+sqrt(16)", 7), ("2√9", 6), ("sqrt(2+7)", 3),
                      ("20%", 0.2), ("100*20%", 20), ("(20+30)%", 0.5), ("10%3", 1)])
    func evaluates(_ input: String, _ expected: Double) {
        #expect(Calculator.evaluate(input) == expected)
    }

    @Test(arguments: ["hello", "1/0", "+8613800138000", "- 5", "1e-5", "-5", "42", "2+", "system(\"ls\")", "1+2;rm",
                      "（12－1", "（12－1）÷0", "１２", "−５", "（12－1）×", "１＋２；rm", "[1+2)", "【1+2", "{[1+2}]", "2 3+4",
                      "1e+2.3", "sqrt(-1)", "√-9", "sqrt(9", "10%0", "2^^3"])
    func rejects(_ input: String) {
        #expect(Calculator.evaluate(input) == nil)
    }

    @Test func inchAbbreviationAndSmallConversions() throws {
        for input in ["10 in to cm", "10 in cm", "10 in in cm"] {
            #expect(try #require(UnitConverter.convert(input)).formattedValue == "25.4")
        }
        let tiny = try #require(UnitConverter.convert("0.1 mm to km"))
        #expect(Double(tiny.formattedValue) == 1e-7)
    }

    @Test func boundedRecursion() {
        #expect(Calculator.evaluate(String(repeating: "-", count: 1000) + "1+2") == nil)
        #expect(Calculator.evaluate(String(repeating: "2^", count: 1000) + "2") == nil)
        #expect(Calculator.evaluate(String(repeating: "(", count: 1000) + "1+2" + String(repeating: ")", count: 1000)) == nil)
    }

    @Test func formatting() {
        #expect(Calculator.format(3) == "3")
        #expect(Calculator.format(2.5) == "2.5")
    }
}

@Suite struct ConversionTests {
    @Test func temperature() throws {
        let c = try #require(UnitConverter.convert("100 f to c"))
        #expect(abs(c.value - 37.7778) < 0.001)
    }

    @Test func chineseUnits() throws {
        let c = try #require(UnitConverter.convert("2 公斤 斤"))
        #expect(abs(c.value - 4) < 1e-9)
    }

    @Test(arguments: [("1斤转两", 10.0), ("10两换成斤", 1.0),
                      ("1 两 克", 50.0), ("50 g to 两", 1.0),
                      ("0.5两 克", 25.0), ("1 公斤 两", 20.0)])
    func liangConversion(_ input: String, _ expected: Double) throws {
        let result = try #require(UnitConverter.convert(input))
        #expect(abs(result.value - expected) < 1e-9)
    }

    @Test func liangDisplay() throws {
        let result = try #require(UnitConverter.convert("1斤转两"))
        #expect(result.display == "1 斤 = 10 两")
        #expect(UnitConverter.convert("1 两 米") == nil)
    }

    @Test func incompatibleDimensions() {
        #expect(UnitConverter.convert("10 kg km") == nil)
        #expect(UnitConverter.convert("km to mi") == nil)
    }
}

@Suite struct CurrencyTests {
    static let ecb = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
    <Cube><Cube time="2026-10-08"><Cube currency="USD" rate="1.1000"/><Cube currency="CNY" rate="7.7000"/></Cube></Cube>
    </gesmes:Envelope>
    """

    @Test func parsesECBAndCrossConverts() throws {
        let r = try #require(ExchangeRates.parseECB(Data(Self.ecb.utf8)))
        #expect(r.date == "2026-10-08")
        let (v, rate) = try #require(r.convert(10, from: "USD", to: "CNY"))
        #expect(abs(rate - 7) < 1e-9)
        #expect(abs(v - 70) < 1e-9)
        #expect(r.convert(1, from: "EUR", to: "USD")?.rate == 1.1) // EUR is the implicit base
        #expect(r.convert(1, from: "USD", to: "XYZ") == nil)
    }

    @Test func queryAliases() {
        #expect(CurrencyQuery.parse("100美元 人民币") == CurrencyQuery(amount: 100, from: "USD", to: "CNY"))
        #expect(CurrencyQuery.parse("100 usd usd") == nil)
        #expect(CurrencyQuery.parse("100 abc cny") == nil)
    }

    @Test func noCacheNoNetworkIsUnavailable() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let svc = ExchangeRateService(cacheURL: dir.appendingPathComponent("rates.json"))
        let r = await svc.convert(CurrencyQuery(amount: 1, from: "USD", to: "CNY"), allowNetwork: false)
        guard case .unavailable = r else { Issue.record("must not fabricate a rate"); return }
    }
}

@Suite struct KeywordTests {
    @Test func onlyBuiltInWebsitesCanBeConfigured() throws {
        let registry = KeywordRegistry(disabledCommands: ["yt"], triggerKeywords: ["go": "search", "custom": "site"])
        #expect(registry.commands.count == KeywordCommand.builtIn.count - 1)
        #expect(registry.matchInput("yt ") == nil)
        #expect(registry.matchInput("go ") == nil)
        #expect(registry.matchInput("site ") == nil)
        let (command, query) = try #require(registry.match("search swift"))
        #expect(command.name == KeywordCommand.builtIn[0].name)
        #expect(command.urlTemplate == KeywordCommand.builtIn[0].urlTemplate)
        #expect(query == "swift")
        #expect(KeywordRegistry().commands.map(\.keyword) == [
            "go", "chat", "ds", "yt", "dy", "tb", "jd", "bl", "gh", "bd", "hb", "zh", "xhs", "wb", "x",
        ])
    }

    @Test func chatGPTCarriesQueryWithoutUserTemplate() throws {
        let command = KeywordCommand.websitePresets[0]
        #expect(command.supportsQuery)
        let url = try #require(command.url(for: "中文 & + # / ?"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "q" }?.value == "中文 & + # / ?")
        #expect(url.absoluteString.contains("%2B"))
        #expect(command.url(for: "")?.query == nil)
        #expect(KeywordCommand.websitePresets.allSatisfy { $0.supportsQuery })
    }

    @Test func deepSeekCarriesQueryAndPreservesSpecialCharacters() throws {
        let (command, query) = try #require(KeywordRegistry().match("ds 中文 & + # / ?"))
        #expect(command.name == "DeepSeek" && command.supportsQuery)
        let url = try #require(command.url(for: query))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.host == "chat.deepseek.com")
        #expect(components.queryItems?.first { $0.name == "q" }?.value == query)
        #expect(url.absoluteString.contains("%2B"))
    }

    @Test func encodesQuerySafely() throws {
        let url = try #require(KeywordCommand.builtIn[0].url(for: "a&b=c #d"))
        #expect(url.query?.contains("a%26b%3Dc%20%23d") == true)
    }
}

@Suite struct TerminalTests {
    @Test func interactiveDetection() {
        #expect(TerminalRunner.isInteractive("vim file"))
        #expect(TerminalRunner.isInteractive("python3"))
        #expect(!TerminalRunner.isInteractive("python3 script.py"))
        #expect(!TerminalRunner.isInteractive("ls -la"))
    }

    @Test func runsAndReportsExitCode() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runner = TerminalRunner(spillDirectory: dir)
        var output = ""
        var exit: Int32?
        for await e in runner.run("echo hello; echo err >&2; exit 3", workingDirectory: FileManager.default.temporaryDirectory) {
            switch e {
            case .stdout(let s), .stderr(let s): output += s
            case .exited(let c, _): exit = c
            default: break
            }
        }
        #expect(output.contains("hello"))
        #expect(output.contains("err"))
        #expect(exit == 3)
    }
}
