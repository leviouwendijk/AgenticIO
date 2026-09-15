import AgenticExecution
import AgenticWorkspace
import Foundation
import Path
import Writers

public struct PreparedFileMutationExecutor:
    AgentPreparedOperation,
    Sendable
{
    public typealias Plan = PreparedFileMutationOperation.Plan

    public static let schema = PreparedFileMutationOperation.schema

    public enum WritersResult: Sendable, Codable, Hashable {
        case mutation(StandardMutationResult)
        case rollback(
            sourceMutationID: UUID,
            result: WriteMutationRollbackResult
        )
    }

    public struct Result: Sendable, Codable, Hashable {
        public let action: FileMutationIntentAction
        public let writers: WritersResult
        public let recordedMutations: [AgentFileMutationRecord]

        public init(
            action: FileMutationIntentAction,
            writers: WritersResult,
            recordedMutations: [AgentFileMutationRecord]
        ) {
            self.action = action
            self.writers = writers
            self.recordedMutations = recordedMutations
        }
    }

    public let recorder: AgentFileMutationRecorder?

    public init(
        recorder: AgentFileMutationRecorder? = nil
    ) {
        self.recorder = recorder
    }

    public func execute(
        _ plan: Plan,
        context: PreparedOperation.Context
    ) async throws -> Result {
        let workspace = try FileToolSupport.requireWorkspace(
            context.workspace,
            toolName: plan.action.authorizationToolName
        )
        let authorized = try authorize(
            plan.authorizations,
            workspace: workspace,
            toolName: plan.action.authorizationToolName
        )
        let writeContext = recorder?.writeExecutionContext()
            ?? .init()
        let mutationContext = mutationContext(
            from: context,
            action: plan.action
        )

        switch plan.work {
        case .mutation(let writersPlan, let failurePolicy):
            try requireAuthorizedTargets(
                writersPlan.entries.map(\.target),
                authorized: authorized
            )

            let writersResult = WorkspaceWriter(
                access: workspace.accessController.paths
            ).mutations.apply(
                writersPlan,
                options: .init(
                    failure: failurePolicy
                ),
                context: writeContext
            )
            let recorded = try await record(
                writersResult.records,
                authorized: authorized,
                context: mutationContext
            )

            return .init(
                action: plan.action,
                writers: .mutation(
                    writersResult
                ),
                recordedMutations: recorded
            )

        case .rollback(let rollbackPlan, let sourceMutationID):
            try requireAuthorizedTargets(
                [
                    rollbackPlan.record.target,
                ],
                authorized: authorized
            )

            let writersResult = try StandardWriter(
                rollbackPlan.record.target
            ).rollbacks.apply(
                rollbackPlan,
                context: writeContext
            )
            var rollbackContext = mutationContext
            rollbackContext.metadata[
                "rollback_source_mutation_id"
            ] = sourceMutationID.uuidString.lowercased()
            let recorded = try await record(
                [
                    writersResult.rollbackRecord,
                ],
                authorized: authorized,
                context: rollbackContext
            )

            return .init(
                action: plan.action,
                writers: .rollback(
                    sourceMutationID: sourceMutationID,
                    result: writersResult
                ),
                recordedMutations: recorded
            )
        }
    }
}

private extension PreparedFileMutationExecutor {
    func authorize(
        _ authorizations: [PreparedFileMutationOperation.Authorization],
        workspace: AgentWorkspace,
        toolName: String
    ) throws -> [AgenticAuthorizedPath] {
        try authorizations.map { authorization in
            let authorized = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: authorization.rootID,
                path: authorization.path,
                capability: .write,
                toolName: toolName,
                type: .file
            )
            let actual = authorized
                .absoluteURL
                .standardizedFileURL
                .path
            let targetMatches =
                authorization.targetPath == actual
                || authorization.targetPath
                    == authorized.presentationPath

            guard targetMatches else {
                throw PreparedFileMutationExecutionError
                    .authorization_target_changed(
                        rootID: authorization.rootID.rawValue,
                        path: authorization.path,
                        expected: authorization.targetPath,
                        actual: actual
                    )
            }

            return authorized
        }
    }

    func requireAuthorizedTargets(
        _ targets: [URL],
        authorized: [AgenticAuthorizedPath]
    ) throws {
        let planned = Set(
            targets.map {
                $0.standardizedFileURL.path
            }
        )
        let granted = Set(
            authorized.map {
                $0.absoluteURL
                    .standardizedFileURL
                    .path
            }
        )

        guard planned == granted else {
            throw PreparedFileMutationExecutionError
                .authorization_plan_mismatch(
                    planned: planned.sorted(),
                    authorized: granted.sorted()
                )
        }
    }

    func mutationContext(
        from context: PreparedOperation.Context,
        action: FileMutationIntentAction
    ) -> AgentFileMutationContext {
        var metadata = context.metadata

        if let sessionID = context.sessionID {
            metadata["session_id"] = sessionID
        }

        if let preparedIntentID = context.preparedIntentID {
            metadata["prepared_intent_id"] =
                preparedIntentID.rawValue
        }

        metadata["execution_mode"] = "prepared_operation"
        metadata["tool_name"] = action.authorizationToolName
        metadata["intent_action"] = action.rawValue
        metadata["intent_action_type"] =
            action == .rollback
                ? "file_mutation_rollback"
                : "file_mutation_pass"

        return .init(
            preparedIntentID: context.preparedIntentID,
            metadata: metadata
        )
    }

    func record(
        _ records: [WriteMutationRecord],
        authorized: [AgenticAuthorizedPath],
        context: AgentFileMutationContext
    ) async throws -> [AgentFileMutationRecord] {
        guard let recorder else {
            return []
        }

        var out: [AgentFileMutationRecord] = []

        for record in records {
            let target = record.target
                .standardizedFileURL
                .path

            guard let authorization = authorized.first(
                where: {
                    $0.absoluteURL
                        .standardizedFileURL
                        .path == target
                }
            ) else {
                throw PreparedFileMutationExecutionError
                    .mutation_target_not_authorized(
                        target
                    )
            }

            let result = try await recorder.record(
                writerRecord: record,
                rootID: authorization.rootID,
                path: authorization.path,
                context: context
            )

            out.append(
                result.mutation
            )
        }

        return out
    }
}

public enum PreparedFileMutationExecutionError:
    Error,
    Sendable,
    Hashable,
    LocalizedError
{
    case authorization_target_changed(
        rootID: String,
        path: String,
        expected: String,
        actual: String
    )
    case authorization_plan_mismatch(
        planned: [String],
        authorized: [String]
    )
    case mutation_target_not_authorized(
        String
    )

    public var errorDescription: String? {
        switch self {
        case .authorization_target_changed(
            let rootID,
            let path,
            let expected,
            let actual
        ):
            return "Prepared file mutation authorization for root '\(rootID)' path '\(path)' resolved to '\(actual)' instead of prepared target '\(expected)'."

        case .authorization_plan_mismatch(
            let planned,
            let authorized
        ):
            return "Prepared file mutation Writers targets \(planned) do not exactly match fresh Agentic authorizations \(authorized)."

        case .mutation_target_not_authorized(let target):
            return "Prepared file mutation produced a writer record for unauthorized target '\(target)'."
        }
    }
}
