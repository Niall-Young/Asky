import Foundation
import CryptoKit

public enum DataSourceID: String, Sendable, Codable, CaseIterable {
    case calendar, reminders, notes, contacts, chrome, shortcuts, messages, terminal, memory, clipboard, maps, plugins, web
}

public enum ToolEffect: String, Sendable, Codable {
    case read
    case write
}

/// How a write is gated. Reads never need confirmation (they still need source checks).
public enum ConfirmationRule: String, Sendable, Codable {
    /// Explicit user-requested creation may run directly; modifications / deletes / batch always confirm.
    case createDirectOtherwiseConfirm
    /// Explicit user requests may execute without an extra prompt; external MCP still confirms.
    case explicitDirectOtherwiseConfirm
    /// Always requires native confirmation.
    case always
    /// Never needs confirmation (read tools).
    case never
}

public enum WriteKind: String, Sendable, Codable {
    case create, modify, delete, batch, handoff
}

public struct ToolDefinition: Sendable, Hashable, Codable {
    public var name: String
    public var summary: String
    public var inputSchema: JSONValue
    public var source: DataSourceID
    public var effect: ToolEffect
    public var writeKind: WriteKind?
    public var confirmation: ConfirmationRule
    /// Whether the tool may be offered to external MCP clients at all.
    public var externallyExposable: Bool
    /// Whether the tool may be offered to the Agent runtime.
    public var agentExposable: Bool

    public init(name: String, summary: String, inputSchema: JSONValue = ["type": "object"],
                source: DataSourceID, effect: ToolEffect, writeKind: WriteKind? = nil,
                confirmation: ConfirmationRule, externallyExposable: Bool, agentExposable: Bool = true) {
        self.name = name
        self.summary = summary
        self.inputSchema = inputSchema
        self.source = source
        self.effect = effect
        self.writeKind = writeKind
        self.confirmation = confirmation
        self.externallyExposable = externallyExposable
        self.agentExposable = agentExposable
    }
}

/// Who is asking. Identity is established by the native side (process / XPC / instance credential),
/// never by a client-declared name.
public enum CallerOrigin: Sendable, Hashable, Codable {
    case launcher
    case agent(sessionID: String)
    case mcp(instanceID: String)
}

public enum UserIntent: String, Sendable, Codable {
    /// The user explicitly asked for this operation.
    case explicitRequest
    /// The AI derived the operation; it must be shown as a suggestion first.
    case aiSuggested
}

/// A request to execute a tool. Deliberately has no "approved"/"confirmed" field.
public struct ActionRequest: Sendable, Hashable, Codable {
    public var requestID: String
    public var tool: String
    public var arguments: JSONValue
    public var taskID: String?
    public var origin: CallerOrigin
    public var intent: UserIntent

    /// Keys that untrusted callers may try to smuggle in; stripped before policy evaluation.
    public static let untrustedKeys: Set<String> = ["confirmed", "approved", "userConfirmed", "_confirmed", "confirmation"]

    public init(requestID: String = UUID().uuidString, tool: String, arguments: JSONValue,
                taskID: String? = nil, origin: CallerOrigin, intent: UserIntent) {
        self.requestID = requestID
        self.tool = tool
        self.arguments = arguments.removingKeys(Self.untrustedKeys)
        self.taskID = taskID
        self.origin = origin
        self.intent = intent
    }

    /// Digest binding a confirmation to exact tool + arguments.
    public var argumentsDigest: String {
        var data = Data(tool.utf8)
        data.append(arguments.canonicalData())
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ConfirmationRequest: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var requestID: String
    public var tool: String
    public var target: String
    public var changes: [String]
    public var note: String?
    public var title: String?
    public var details: String?
    public var argumentsDigest: String
    public var origin: CallerOrigin

    public init(id: String = UUID().uuidString, requestID: String, tool: String, target: String,
                changes: [String], note: String? = nil, argumentsDigest: String, origin: CallerOrigin, title: String? = nil, details: String? = nil) {
        self.id = id
        self.requestID = requestID
        self.tool = tool
        self.target = target
        self.changes = changes
        self.note = note
        self.title = title
        self.details = details
        self.argumentsDigest = argumentsDigest
        self.origin = origin
    }
}

public enum ConfirmationDecision: String, Sendable, Codable {
    case approved, rejected
}

public enum ExecutionStatus: String, Sendable, Codable {
    case completed
    case rejected
    case cancelled
    case failed
    case pendingVerification
    case awaitingConfirmation
    case suggestion
}

public enum ToolErrorCode: String, Sendable, Codable {
    case unknownTool
    case invalidArguments
    case permissionDenied
    case sourceDisabled
    case notExposed
    case targetNotFound
    case targetReadOnly
    case ambiguousTarget
    case conflict
    case adapterFailure
    case timeout
    case unavailable
    case protocolError
    case userRejected
    case cancelled
}

public struct ToolError: Error, LocalizedError, Sendable, Hashable, Codable {
    public var errorDescription: String? { message }
    public var code: ToolErrorCode
    public var message: String
    public init(_ code: ToolErrorCode, _ message: String) {
        self.code = code
        self.message = message
    }
}

public struct ExecutionResult: Sendable, Hashable, Codable {
    public var requestID: String
    public var status: ExecutionStatus
    public var targets: [TargetRef]
    public var output: JSONValue?
    public var readback: JSONValue?
    public var error: ToolError?
    public var confirmation: ConfirmationRequest?

    public init(requestID: String, status: ExecutionStatus, targets: [TargetRef] = [], output: JSONValue? = nil,
                readback: JSONValue? = nil, error: ToolError? = nil, confirmation: ConfirmationRequest? = nil) {
        self.requestID = requestID
        self.status = status
        self.targets = targets
        self.output = output
        self.readback = readback
        self.error = error
        self.confirmation = confirmation
    }

    public static func failure(_ requestID: String, _ code: ToolErrorCode, _ message: String,
                               status: ExecutionStatus = .failed) -> ExecutionResult {
        ExecutionResult(requestID: requestID, status: status, error: ToolError(code, message))
    }
}
