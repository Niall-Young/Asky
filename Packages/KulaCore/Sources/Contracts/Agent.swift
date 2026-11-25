import Foundation

public enum CapabilityStatus: String, Sendable, Codable {
    case unknown, available, unavailable
}

public struct ModelCapabilities: Sendable, Hashable, Codable {
    public var text: CapabilityStatus
    public var image: CapabilityStatus
    public var tools: CapabilityStatus
    public var checkedAt: Date?
    public init(text: CapabilityStatus = .unknown, image: CapabilityStatus = .unknown,
                tools: CapabilityStatus = .unknown, checkedAt: Date? = nil) {
        self.text = text
        self.image = image
        self.tools = tools
        self.checkedAt = checkedAt
    }
}

/// The API key itself never lives here — only a Keychain account reference.
public struct ModelConfiguration: Sendable, Hashable, Codable {
    public var baseURL: URL
    public var modelName: String
    public var credentialRef: String
    public var capabilities: ModelCapabilities
    public init(baseURL: URL, modelName: String, credentialRef: String, capabilities: ModelCapabilities = .init()) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.credentialRef = credentialRef
        self.capabilities = capabilities
    }
}

public enum AttachmentKind: String, Sendable, Codable {
    case image, text, file
}

/// Attachments are passed by file reference; never as repeated Base64 copies through layers.
public struct AttachmentRef: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var kind: AttachmentKind
    public var path: String
    public var mimeType: String
    public var byteSize: Int
    public var temporary: Bool
    public init(id: String = UUID().uuidString, kind: AttachmentKind, path: String, mimeType: String,
                byteSize: Int, temporary: Bool) {
        self.id = id
        self.kind = kind
        self.path = path
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.temporary = temporary
    }
}

public struct AgentRequest: Sendable, Hashable, Codable {
    public var sessionID: String
    public var taskID: String
    public var text: String
    public var attachments: [AttachmentRef]
    public var context: [ContextSnippet]
    public init(sessionID: String, taskID: String = UUID().uuidString, text: String,
                attachments: [AttachmentRef] = [], context: [ContextSnippet] = []) {
        self.sessionID = sessionID
        self.taskID = taskID
        self.text = text
        self.attachments = attachments
        self.context = context
    }
}

/// An authorised context fragment with provenance, as assembled by the native side.
public struct ContextSnippet: Sendable, Hashable, Codable {
    public var sourceID: String
    public var text: String
    public init(sourceID: String, text: String) {
        self.sourceID = sourceID
        self.text = text
    }
}

public enum AgentTaskState: String, Sendable, Codable {
    case starting, running, compacting, awaitingInput, awaitingConfirmation, completed, cancelled, failed, pendingVerification

    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed, .pendingVerification: true
        default: false
        }
    }
}

public enum AgentEvent: Sendable, Hashable {
    case taskState(taskID: String, AgentTaskState)
    case textDelta(taskID: String, String)
    case message(taskID: String, String)
    case toolCall(taskID: String, ActionRequest)
    case toolResult(taskID: String, ExecutionResult)
    case clarification(taskID: String, question: String)
    case confirmationRequired(taskID: String, ConfirmationRequest)
    case error(taskID: String?, String)
    case runtimeExited(code: Int32)
}
