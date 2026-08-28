import Agentic
import Foundation
import Writers

public struct AgentFileMutationResult: Sendable, Codable, Hashable {
    public let mutation: AgentFileMutationRecord
    public let writerRecord: WriteMutationRecord
    public let writeResult: SafeWriteResult?
    public let editResult: StandardEditResult?
    public let artifacts: [AgentArtifact]

    public init(
        mutation: AgentFileMutationRecord,
        writerRecord: WriteMutationRecord,
        writeResult: SafeWriteResult? = nil,
        editResult: StandardEditResult? = nil,
        artifacts: [AgentArtifact] = []
    ) {
        self.mutation = mutation
        self.writerRecord = writerRecord
        self.writeResult = writeResult
        self.editResult = editResult
        self.artifacts = artifacts
    }
}

public extension AgentFileMutationResult {
    var writerRecordID: UUID {
        mutation.writerRecordID
    }

    var mutationID: UUID {
        mutation.id
    }

    var storedWriterRecord: WriteStoredRecord {
        mutation.writerRecord
    }
}
