import Foundation
import Contracts

/// Runs AppleScript in-process so TCC "Automation" prompts are attributed to Asky itself.
/// Calls are serialized; arguments are only ever embedded through `AppleScript.literal`.
public actor AppleScriptRunner {
    public static let shared = AppleScriptRunner()

    public func run(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else { throw ToolError(.adapterFailure, CoreLocalization.text("脚本无法编译")) }
        var info: NSDictionary?
        let result = script.executeAndReturnError(&info)
        if let info {
            let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
            let msg = (info[NSAppleScript.errorMessage] as? String) ?? CoreLocalization.text("未知错误")
            throw AppleScript.mapError(code: code, message: msg)
        }
        return result.stringValue ?? ""
    }
}

public enum AppleScript {
    /// Field / record separators used in script output (ASCII US / RS), which never appear in titles or URLs in practice.
    public static let fieldSep: Character = "\u{1F}"
    public static let recordSep: Character = "\u{1E}"

    /// Quotes a value as an AppleScript string literal. Backslashes and quotes are escaped; nothing else is interpreted.
    public static func literal(_ s: String) -> String {
        var out = "\""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            default: out.append(ch)
            }
        }
        return out + "\""
    }

    public static func parseRecords(_ s: String, fields: Int) -> [[String]] {
        s.split(separator: recordSep, omittingEmptySubsequences: true).compactMap { rec in
            let f = rec.split(separator: fieldSep, omittingEmptySubsequences: false).map(String.init)
            return f.count == fields ? f : nil
        }
    }

    static func mapError(code: Int, message: String) -> ToolError {
        switch code {
        // Application-defined error preserves Chrome page-reading permission guidance.
        case -27001: ToolError(.permissionDenied, message)
        case -1743: ToolError(.permissionDenied, CoreLocalization.text("未获得自动化授权（系统设置 › 隐私与安全性 › 自动化）"))
        case -600, -609: ToolError(.unavailable, CoreLocalization.text("目标应用未运行"))
        case -1728, -1719: ToolError(.targetNotFound, message)
        case -1712: ToolError(.timeout, CoreLocalization.text("目标应用响应超时"))
        default: ToolError(.adapterFailure, CoreLocalization.format("Apple Events 错误 %@：%@", String(describing: code), String(describing: message)))
        }
    }

    /// AppleScript handler shared by scripts that serialize records.
    static let joinHandler = """
    on kjoin(xs, d)
      set AppleScript's text item delimiters to d
      set r to xs as text
      set AppleScript's text item delimiters to ""
      return r
    end kjoin
    """
    static let us = "(character id 31)"
    static let rs = "(character id 30)"
}
