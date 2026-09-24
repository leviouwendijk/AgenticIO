import Agentic
import AgenticIO
import Foundation
import Primitives
import Testing
import Writers

extension AgenticIOFlowTesting {
    static func runFileMutationRollbackPreflight() async throws -> [TestDiagnostic] {
        let env = try RollbackMutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_mutation_rollback_preflight
        )
        defer {
            env.remove()
        }

        let source = try await env.recordSourceMutation(
            path: "rollback-preflight.txt",
            before: "old\n",
            after: "new\n"
        )

        let preflight = try await AgentFileMutationPreflight.rollback(
            .init(
                mutationID: source.mutationID.uuidString.lowercased()
            ),
            store: env.store,
            workspace: env.workspace,
            recorder: env.recorder
        )

        try Expect.equal(
            preflight.action,
            .rollback,
            "rollback preflight action"
        )

        try Expect.equal(
            preflight.path,
            "rollback-preflight.txt",
            "rollback preflight path"
        )

        try Expect.equal(
            preflight.estimatedWriteCount,
            1,
            "rollback preflight estimates one write"
        )

        try Expect.true(
            preflight.willRecordSessionMutation,
            "rollback preflight records session mutation"
        )

        _ = try Expect.notNil(
            preflight.diffPreview,
            "rollback preflight generates diff preview"
        )

        let replayInput = try JSONToolBridge.decode(
            AgentFileMutationRollbackInput.self,
            from: preflight.exactReplayInput
        )

        try Expect.equal(
            replayInput.mutationID,
            source.mutationID.uuidString.lowercased(),
            "rollback preflight captures exact replay input"
        )

        try Expect.equal(
            try env.read("rollback-preflight.txt"),
            "new\n",
            "rollback preflight does not mutate file"
        )

        let mutations = try await env.store.list(
            .all
        )

        try Expect.equal(
            mutations.count,
            1,
            "rollback preflight does not record another mutation"
        )

