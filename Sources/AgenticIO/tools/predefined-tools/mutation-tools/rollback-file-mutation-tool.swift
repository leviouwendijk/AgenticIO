import Agentic
import AgenticExecution
import AgenticWorkspace
import Difference
import Foundation
import Primitives
import Writers

public struct RollbackFileMutationTool: AgentTool {
    public typealias Input = AgentFileMutationRollbackInput
    public typealias Output = AgentFileMutationRollbackOutput

    public let identifier: AgentToolIdentifier = .rollback_file_mutation
    public let description = "Roll back a recorded file mutation."
    public let risk: ActionRisk = .boundedmutate

    public let store: any AgentFileMutationStore
    public let recorder: AgentFileMutationRecorder

    public init(
        store: any AgentFileMutationStore,
        recorder: AgentFileMutationRecorder
    ) {
        self.store = store
        self.recorder = recorder
    }

    public func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {

        return try await AgentFileMutationPreflight.rollback(
            input,
            store: store,
            workspace: context.workspace,
            recorder: recorder
        ).toolPreflight
    }

    

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {

        let sourceID = try input.normalizedMutationUUID()
        let sourceIDString = sourceID.uuidString.lowercased()

        guard let source = try await store.load(
            id: sourceID
        ) else {
            throw AgentFileMutationRollbackError.mutationNotFound(
                sourceIDString
            )
        }

        guard source.rollbackable else {
            throw AgentFileMutationRollbackError.mutationNotRollbackable(
                sourceIDString
            )
        }

        guard let writerRecord = try await store.loadWriterRecord(
            for: source
        ) else {
            throw AgentFileMutationRollbackError.missingWriterRecord(
                sourceIDString
            )
        }

        let rollback = try StandardWriter(
            source.target
        ).rollback(
            writerRecord,
            options: try recorder.writeOptions(),
            checkTarget: input.checkTarget
        )

        let recorded = try await recorder.record(
            writerRecord: rollbackRecordingRecord(
                rollback
            ),
            writeResult: rollback.writeResult,
            rootID: source.rootID,
            path: source.path,
            context: AgentFileMutationContext(
                toolContext: context,
                additionalMetadata: [
                    "toolName": identifier.rawValue,
                    "intent_action": "rollback",
                    "intent_action_type": FileMutationIntentAction.rollback.actionType,
                    "rollback_of": source.id.uuidString.lowercased(),
                    "rollback_source_writer_record_id": source.writerRecordID.uuidString.lowercased(),
                    "rollback_strategy": rollback.preview.strategy.rawValue
                ]
            )
        )

        return AgentFileMutationRollbackOutput(
            sourceMutationID: source.id,
            rollbackMutationID: recorded.mutation.id,
            writerRecordID: recorded.writerRecord.id,
            targetPath: recorded.mutation.target.standardizedFileURL.path,
            rollbackStrategy: rollback.preview.strategy,
            artifactIDs: recorded.mutation.artifactIDs
        )
        
    }
}

private extension RollbackFileMutationTool {
    func rollbackRecordingRecord(
        _ rollback: WriteMutationRollbackResult
    ) -> WriteMutationRecord {
        let before = rollback.preview.current.content ?? ""
        let after = rollback.preview.rollbackContent
        let difference = TextDiffer.diff(
            old: before,
            new: after,
            oldName: "current/\(rollback.preview.target.lastPathComponent)",
            newName: "rollback/\(rollback.preview.target.lastPathComponent)"
        )

        return .init(
            id: rollback.rollbackRecord.id,
            target: rollback.rollbackRecord.target,
            createdAt: rollback.rollbackRecord.createdAt,
            operationKind: rollback.rollbackRecord.operationKind,
            before: .init(
                content: before,
                storeContent: true
            ),
            after: .init(
                content: after,
                storeContent: true
            ),
            difference: .init(
                insertions: difference.insertions,
                deletions: difference.deletions,
                changeCount: difference.changeCount,
                hasChanges: difference.hasChanges
            ),
            backupRecord: rollback.rollbackRecord.backupRecord,
            writeResult: rollback.rollbackRecord.writeResult,
            rollbackOperations: rollback.rollbackRecord.rollbackOperations,
            rollbackGuard: rollback.rollbackRecord.rollbackGuard,
            metadata: rollback.rollbackRecord.metadata
        )
    }
}