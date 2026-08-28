import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Primitives
import Difference
import Writers

public enum FileMutationIntentExecutionError: Error, Sendable, LocalizedError {
    case unsupportedActionType(String)
    case missingExactInputs(PreparedIntentIdentifier)

    public var errorDescription: String? {
        switch self {
        case .unsupportedActionType(let actionType):
            return "Unsupported file mutation prepared intent action type '\(actionType)'."

        case .missingExactInputs(let id):
            return "Prepared file mutation intent '\(id.rawValue)' is missing exact replay inputs."
        }
    }
}

public struct FileMutationIntentExecutor: Sendable {
    public static let name = "file_mutation_intent_executor"

    public let manager: PreparedIntentManager
    public let workspace: AgentWorkspace
    public let recorder: AgentFileMutationRecorder

    public init(
        manager: PreparedIntentManager,
        workspace: AgentWorkspace,
        recorder: AgentFileMutationRecorder
    ) {
        self.manager = manager
        self.workspace = workspace
        self.recorder = recorder
    }

    public func execute(
        _ id: PreparedIntentIdentifier
    ) async throws -> PreparedIntent {
        let intent = try await manager.executableIntent(
            id: id
        )
        let startedAt = Date()

        guard let action = FileMutationIntentAction(
            actionType: intent.actionType
        ) else {
            try await fail(
                intent: intent,
                startedAt: startedAt,
                summary: "Prepared file mutation intent has an unsupported action type.",
                error: FileMutationIntentExecutionError.unsupportedActionType(
                    intent.actionType
                ),
                executionToolName: nil,
                metadata: [
                    "executor": Self.name,
                    "actionType": intent.actionType
                ]
            )
        }

        guard let exactInputs = intent.reviewPayload.exactInputs else {
            try await fail(
                intent: intent,
                startedAt: startedAt,
                summary: "Prepared file mutation intent is missing exact replay inputs.",
                error: FileMutationIntentExecutionError.missingExactInputs(
                    intent.id
                ),
                executionToolName: action.toolName,
                metadata: metadata(
                    intent: intent,
                    action: action
                )
            )
        }

        do {
            let approval = try AgentFileMutationApproval.approval(
                for: intent,
                action: action
            )

            try approval?.requireCurrentFile(
                in: workspace,
                toolName: action.toolName
            )

            let result = try await execute(
                action,
                intentID: intent.id,
                exactInputs: exactInputs
            )

            return try await manager.recordExecution(
                id: intent.id,
                record: .init(
                    intentID: intent.id,
                    executionToolName: action.toolName,
                    status: .succeeded,
                    summary: "Executed prepared file mutation \(action.rawValue).",
                    startedAt: startedAt,
                    completedAt: Date(),
                    result: result,
                    metadata: metadata(
                        intent: intent,
                        action: action
                    )
                )
            )
        } catch {
            try await fail(
                intent: intent,
                startedAt: startedAt,
                summary: "Prepared file mutation execution failed.",
                error: error,
                executionToolName: action.toolName,
                metadata: metadata(
                    intent: intent,
                    action: action
                )
            )
        }
    }
}

private extension FileMutationIntentExecutor {
    func execute(
        _ action: FileMutationIntentAction,
        intentID: PreparedIntentIdentifier,
        exactInputs: JSONValue
    ) async throws -> JSONValue {
        switch action {
        case .write:
            let decoded = try JSONToolBridge.decode(
                WriteFileToolInput.self,
                from: exactInputs
            )

            return try await WriteFileTool(
                recorder: recorder,
                context: mutationContext(
                    intentID: intentID,
                    action: action
                )
            ).call(
                input: try JSONToolBridge.encode(
                    decoded
                ),
                workspace: workspace
            )

        case .edit:
            let decoded = try JSONToolBridge.decode(
                EditFileToolInput.self,
                from: exactInputs
            )

            return try await EditFileTool(
                recorder: recorder,
                context: mutationContext(
                    intentID: intentID,
                    action: action
                )
            ).call(
                input: try JSONToolBridge.encode(
                    decoded
                ),
                workspace: workspace
            )

        case .rollback:
            let decoded = try JSONToolBridge.decode(
                AgentFileMutationRollbackInput.self,
                from: exactInputs
            )

            return try await executeRollback(
                decoded,
                intentID: intentID,
                action: action
            )
        }
    }

    func executeRollback(
        _ input: AgentFileMutationRollbackInput,
        intentID: PreparedIntentIdentifier,
        action: FileMutationIntentAction
    ) async throws -> JSONValue {
        let sourceID = try input.normalizedMutationUUID()
        let sourceIDString = sourceID.uuidString.lowercased()

        guard let source = try await recorder.store.load(
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

        guard let writerRecord = try await recorder.store.loadWriterRecord(
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
            context: mutationContext(
                intentID: intentID,
                action: action
            ).withRollbackMetadata(
                sourceMutationID: source.id,
                sourceWriterRecordID: source.writerRecordID,
                strategy: rollback.preview.strategy
            )
        )

        return try JSONToolBridge.encode(
            AgentFileMutationRollbackOutput(
                sourceMutationID: source.id,
                rollbackMutationID: recorded.mutation.id,
                writerRecordID: recorded.writerRecord.id,
                targetPath: recorded.mutation.target.standardizedFileURL.path,
                rollbackStrategy: rollback.preview.strategy,
                artifactIDs: recorded.mutation.artifactIDs
            )
        )
    }

    func mutationContext(
        intentID: PreparedIntentIdentifier,
        action: FileMutationIntentAction
    ) -> AgentFileMutationContext {
        .init(
            preparedIntentID: intentID,
            metadata: [
                "executor": Self.name,
                "prepared_intent_id": intentID.rawValue,
                "intent_action": action.rawValue,
                "intent_action_type": action.actionType
            ]
        )
    }

    func metadata(
        intent: PreparedIntent,
        action: FileMutationIntentAction
    ) -> [String: String] {
        [
            "executor": Self.name,
            "prepared_intent_id": intent.id.rawValue,
            "action": action.rawValue,
            "actionType": intent.actionType,
            "toolName": action.toolName
        ]
    }

    func fail(
        intent: PreparedIntent,
        startedAt: Date,
        summary: String,
        error: Error,
        executionToolName: String?,
        metadata: [String: String]
    ) async throws -> Never {
        _ = try await manager.recordExecution(
            id: intent.id,
            record: .init(
                intentID: intent.id,
                executionToolName: executionToolName,
                status: .failed,
                summary: summary,
                startedAt: startedAt,
                completedAt: Date(),
                result: nil,
                errorMessage: String(
                    describing: error
                ),
                metadata: metadata
            )
        )

        throw error
    }

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

internal extension AgentFileMutationContext {
    func withRollbackMetadata(
        sourceMutationID: UUID,
        sourceWriterRecordID: UUID,
        strategy: WriteMutationRollbackStrategy
    ) -> Self {
        var copy = self

        copy.metadata["rollback_of"] = sourceMutationID.uuidString.lowercased()
        copy.metadata["rollback_source_writer_record_id"] = sourceWriterRecordID.uuidString.lowercased()
        copy.metadata["rollback_strategy"] = strategy.rawValue

        return copy
    }
}
