import Foundation
import Contracts

/// The same validation applies before invoking native and legacy plugin code.
enum PluginArguments {
    static func validate(_ value: JSONValue, schema: JSONValue, path: String = "arguments") throws {
        func fail(_ reason: String) throws { throw ToolError(.invalidArguments, "\(path): \(reason)") }
        if let type = schema["type"]?.stringValue {
            let matches: Bool
            switch (type, value) {
            case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("number", .number), ("null", .null): matches = true
            case ("integer", .number(let n)): matches = n.isFinite && n.rounded() == n
            default: matches = false
            }
            if !matches { try fail("expected \(type)") }
        }
        if let options = schema["enum"]?.arrayValue, !options.contains(value) { try fail("invalid option") }
        if let text = value.stringValue {
            if Double(text.count) < (schema["minLength"]?.numberValue ?? 0) { try fail("value is too short") }
            if let max = schema["maxLength"]?.numberValue, Double(text.count) > max { try fail("value is too long") }
        }
        if let object = value.objectValue {
            for key in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] where object[key] == nil { try fail("\(key): required") }
            for (key, val) in object {
                if schema["additionalProperties"] == false && schema["properties"]?[key] == nil { try fail("\(key): unexpected property") }
                try validate(val, schema: schema["properties"]?[key] ?? [:], path: path + "." + key)
            }
        }
        if let array = value.arrayValue, let items = schema["items"] {
            for (index, val) in array.enumerated() { try validate(val, schema: items, path: path + "[\(index)]") }
        }
    }
}
