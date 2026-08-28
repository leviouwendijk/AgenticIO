import Agentic
import AgenticWorkspace
import Foundation
import Path
import Writers

public struct AgentFileMutationDraft: Sendable, Hashable {
    public let id: UUID
    public let sessionID: String
    public let toolCallID: String?
    public let preparedIntentID: PreparedIntentIdentifier?
    public let createdAt: Date
    public let rootID: PathAccessRootIdentifier?
    public let scopedPath: ScopedPath?
    public let writerRecord: WriteMutationRecord
    public let artifactIDs: [String]
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        sessionID: String,
        toolCallID: String? = nil,
        preparedIntentID: PreparedIntentIdentifier? = nil,
        createdAt: Date = Date(),
        rootID: PathAccessRootIdentifier? = nil,
        scopedPath: ScopedPath? = nil,
        writerRecord: WriteMutationRecord,
        artifactIDs: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.toolCallID = toolCallID
        self.preparedIntentID = preparedIntentID
        self.createdAt = createdAt
        self.rootID = rootID
        self.scopedPath = scopedPath
        self.writerRecord = writerRecord
        self.artifactIDs = artifactIDs
        self.metadata = metadata
    }
}

public struct AgentFileMutationRecord: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let sessionID: String
    public let toolCallID: String?
    public let preparedIntentID: PreparedIntentIdentifier?
    public let createdAt: Date
    public let rootID: PathAccessRootIdentifier?
    public let scopedPath: ScopedPath?

    public let writerRecord: WriteStoredRecord
    public let operationKind: WriteMutationOperationKind
    public let resource: WriteResourceChangeKind
    public let delta: WriteDeltaKind
    public let rollbackable: Bool

    public let artifactIDs: [String]
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        sessionID: String,
        toolCallID: String? = nil,
        preparedIntentID: PreparedIntentIdentifier? = nil,
        createdAt: Date = Date(),
        rootID: PathAccessRootIdentifier? = nil,
        scopedPath: ScopedPath? = nil,
        writerRecord: WriteStoredRecord,
        operationKind: WriteMutationOperationKind,
        resource: WriteResourceChangeKind,
        delta: WriteDeltaKind,
        rollbackable: Bool,
        artifactIDs: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.toolCallID = toolCallID
        self.preparedIntentID = preparedIntentID
        self.createdAt = createdAt
        self.rootID = rootID
        self.scopedPath = scopedPath
        self.writerRecord = writerRecord
        self.operationKind = operationKind
        self.resource = resource
        self.delta = delta
        self.rollbackable = rollbackable
        self.artifactIDs = artifactIDs
        self.metadata = metadata
    }
}

public extension AgentFileMutationRecord {
    var writerRecordID: UUID {
        writerRecord.id
    }

    var target: URL {
        writerRecord.target
    }

    var hasChanges: Bool {
        delta != .unchanged
    }

    var relativePath: String? {
        scopedPath?.presentingRelative(
            filetype: true
        )
    }

    func withArtifactIDs(
        _ artifactIDs: [String]
    ) -> Self {
        .init(
            id: id,
            sessionID: sessionID,
            toolCallID: toolCallID,
            preparedIntentID: preparedIntentID,
            createdAt: createdAt,
            rootID: rootID,
            scopedPath: scopedPath,
            writerRecord: writerRecord,
            operationKind: operationKind,
            resource: resource,
            delta: delta,
            rollbackable: rollbackable,
            artifactIDs: artifactIDs,
            metadata: metadata
        )
    }
}
