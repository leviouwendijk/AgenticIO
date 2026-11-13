import Agentic
import Workspace
import Foundation
import Path
import Writers

public struct AgentFileMutationContext: Sendable, Codable, Hashable {
    public var rootID: PathAccessRootIdentifier?
    public var callID: String?
    public var preparedIntentID: PreparedIntentIdentifier?
    public var metadata: [String: String]

    public init(
        rootID: PathAccessRootIdentifier? = nil,
        callID: String? = nil,
        preparedIntentID: PreparedIntentIdentifier? = nil,
        metadata: [String: String] = [:]
    ) {
        self.rootID = rootID
        self.callID = callID
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