        return rollbackDiagnostics(
            [
                ("action", preflight.action.rawValue),
                ("target", preflight.path),
                ("preview", "ok")
            ]
        )
    }

    static func runFileMutationRollbackPreflightRejectsMissingID() async throws -> [TestDiagnostic] {
        let env = try RollbackMutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_mutation_rollback_preflight_rejects_missing_id
        )
        defer {
            env.remove()
        }

        try await Expect.throwsError(
            "rollback preflight rejects malformed id"
        ) {
            _ = try await AgentFileMutationPreflight.rollback(
                .init(
                    mutationID: "not-a-uuid"
                ),
                store: env.store,
                workspace: env.workspace,
                recorder: env.recorder
            )
        }

        try await Expect.throwsError(
            "rollback preflight rejects missing id"
        ) {
            _ = try await AgentFileMutationPreflight.rollback(
                .init(
                    mutationID: UUID().uuidString.lowercased()
                ),
                store: env.store,
                workspace: env.workspace,
                recorder: env.recorder
            )
        }

        return rollbackDiagnostics(
            [
                ("malformedID", "rejected"),
                ("missingID", "rejected")
            ]
        )
    }

    static func runPreparedFileMutationRollback() async throws -> [TestDiagnostic] {
        let env = try RollbackMutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.prepared_file_mutation_rollback
        )
        defer {
            env.remove()
        }

        let source = try await env.recordSourceMutation(
            path: "prepared-rollback.txt",
            before: "old\n",
            after: "new\n"
        )

        let preflight = try await AgentFileMutationPreflight.rollback(
            .init(
                mutationID: source.mutationID.uuidString.lowercased()
            ),
            store: env.store,
            workspace: env.workspace,
            recorder: env.recorder
        )

        let intent = try await FileMutationIntentBuilder(
            sessionID: env.sessionID
        ).create(
            preflight,
            using: env.intentManager
        )

        try Expect.equal(
            intent.status,
            .pending_review,
            "prepared rollback intent is pending review"
        )

        try Expect.equal(
            intent.actionType,
            FileMutationIntentAction.rollback.actionType,
            "prepared rollback intent action type"
        )

        _ = try Expect.notNil(
            intent.reviewPayload.exactInputs,
            "prepared rollback intent has exact replay input"
        )

        try Expect.contains(
            intent.reviewPayload.summary,
            "rollback",
            "prepared rollback intent summary mentions rollback"
        )

        return rollbackDiagnostics(
            [
                ("intent", intent.id.rawValue),
                ("status", intent.status.rawValue),
                ("exactInputs", "rollback")
            ]
        )
    }

    static func runExecutePreparedIntentReplaysFileMutationRollback() async throws -> [TestDiagnostic] {
        let env = try RollbackMutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.execute_prepared_intent_replays_file_mutation_rollback
        )
        defer {
            env.remove()
        }

        let source = try await env.recordSourceMutation(
            path: "execute-rollback.txt",
            before: "old\n",
            after: "new\n"
        )

        let preflight = try await AgentFileMutationPreflight.rollback(
            .init(
                mutationID: source.mutationID.uuidString.lowercased()
            ),
            store: env.store,
            workspace: env.workspace,
            recorder: env.recorder
        )

        let intent = try await FileMutationIntentBuilder(
            sessionID: env.sessionID
        ).create(
            preflight,
            using: env.intentManager
        )

        _ = try await env.intentManager.review(
            id: intent.id,
            decision: .approve
        )

        let replay = try await executePreparedIntentThroughRegistry(
            intent,
            manager: env.intentManager,
            workspace: env.workspace,
            recorder: env.recorder,
            store: env.store,
            sessionID: env.sessionID
        )

        try assertPreparedReplayResult(
            replay,
            intentID: intent.id,
            expectedToolName: AgentToolIdentifier.rollback_file_mutation.rawValue,
            label: "prepared rollback replay"
        )

        try Expect.equal(
            try env.read("execute-rollback.txt"),
            "old\n",
            "prepared rollback replay restores previous content"
        )

        let decoded = try JSONToolBridge.decode(
            AgentFileMutationRollbackOutput.self,
            from: replay.toolResult.output
        )

        try Expect.equal(
            decoded.sourceMutationID,
            source.mutationID,
            "rollback output links source mutation"
        )

        return rollbackDiagnostics(
            [
                ("intent", replay.intent.id.rawValue),
                ("status", replay.intent.status.rawValue),
                ("tool", replay.toolCall.name),
                ("file", "rolled-back")
            ]
        )
    }

    static func runExecutePreparedIntentRollbackRecordsMutation() async throws -> [TestDiagnostic] {
        let env = try RollbackMutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.execute_prepared_intent_rollback_records_mutation
        )
        defer {
            env.remove()
        }

        let source = try await env.recordSourceMutation(
            path: "recorded-rollback.txt",
            before: "old\n",
            after: "new\n"
        )

        let preflight = try await AgentFileMutationPreflight.rollback(
            .init(
                mutationID: source.mutationID.uuidString.lowercased()
            ),
            store: env.store,
            workspace: env.workspace,
            recorder: env.recorder
        )

        let intent = try await FileMutationIntentBuilder(
            sessionID: env.sessionID
        ).create(
            preflight,
            using: env.intentManager
        )

        _ = try await env.intentManager.review(
            id: intent.id,
            decision: .approve
        )

        let replay = try await executePreparedIntentThroughRegistry(
            intent,
            manager: env.intentManager,
            workspace: env.workspace,
            recorder: env.recorder,
            store: env.store,
            sessionID: env.sessionID
        )

        let mutations = try await env.store.list(
            .all
        )

        try Expect.equal(
            mutations.count,
            2,
            "rollback replay records source mutation and rollback mutation"
        )

        let rollback = try Expect.notNil(
            mutations.first {
                $0.operationKind == .rollback
            },
            "rollback replay stores rollback mutation"
        )

        try Expect.equal(
            rollback.preparedIntentID,
            intent.id,
            "rollback mutation links prepared intent"
        )

        try Expect.equal(
            rollback.metadata["prepared_intent_id"],
            intent.id.rawValue,
            "rollback mutation metadata links prepared intent"
        )

        try Expect.equal(
            rollback.metadata["execution_mode"],
            AgentToolExecutionMode.prepared_intent_replay.rawValue,
            "rollback mutation records replay execution mode"
        )

        try Expect.equal(
            rollback.metadata["rollback_of"],
            source.mutationID.uuidString.lowercased(),
            "rollback mutation metadata links source mutation"
        )

        try Expect.true(
            rollback.artifactIDs.isEmpty == false,
            "rollback replay emits diff artifact"
        )

        let decoded = try JSONToolBridge.decode(
            AgentFileMutationRollbackOutput.self,
            from: replay.toolResult.output
        )

        try Expect.equal(
            decoded.rollbackMutationID,
            rollback.id,
            "rollback output links recorded rollback mutation"
        )

        return rollbackDiagnostics(
            [
                ("intent", replay.intent.id.rawValue),
                ("mutations", "\(mutations.count)"),
                ("rollbackMutationID", rollback.id.uuidString.lowercased())
            ]
        )
    }
}

