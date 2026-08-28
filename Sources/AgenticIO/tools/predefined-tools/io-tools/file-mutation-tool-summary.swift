import Agentic
import Foundation
import Writers

public struct AgentFileMutationToolSummary: Sendable, Codable, Hashable {
    public let mutationID: UUID
    public let writerRecordID: UUID
    public let artifactIDs: [String]
    public let backupPolicy: AgentFileBackupPolicy
    public let payloadPolicy: WriteMutationPayloadPolicy
    public let resource: WriteResourceChangeKind
    public let delta: WriteDeltaKind
    public let rollbackable: Bool

    public init(
        mutationID: UUID,
        writerRecordID: UUID,
        artifactIDs: [String],
        backupPolicy: AgentFileBackupPolicy,
        payloadPolicy: WriteMutationPayloadPolicy,
        resource: WriteResourceChangeKind,
        delta: WriteDeltaKind,
        rollbackable: Bool
    ) {
        self.mutationID = mutationID
        self.writerRecordID = writerRecordID
        self.artifactIDs = artifactIDs
        self.backupPolicy = backupPolicy
        self.payloadPolicy = payloadPolicy
        self.resource = resource
        self.delta = delta
        self.rollbackable = rollbackable
    }
}

public extension AgentFileMutationToolSummary {
    init(
        result: AgentFileMutationResult,
        policy: AgentFileMutationPolicy
    ) {
        self.init(
            mutationID: result.mutation.id,
            writerRecordID: result.mutation.writerRecordID,
            artifactIDs: result.mutation.artifactIDs,
            backupPolicy: policy.backupPolicy,
            payloadPolicy: policy.payloadPolicy,
            resource: result.mutation.resource,
            delta: result.mutation.delta,
            rollbackable: result.mutation.rollbackable
        )
    }
}
