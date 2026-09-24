import Agentic
import AgenticIO
import Foundation
import Primitives
import Testing

extension AgenticIOFlowTesting {
    static func runExecutePreparedIntentRejectsStaleFileMutationWrite() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.execute_prepared_intent_rejects_stale_file_mutation_write
        )
        defer {
            env.remove()
        }

        try env.write(
            "old\n",
            to: "stale-write.txt"
        )

        let preflight = try await AgentFileMutationPreflight.write(
            .init(
                path: "stale-write.txt",
                content: "new\n"
            ),
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

        try env.write(
            "drifted\n",
            to: "stale-write.txt"
        )

        do {
            _ = try await executePreparedIntentThroughRegistry(
                intent,
                manager: env.intentManager,
                workspace: env.workspace,
                recorder: env.recorder,
                store: env.store,
                sessionID: env.sessionID
            )

            throw AgenticIOFlowTestError.unexpectedResult(
                "stale prepared write unexpectedly executed"
            )
        } catch AgentFileMutationApprovalError.stale_file(let path, _, _) {
            try Expect.contains(
                path,
                "stale-write.txt",
                "stale write error names target file"
            )

            try Expect.equal(
                try env.read("stale-write.txt"),
                "drifted\n",
                "stale prepared write does not mutate drifted target"
            )

            let mutations = try await env.store.list(
                .all
            )

            try Expect.equal(
                mutations.count,
                0,
                "stale prepared write records no file mutation"
            )

            let persisted = try await env.intentManager.get(
                intent.id
            )

            try Expect.equal(
                persisted.status,
                .execution_failed,
                "stale prepared write marks intent execution failed"
            )

            let executionRecord = try Expect.notNil(
                persisted.executionRecord,
                "stale prepared write stores execution record"
            )

            try Expect.equal(
                executionRecord.status,
                .failed,
                "stale prepared write execution record failed"
            )

            try Expect.equal(
                executionRecord.executionToolName,
                WriteFileTool.identifier.rawValue,
                "stale prepared write records execution tool name"
            )

            try Expect.contains(
                executionRecord.errorMessage ?? "",
                "stale_file",
                "stale prepared write records stale file error"
            )

            return mutationPreflightDiagnostics(
                [
                    ("intent", persisted.id.rawValue),
                    ("status", persisted.status.rawValue),
                    ("error", "stale_file"),
                    ("mutations", "\(mutations.count)")
                ]
            )
        }
    }

    static func runExecutePreparedIntentRejectsStaleFileMutationEdit() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.execute_prepared_intent_rejects_stale_file_mutation_edit
        )
        defer {
            env.remove()
        }

        try env.write(
            "alpha\nbeta\n",
            to: "stale-edit.txt"
        )

        let preflight = try await AgentFileMutationPreflight.edit(
            .init(
                path: "stale-edit.txt",
                operations: [
                    .replace_first(
                        .init(
                            target: "beta",
                            replacement: "gamma"
                        )
                    )
                ]
            ),
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

        try env.write(
            "alpha\ndrifted\n",
            to: "stale-edit.txt"
        )

        do {
            _ = try await executePreparedIntentThroughRegistry(
                intent,
                manager: env.intentManager,
                workspace: env.workspace,
                recorder: env.recorder,
                store: env.store,
                sessionID: env.sessionID
            )

            throw AgenticIOFlowTestError.unexpectedResult(
                "stale prepared edit unexpectedly executed"
            )
        } catch AgentFileMutationApprovalError.stale_file(let path, _, _) {
            try Expect.contains(
                path,
                "stale-edit.txt",
                "stale edit error names target file"
            )

            try Expect.equal(
                try env.read("stale-edit.txt"),
                "alpha\ndrifted\n",
                "stale prepared edit does not mutate drifted target"
            )

            let mutations = try await env.store.list(
                .all
            )

            try Expect.equal(
                mutations.count,
                0,
                "stale prepared edit records no file mutation"
            )

            let persisted = try await env.intentManager.get(
                intent.id
            )

            try Expect.equal(
                persisted.status,
                .execution_failed,
                "stale prepared edit marks intent execution failed"
            )

            let executionRecord = try Expect.notNil(
                persisted.executionRecord,
                "stale prepared edit stores execution record"
            )

            try Expect.equal(
                executionRecord.status,
                .failed,
                "stale prepared edit execution record failed"
            )

            try Expect.equal(
                executionRecord.executionToolName,
                EditFileTool.identifier.rawValue,
                "stale prepared edit records execution tool name"
            )

            try Expect.contains(
                executionRecord.errorMessage ?? "",
                "stale_file",
                "stale prepared edit records stale file error"
            )

            return mutationPreflightDiagnostics(
                [
                    ("intent", persisted.id.rawValue),
                    ("status", persisted.status.rawValue),
                    ("error", "stale_file"),
                    ("mutations", "\(mutations.count)")
                ]
            )
        }
    }
    static func runExecutePreparedIntentReplaysFileMutationWrite() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.execute_prepared_intent_replays_file_mutation_write
        )
        defer {
            env.remove()
        }

        try env.write(
            "old\n",
            to: "execute-write.txt"
        )

        let preflight = try await AgentFileMutationPreflight.write(
            .init(
                path: "execute-write.txt",
                content: "new\n"
            ),
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
            expectedToolName: WriteFileTool.identifier.rawValue,
            label: "prepared write replay"
        )

        try Expect.equal(
            try env.read("execute-write.txt"),
            "new\n",
            "prepared write replay mutates target file"
        )

        let mutations = try await env.store.list(
            .all
        )

        try Expect.equal(
            mutations.count,
            1,
            "prepared write replay records one mutation"
        )

        let mutation = try Expect.notNil(
            mutations.first,
            "prepared write replay mutation record"
        )

        try Expect.equal(
            mutation.preparedIntentID,
            intent.id,
            "prepared write mutation links prepared intent id"
        )

        try Expect.equal(
            mutation.metadata["prepared_intent_id"],
            intent.id.rawValue,
            "prepared write mutation metadata links prepared intent id"
        )

        try Expect.equal(
            mutation.metadata["execution_mode"],
            AgentToolExecutionMode.prepared_intent_replay.rawValue,
            "prepared write mutation records replay execution mode"
        )

        return mutationPreflightDiagnostics(
            [
                ("intent", replay.intent.id.rawValue),
                ("status", replay.intent.status.rawValue),
                ("tool", replay.toolCall.name),
                ("mutations", "\(mutations.count)")
            ]
        )
    }

    static func runExecutePreparedIntentReplaysFileMutationEdit() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.execute_prepared_intent_replays_file_mutation_edit
        )
        defer {
            env.remove()
        }

        try env.write(
            "alpha\nbeta\n",
            to: "execute-edit.txt"
        )

        let preflight = try await AgentFileMutationPreflight.edit(
            .init(
                path: "execute-edit.txt",
                operations: [
                    .replace_first(
                        .init(
                            target: "beta",
                            replacement: "gamma"
                        )
                    )
                ]
            ),
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
            expectedToolName: EditFileTool.identifier.rawValue,
            label: "prepared edit replay"
        )

        try Expect.equal(
            try env.read("execute-edit.txt"),
            "alpha\ngamma\n",
            "prepared edit replay mutates target file"
        )

        let mutations = try await env.store.list(
            .all
        )

        try Expect.equal(
            mutations.count,
            1,
            "prepared edit replay records one mutation"
        )

        let mutation = try Expect.notNil(
            mutations.first,
            "prepared edit replay mutation record"
        )

        try Expect.equal(
            mutation.preparedIntentID,
            intent.id,
            "prepared edit mutation links prepared intent id"
        )

        try Expect.equal(
            mutation.metadata["prepared_intent_id"],
            intent.id.rawValue,
            "prepared edit mutation metadata links prepared intent id"
        )

        try Expect.equal(
            mutation.metadata["execution_mode"],
            AgentToolExecutionMode.prepared_intent_replay.rawValue,
            "prepared edit mutation records replay execution mode"
        )

        return mutationPreflightDiagnostics(
            [
                ("intent", replay.intent.id.rawValue),
                ("status", replay.intent.status.rawValue),
                ("tool", replay.toolCall.name),
                ("mutations", "\(mutations.count)")
            ]
        )
    }

    static func runExecutePreparedIntentRequiresApproved() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.execute_prepared_intent_requires_approved
        )
        defer {
            env.remove()
        }

        try env.write(
            "old\n",
            to: "requires-approved.txt"
        )

        let preflight = try await AgentFileMutationPreflight.write(
            .init(
                path: "requires-approved.txt",
                content: "new\n"
            ),
            workspace: env.workspace,
            recorder: env.recorder
        )

        let intent = try await FileMutationIntentBuilder(
            sessionID: env.sessionID
        ).create(
            preflight,
            using: env.intentManager
        )

        do {
            _ = try await executePreparedIntentThroughRegistry(
                intent,
                manager: env.intentManager,
                workspace: env.workspace,
                recorder: env.recorder,
                store: env.store,
                sessionID: env.sessionID
            )

            throw AgenticIOFlowTestError.unexpectedResult(
                "pending prepared intent unexpectedly executed"
            )
        } catch PreparedIntentError.notApproved(let id, let status) {
            try Expect.equal(
                id,
                intent.id,
                "notApproved id"
            )

            try Expect.equal(
                status,
                .pending_review,
                "notApproved status"
            )

            try Expect.equal(
                try env.read("requires-approved.txt"),
                "old\n",
                "unapproved prepared intent does not mutate target file"
            )

            let persisted = try await env.intentManager.get(
                intent.id
            )

            try Expect.equal(
                persisted.status,
                .pending_review,
                "unapproved prepared intent remains pending"
            )

            return mutationPreflightDiagnostics(
                [
                    ("intent", intent.id.rawValue),
                    ("status", persisted.status.rawValue),
                    ("error", "notApproved")
                ]
            )
        }
    }

    static func runExecutePreparedIntentRejectsMissingExecutionTool() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.execute_prepared_intent_rejects_missing_execution_tool
        )
        defer {
            env.remove()
        }

        try env.write(
            "old\n",
            to: "missing-execution-tool.txt"
        )

        let exactInputs = try JSONToolBridge.encode(
            WriteFileToolInput(
                path: "missing-execution-tool.txt",
                content: "new\n"
            )
        )

        let intent = try await env.intentManager.create(
            .init(
                sessionID: env.sessionID,
                actionType: FileMutationIntentAction.write.actionType,
                reviewPayload: .init(
                    title: "Missing execution tool name",
                    summary: "Prepared intent without a concrete replay tool.",
                    actionType: FileMutationIntentAction.write.actionType,
                    risk: .boundedmutate,
                    target: "missing-execution-tool.txt",
                    exactInputs: exactInputs,
                    expectedSideEffects: [
                        "test fixture should not execute"
                    ],
                    policyChecks: [
                        "test_fixture"
                    ]
                ),
                executionToolName: nil
            )
        )

        _ = try await env.intentManager.review(
            id: intent.id,
            decision: .approve
        )

        do {
            _ = try await executePreparedIntentThroughRegistry(
                intent,
                manager: env.intentManager,
                workspace: env.workspace,
                recorder: env.recorder,
                store: env.store,
                sessionID: env.sessionID
            )

            throw AgenticIOFlowTestError.unexpectedResult(
                "prepared intent without executionToolName unexpectedly executed"
            )
        } catch ExecutePreparedIntentToolError.missingExecutionToolName(let id) {
            try Expect.equal(
                id,
                intent.id,
                "missing execution tool name id"
            )

            try Expect.equal(
                try env.read("missing-execution-tool.txt"),
                "old\n",
                "missing execution tool name does not mutate target file"
            )

            let failed = try await env.intentManager.get(
                intent.id
            )

            try Expect.equal(
                failed.status,
                .execution_failed,
                "missing execution tool name marks execution failed"
            )

            _ = try Expect.notNil(
                failed.executionRecord,
                "missing execution tool name has failure record"
            )

            return mutationPreflightDiagnostics(
                [
                    ("intent", intent.id.rawValue),
                    ("status", failed.status.rawValue),
                    ("error", "missingExecutionToolName")
                ]
            )
        }
    }

    static func runPreparedIntentOperatorToolSetRegistersExecuteWhenExecutionRegistryProvided() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.prepared_intent_operator_tool_set_registers_execute_when_execution_registry_provided
        )
        defer {
            env.remove()
        }

        let executionRegistry = try preparedIntentReplayRegistry(
            recorder: env.recorder,
            store: env.store
        )
        var registry = ToolRegistry()

        try registry.register(
            PreparedIntentOperatorToolSet(
                manager: env.intentManager,
                executionRegistry: executionRegistry,
                sessionID: env.sessionID
            )
        )

        _ = try Expect.notNil(
            registry.tool(
                named: AgentToolIdentifier.execute_prepared_intent.rawValue
            ),
            "operator tool set registers execute_prepared_intent"
        )

        return mutationPreflightDiagnostics(
            [
                ("registered", AgentToolIdentifier.execute_prepared_intent.rawValue),
                ("tools", "\(registry.count)")
            ]
        )
    }
    static func runFileMutationPreflightWrite() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_mutation_preflight_write
        )
        defer {
            env.remove()
        }

        try env.write(
            "old\n",
            to: "write.txt"
        )

        let preflight = try await AgentFileMutationPreflight.write(
            .init(
                path: "write.txt",
                content: "new\n"
            ),
            workspace: env.workspace,
            recorder: env.recorder
        )

        try Expect.equal(
            preflight.action,
            .write,
            "write preflight operation kind"
        )

        _ = try Expect.notNil(
            preflight.diffPreview,
            "write preflight has diff preview"
        )

        try Expect.equal(
            preflight.willRecordSessionMutation,
            true,
            "write preflight describes session mutation recording"
        )

        try Expect.equal(
            preflight.willStoreBackupPayload,
            true,
            "write preflight describes session backup payload storage"
        )

        try Expect.equal(
            try env.read("write.txt"),
            "old\n",
            "write preflight does not mutate target file"
        )

        return mutationPreflightDiagnostics(
            [
                ("action", preflight.action.rawValue),
                ("target", preflight.targetPath),
                ("preview", "ok")
            ]
        )
    }

    static func runFileMutationPreflightEdit() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_mutation_preflight_edit
        )
        defer {
            env.remove()
        }

        try env.write(
            "alpha\nbeta\n",
            to: "edit.txt"
        )

        let preflight = try await AgentFileMutationPreflight.edit(
            .init(
                path: "edit.txt",
                operations: [
                    .replace_first(
                        .init(
                            target: "beta",
                            replacement: "gamma"
                        )
                    )
                ]
            ),
            workspace: env.workspace,
            recorder: env.recorder
        )

        try Expect.equal(
            preflight.action,
            .edit,
            "edit preflight operation kind"
        )

        _ = try Expect.notNil(
            preflight.diffPreview,
            "edit preflight has diff preview"
        )

        try Expect.equal(
            preflight.willRecordSessionMutation,
            true,
            "edit preflight describes session mutation recording"
        )

        try Expect.equal(
            try env.read("edit.txt"),
            "alpha\nbeta\n",
            "edit preflight does not mutate target file"
        )

        return mutationPreflightDiagnostics(
            [
                ("action", preflight.action.rawValue),
                ("target", preflight.targetPath),
                ("preview", "ok")
            ]
        )
    }

    static func runFileMutationPreflightNoSideEffects() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_mutation_preflight_no_side_effects
        )
        defer {
            env.remove()
        }

        try env.write(
            "before\n",
            to: "no-side-effects.txt"
        )

        _ = try await AgentFileMutationPreflight.write(
            .init(
                path: "no-side-effects.txt",
                content: "after\n"
            ),
            workspace: env.workspace,
            recorder: env.recorder
        )

        try Expect.equal(
            try env.read("no-side-effects.txt"),
            "before\n",
            "preflight does not mutate file contents"
        )

        try Expect.equal(
            try await env.store.list(.all).count,
            0,
            "preflight does not write mutation records"
        )

        try Expect.equal(
            try await env.artifactStore.list(
                kinds: [],
                latestFirst: true,
                limit: nil
            ).count,
            0,
            "preflight does not emit artifacts"
        )

        try Expect.equal(
            containsPathComponent(
                "content",
                under: env.mutationdir
            ),
            false,
            "preflight does not create backup payload content"
        )

        return mutationPreflightDiagnostics(
            [
                ("file", "unchanged"),
                ("mutations", "0"),
                ("artifacts", "0")
            ]
        )
    }

    static func runPreparedFileMutationWrite() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.prepared_file_mutation_write
        )
        defer {
            env.remove()
        }

        try env.write(
            "old\n",
            to: "prepared-write.txt"
        )

        let preflight = try await AgentFileMutationPreflight.write(
            .init(
                path: "prepared-write.txt",
                content: "new\n"
            ),
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
            "prepared write intent starts pending review"
        )

        try Expect.equal(
            intent.executionToolName,
            WriteFileTool.identifier.rawValue,
            "prepared write intent declares write replay tool"
        )

        let exactInputs = try Expect.notNil(
            intent.reviewPayload.exactInputs,
            "prepared write intent has exact inputs"
        )

        let decoded = try JSONToolBridge.decode(
            WriteFileToolInput.self,
            from: exactInputs
        )

        try Expect.equal(
            decoded.path,
            "prepared-write.txt",
            "prepared write exactInputs are replayable"
        )

        try Expect.equal(
            decoded.content,
            "new\n",
            "prepared write exactInputs preserve content"
        )

        try Expect.equal(
            try env.read("prepared-write.txt"),
            "old\n",
            "prepared write intent creation does not mutate target file"
        )

        return mutationPreflightDiagnostics(
            [
                ("intent", intent.id.rawValue),
                ("status", intent.status.rawValue),
                ("exactInputs", "write")
            ]
        )
    }

    static func runPreparedFileMutationEdit() async throws -> [TestDiagnostic] {
        let env = try MutationPreflightFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.prepared_file_mutation_edit
        )
        defer {
            env.remove()
        }

        try env.write(
            "alpha\nbeta\n",
            to: "prepared-edit.txt"
        )

        let preflight = try await AgentFileMutationPreflight.edit(
            .init(
                path: "prepared-edit.txt",
                operations: [
                    .replace_first(
                        .init(
                            target: "beta",
                            replacement: "gamma"
                        )
                    )
                ]
            ),
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
            "prepared edit intent starts pending review"
        )

        try Expect.equal(
            intent.executionToolName,
            EditFileTool.identifier.rawValue,
            "prepared edit intent declares edit replay tool"
        )

        let exactInputs = try Expect.notNil(
            intent.reviewPayload.exactInputs,
            "prepared edit intent has exact inputs"
        )

        let decoded = try JSONToolBridge.decode(
            EditFileToolInput.self,
            from: exactInputs
        )

        try Expect.equal(
            decoded.path,
            "prepared-edit.txt",
            "prepared edit exactInputs are replayable"
        )

        try Expect.equal(
            decoded.operations.count,
            1,
            "prepared edit exactInputs preserve operation count"
        )

        try Expect.equal(
            try env.read("prepared-edit.txt"),
            "alpha\nbeta\n",
            "prepared edit intent creation does not mutate target file"
        )

        return mutationPreflightDiagnostics(
            [
                ("intent", intent.id.rawValue),
                ("status", intent.status.rawValue),
                ("exactInputs", "edit")
            ]
        )
    }
}

private struct MutationPreflightFlowWorkspace {
    let rootdir: URL
    let projectdir: URL
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
                "agentic-\(mutationPreflightSafeName(name))-\(UUID().uuidString)",
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
}

internal func mutationPreflightDiagnostics(
    _ pairs: [(String, String)]
) -> [TestDiagnostic] {
    pairs.map { key, value in
        .field(
            key,
            value
        )
    }
}

private func mutationPreflightSafeName(
    _ name: String
) -> String {
    name.map { character in
        character.isLetter || character.isNumber
            ? String(character)
            : "-"
    }
    .joined()
}

private func containsPathComponent(
    _ component: String,
    under root: URL
) -> Bool {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: nil,
        options: [
            .skipsHiddenFiles
        ]
    ) else {
        return false
    }

    for case let url as URL in enumerator {
        if url.lastPathComponent == component {
            return true
        }
    }

    return false
}
