import Testing
import Foundation
import Contracts
@testable import Adapters

@Suite struct ArgsTests {
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    @Test func parsesOffsetAndLocalWallTime() throws {
        let withOffset = try #require(Args.date("2026-10-10T15:00:00+08:00"))
        let local = try #require(Args.date("2026-10-10T15:00", timeZone: shanghai))
        let spaced = try #require(Args.date("2026-10-10 15:00", timeZone: shanghai))
        #expect(withOffset == local && local == spaced)
        #expect(Args.date("2026-10-10T07:00:00Z") == withOffset)
        #expect(Args.date("2026-10-10T07:00:00.500Z") != nil)
    }

    @Test func rejectsGarbage() {
        #expect(Args.date("明天下午三点") == nil)
        #expect(Args.date("") == nil)
        #expect(Args.date(.number(1)) == nil)
        #expect(throws: ToolError.self) { try Args.requiredDate(["start": "x"], "start") }
    }

    @Test func isoRoundTripsInZone() throws {
        let d = try #require(Args.date("2026-10-10T15:00:00+08:00"))
        #expect(Args.iso(d, timeZone: shanghai) == "2026-10-10T15:00:00+08:00")
    }

    @Test func stringAndIntHelpers() throws {
        #expect(try Args.string("  x ", "n") == "x")
        #expect(throws: ToolError.self) { try Args.string("   ", "n") }
        #expect(try Args.string(nil, "n", required: false) == nil)
        #expect(Args.int(.number(500), default: 50, max: 200) == 200)
        #expect(Args.int(.number(-3), default: 50, max: 200) == 1)
        #expect(Args.int(nil, default: 50, max: 200) == 50)
    }

    @Test func numericLimitsClampPriorToIntegerConversion() {
        #expect(Args.int(.number(1e20), default: 5, max: 50) == 50)
        #expect(Args.int(.number(Double(Int.max)), default: 5, max: Int.max) == Int.max)
        #expect(Args.int(.number(-1e20), default: 5, max: 50) == 1)
        #expect(Args.int(.number(.infinity), default: 5, max: 50) == 5)
        #expect(Args.int(.number(.nan), default: 5, max: 50) == 5)
    }

    @Test func schemaForbidsExtraProperties() {
        let s = Args.schema(["a": Args.stringProp], required: ["a"])
        #expect(s["additionalProperties"] == false)
    }
}