private struct RollbackMutationFlowWorkspace {
    let rootdir: URL
    let projectdir: URL
    let sessiondir: URL
    let mutationdir: URL
    let artifactdir: URL
    let preparedIntentsdir: URL
    let sessionID: String
    let workspace: WorkspaceContext
    let store: FileAgentFileMutationStore
    let artifactStore: FileAgentArtifactStore
    let recorder: AgentFileMutationRecorder
    let intentManager: PreparedIntentManager

    static func make(
        _ name: String
    ) throws -> Self {
        let rootdir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-\(rollbackSafeName(name))-\(UUID().uuidString)",
                isDirectory: true
            )

        let projectdir = rootdir.appendingPathComponent(
            "project",
            isDirectory: true
        )
        let sessiondir = rootdir.appendingPathComponent(
            "session",
            isDirectory: true
        )
        let mutationdir = sessiondir.appendingPathComponent(
            "mutations",
            isDirectory: true
        )
        let artifactdir = sessiondir.appendingPathComponent(
            "artifacts",
            isDirectory: true
        )
        let preparedIntentsdir = sessiondir.appendingPathComponent(
            "prepared-intents",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: projectdir,
            withIntermediateDirectories: true
        )

        try FileManager.default.createDirectory(
            at: sessiondir,
            withIntermediateDirectories: true
        )

        let sessionID = "session-\(UUID().uuidString)"
        let workspace = try WorkspaceContext(
            root: projectdir
        )
        let store = FileAgentFileMutationStore(
            sessionID: sessionID,
            mutationdir: mutationdir
        )
        let artifactStore = FileAgentArtifactStore(
            sessionID: sessionID,
            artifactdir: artifactdir
        )
        let backupStore = AgentWriteBackupStore(
            mutationdir: mutationdir
        )
        let recorder = AgentFileMutationRecorder(
            sessionID: sessionID,
            store: store,
            artifacts: artifactStore,
            backups: backupStore,
            policy: .normal
        )
        let intentManager = PreparedIntentManager(
            store: FilePreparedIntentStore(
                preparedIntentsdir: preparedIntentsdir
            )
        )

        return .init(
            rootdir: rootdir,
            projectdir: projectdir,
            sessiondir: sessiondir,
            mutationdir: mutationdir,
            artifactdir: artifactdir,
            preparedIntentsdir: preparedIntentsdir,
            sessionID: sessionID,
            workspace: workspace,
            store: store,
            artifactStore: artifactStore,
            recorder: recorder,
            intentManager: intentManager
        )
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: rootdir
        )
    }

    @discardableResult
    func write(
        _ text: String,
        to relativePath: String
    ) throws -> URL {
        let url = projectdir.appendingPathComponent(
            relativePath,
            isDirectory: false
        )

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try text.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        return url.standardizedFileURL
    }

    func read(
        _ relativePath: String
    ) throws -> String {
        try String(
            contentsOf: projectdir.appendingPathComponent(
                relativePath,
                isDirectory: false
            ),
            encoding: .utf8
        )
    }

    func recordSourceMutation(
        path: String,
        before: String,
        after: String
    ) async throws -> AgentFileMutationResult {
        try write(
            before,
            to: path
        )

        return try await FileEditor(
            workspace: workspace
        ).writeRecorded(
            after,
            to: path,
            recorder: recorder,
            options: .init(
                mutation: .init(
                    toolCallID: "rollback-source-tool-call",
                    metadata: [
                        "source": "rollback-test"
                    ]
                )
            )
        )
    }
}

private func rollbackDiagnostics(
    _ pairs: [(String, String)]
) -> [TestDiagnostic] {
    pairs.map { key, value in
        .field(
            key,
            value
        )
    }
}

private func rollbackSafeName(
    _ name: String
) -> String {
    name.map { character in
        character.isLetter || character.isNumber
            ? String(character)
            : "-"
    }
    .joined()
}
