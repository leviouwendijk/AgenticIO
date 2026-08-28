import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Path
import Writers

public struct AgentFileMutationContext: Sendable, Codable, Hashable {
    public var rootID: PathAccessRootIdentifier?
    public var toolCallID: String?
    public var preparedIntentID: PreparedIntentIdentifier?
    public var metadata: [String: String]

    public init(
        rootID: PathAccessRootIdentifier? = nil,
        toolCallID: String? = nil,
        preparedIntentID: PreparedIntentIdentifier? = nil,
        metadata: [String: String] = [:]
    ) {
        self.rootID = rootID
        self.toolCallID = toolCallID
        self.preparedIntentID = preparedIntentID
        self.metadata = metadata
    }

    public static let empty = Self()
}

public struct AgentFileEditOptions: Sendable {
    public var encoding: String.Encoding
    public var write: SafeWriteOptions?
    public var mode: StandardEditMode
    public var mutation: AgentFileMutationContext

    public init(
        encoding: String.Encoding = .utf8,
        write: SafeWriteOptions? = nil,
        mode: StandardEditMode = .sequential,
        mutation: AgentFileMutationContext = .empty
    ) {
        self.encoding = encoding
        self.write = write
        self.mode = mode
        self.mutation = mutation
    }

    public static let `default` = Self()
}

public extension AgentFileMutationContext {
    init(
        toolContext: AgentToolExecutionContext,
        additionalMetadata: [String: String] = [:]
    ) {
        var metadata = toolContext.metadata

        if let sessionID = toolContext.sessionID {
            metadata["session_id"] = sessionID
        }

        if let toolCallID = toolContext.toolCallID {
            metadata["tool_call_id"] = toolCallID
        }

        if let preparedIntentID = toolContext.preparedIntentID {
            metadata["prepared_intent_id"] = preparedIntentID.rawValue
        }

        metadata["execution_mode"] = toolContext.executionMode.rawValue

        metadata.merge(
            additionalMetadata
        ) { _, new in
            new
        }

        self.init(
            toolCallID: toolContext.toolCallID,
            preparedIntentID: toolContext.preparedIntentID,
            metadata: metadata
        )
    }
}
