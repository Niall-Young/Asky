import Foundation
import Contracts

/// Shared argument helpers so every entry point interprets dates, time zones and targets the same way.
public enum Args {
    /// Accepts ISO 8601 with offset ("2026-10-10T15:00:00+08:00"), or local wall time without offset
    /// ("2026-10-10T15:00[:00]" / "2026-10-10 15:00"), interpreted in `timeZone`.
    public static func date(_ v: JSONValue?, timeZone: TimeZone = .current) -> Date? {
        guard let s = v?.stringValue?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    public static func iso(_ d: Date, timeZone: TimeZone = .current) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    public static func string(_ v: JSONValue?, _ name: String, required: Bool = true) throws -> String? {
        if let s = v?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        if required { throw ToolError(.invalidArguments, CoreLocalization.format("缺少参数 %@", String(describing: name))) }
        return nil
    }

    public static func requiredString(_ args: JSONValue, _ name: String) throws -> String {
        try string(args[name], name)!
    }

    public static func requiredDate(_ args: JSONValue, _ name: String) throws -> Date {
        guard let d = date(args[name]) else { throw ToolError(.invalidArguments, CoreLocalization.format("参数 %@ 不是有效日期时间", String(describing: name))) }
        return d
    }

    public static func int(_ v: JSONValue?, default def: Int, max: Int) -> Int {
        guard let n = v?.numberValue, n.isFinite else { return def }
        if n <= 1 { return 1 }
        if n >= Double(max) { return Swift.max(1, max) }
        return Int(n)
    }

    /// JSON-schema helper.
    public static func schema(_ props: [String: JSONValue], required: [String]) -> JSONValue {
        ["type": "object", "properties": .object(props), "required": .array(required.map { .string($0) }),
         "additionalProperties": false]
    }

    public static let isoDateProp: JSONValue = ["type": "string", "description": .string(CoreLocalization.text("ISO 8601；无时区偏移时按用户当前时区解释"))]
    public static let stringProp: JSONValue = ["type": "string"]
    public static let intProp: JSONValue = ["type": "integer"]
}
