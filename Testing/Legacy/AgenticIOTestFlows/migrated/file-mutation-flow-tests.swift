import Agentic
import AgenticIO
import Foundation
import Primitives
import Testing
import Writers

extension AgenticIOFlowTesting {
    static func runListFileMutationsTool() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.list_file_mutations_tool
        )
        defer {
            env.remove()
        }

        let editor = FileEditor(
            workspace: env.workspace
        )

        _ = try env.write(
            "one\n",
            to: "history-a.txt"
        )
        _ = try env.write(
            "alpha\nbeta\n",
            to: "history-b.txt"
        )

        let first = try await editor.writeRecorded(
            "two\n",
            to: "history-a.txt",
            recorder: env.recorder,
            options: .init(
                mutation: .init(
                    toolCallID: "history-list-tool-call-1",
                    preparedIntentID: .init("history-list-intent-1"),
                    metadata: [
                        "flow": AgenticIOMigratedMutationFlowID.list_file_mutations_tool,
                        "slot": "first"
                    ]
                )
            )
        )

        let second = try await editor.editRecorded(
            .replaceUnique(
                of: "beta",
                with: "bravo"
            ),
            at: "history-b.txt",
            recorder: env.recorder,
            options: .init(
                mutation: .init(
                    toolCallID: "history-list-tool-call-2",
                    preparedIntentID: .init("history-list-intent-2"),
                    metadata: [
                        "flow": AgenticIOMigratedMutationFlowID.list_file_mutations_tool,
                        "slot": "second"
                    ]
                )
            )
        )

        let registry = try Agentic.tool.registry {
            CoreFileMutationHistoryToolSet(
                store: env.store,
                recorder: env.recorder,
                artifactStore: env.artifactStore
            )
        }

        try Expect.equal(
            registry.count,
            3,
            "mutation history tool set count"
        )

        _ = try Expect.notNil(
            registry.tool(
                named: SystemIO.Tools.ListFileMutations.identifier.rawValue
            ),
            "history tool set registers list_file_mutations"
        )

        _ = try Expect.notNil(
            registry.tool(
                named: SystemIO.Tools.InspectFileMutation.identifier.rawValue
            ),
            "history tool set registers inspect_file_mutation"
        )

        _ = try Expect.notNil(
            registry.tool(
                named: AgentToolIdentifier.rollback_file_mutation.rawValue
            ),
            "history tool set registers rollback_file_mutation"
        )

        let tool = SystemIO.Tools.ListFileMutations(
            store: env.store
        )
        let output = try JSONToolBridge.decode(
            AgentFileMutationHistoryList.self,
            from: try await tool.call(
                input: try JSONToolBridge.encode(
                    SystemIO.Tools.ListFileMutations.Input(
                        limit: 1
                    )
                ),
                workspace: env.workspace
            )
        )

        try Expect.equal(
            output.totalCount,
            2,
            "list_file_mutations reports total count before limit"
        )

        try Expect.equal(
            output.returnedCount,
            1,
            "list_file_mutations applies limit"
        )

        try Expect.true(
            output.truncated,
            "list_file_mutations marks limited output as truncated"
        )

        let summary = try Expect.notNil(
            output.mutations.first,
            "list_file_mutations returns a summary"
        )

        try Expect.true(
            [
                first.mutationID,
                second.mutationID
            ].contains(
                summary.id
            ),
            "list_file_mutations limited result is one known mutation"
        )

        let secondOnly = try JSONToolBridge.decode(
            AgentFileMutationHistoryList.self,
            from: try await tool.call(
                input: try JSONToolBridge.encode(
                    SystemIO.Tools.ListFileMutations.Input(
                        preparedIntentID: "history-list-intent-2",
                        limit: 10
                    )
                ),
                workspace: env.workspace
            )
        )

        try Expect.equal(
            secondOnly.totalCount,
            1,
            "list_file_mutations filters by prepared intent id"
        )

        let secondSummary = try Expect.notNil(
            secondOnly.mutations.first,
            "list_file_mutations returns prepared-intent-filtered summary"
        )

        try Expect.equal(
            secondSummary.id,
            second.mutationID,
            "list_file_mutations prepared-intent filter returns matching mutation"
        )

        try Expect.equal(
            secondSummary.preparedIntentID,
            .init("history-list-intent-2"),
            "list_file_mutations includes prepared intent id"
        )

        try Expect.equal(
            secondSummary.writerRecordID,
            second.writerRecordID,
            "list_file_mutations includes writer record id"
        )

        try Expect.equal(
            secondSummary.path,
            "history-b.txt",
            "list_file_mutations includes relative path"
        )

        try Expect.equal(
            secondSummary.operationKind,
            .edit_operations,
            "list_file_mutations includes operation kind"
        )

        try Expect.equal(
            secondSummary.resource,
            .update,
            "list_file_mutations includes resource change"
        )

        try Expect.equal(
            secondSummary.delta,
            .replacement,
            "list_file_mutations includes delta kind"
        )

        try Expect.true(
            secondSummary.rollbackable,
            "list_file_mutations includes rollbackable flag"
        )

        let filtered = try JSONToolBridge.decode(
            AgentFileMutationHistoryList.self,
            from: try await tool.call(
                input: try JSONToolBridge.encode(
                    SystemIO.Tools.ListFileMutations.Input(
                        path: "history-a.txt",
                        limit: 10
                    )
                ),
                workspace: env.workspace
            )
        )

        try Expect.equal(
            filtered.totalCount,
            1,
            "list_file_mutations filters by path"
        )

        try Expect.equal(
            filtered.mutations.first?.id,
            first.mutationID,
            "list_file_mutations path filter returns matching mutation"
        )

        return mutationPreflightDiagnostics(
            [
                ("returnedCount", "\(output.returnedCount)"),
                ("totalCount", "\(output.totalCount)"),
                ("latestMutationID", summary.id.uuidString.lowercased())
            ]
        )
    }

    static func runInspectFileMutationTool() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.inspect_file_mutation_tool
        )
        defer {
            env.remove()
        }

        let editor = FileEditor(
            workspace: env.workspace
        )

        _ = try env.write(
            "old\n",
            to: "inspect.txt"
        )

        let result = try await editor.writeRecorded(
            "new\n",
            to: "inspect.txt",
            recorder: env.recorder,
            options: .init(
                mutation: .init(
                    toolCallID: "history-inspect-tool-call",
                    preparedIntentID: .init("history-inspect-intent"),
                    metadata: [
                        "flow": AgenticIOMigratedMutationFlowID.inspect_file_mutation_tool
                    ]
                )
            )
        )

        let tool = SystemIO.Tools.InspectFileMutation(
            store: env.store,
            artifactStore: env.artifactStore
        )
        let inspection = try JSONToolBridge.decode(
            AgentFileMutationInspection.self,
            from: try await tool.call(
                input: try JSONToolBridge.encode(
                    SystemIO.Tools.InspectFileMutation.Input(
                        id: result.mutationID.uuidString.lowercased(),
                        loadDiffArtifact: false
                    )
                ),
                workspace: env.workspace
            )
        )

        try Expect.equal(
            inspection.mutation.id,
            result.mutationID,
            "inspect_file_mutation returns requested mutation"
        )

        try Expect.equal(
            inspection.mutation.writerRecordID,
            result.writerRecordID,
            "inspect_file_mutation includes writer record id"
        )

        try Expect.equal(
            inspection.mutation.preparedIntentID,
            .init("history-inspect-intent"),
            "inspect_file_mutation includes prepared intent id"
        )

        try Expect.equal(
            inspection.mutation.path,
            "inspect.txt",
            "inspect_file_mutation includes relative path"
        )

        try Expect.equal(
            inspection.mutation.operationKind,
            .write_text,
            "inspect_file_mutation includes operation kind"
        )

        try Expect.equal(
            inspection.mutation.resource,
            .update,
            "inspect_file_mutation includes resource kind"
        )

        try Expect.equal(
            inspection.mutation.delta,
            .replacement,
            "inspect_file_mutation includes delta kind"
        )

        try Expect.true(
            inspection.mutation.rollbackable,
            "inspect_file_mutation includes rollbackable flag"
        )

        try Expect.equal(
            inspection.writerRecord.id,
            result.writerRecordID,
            "inspect_file_mutation includes writer record summary"
        )

        _ = try Expect.notNil(
            inspection.writerMutationRecord,
            "inspect_file_mutation loads canonical writer mutation record"
        )

        try Expect.isNil(
            inspection.diffArtifact,
            "inspect_file_mutation skips diff artifact when requested"
        )

        return mutationPreflightDiagnostics(
            [
                ("mutationID", inspection.mutation.id.uuidString.lowercased()),
                ("writerRecordID", inspection.writerRecord.id.uuidString.lowercased())
            ]
        )
    }

    static func runInspectFileMutationLoadsDiffArtifact() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.inspect_file_mutation_loads_diff_artifact
        )
        defer {
            env.remove()
        }

        let editor = FileEditor(
            workspace: env.workspace
        )

        _ = try env.write(
            "one\ntwo\n",
            to: "inspect-diff.txt"
        )

        let result = try await editor.writeRecorded(
            "one\ntwo changed\n",
            to: "inspect-diff.txt",
            recorder: env.recorder,
            options: .init(
                mutation: .init(
                    toolCallID: "history-inspect-diff-tool-call",
                    preparedIntentID: .init("history-inspect-diff-intent"),
                    metadata: [
                        "flow": AgenticIOMigratedMutationFlowID.inspect_file_mutation_loads_diff_artifact
                    ]
                )
            )
        )

        try Expect.false(
            result.artifacts.isEmpty,
            "recorded mutation emitted diff artifact before inspection"
        )

        let tool = SystemIO.Tools.InspectFileMutation(
            store: env.store,
            artifactStore: env.artifactStore
        )
        let inspection = try JSONToolBridge.decode(
            AgentFileMutationInspection.self,
            from: try await tool.call(
                input: try JSONToolBridge.encode(
                    SystemIO.Tools.InspectFileMutation.Input(
                        id: result.mutationID.uuidString.lowercased(),
                        loadDiffArtifact: true
                    )
                ),
                workspace: env.workspace
            )
        )

        let diffArtifact = try Expect.notNil(
            inspection.diffArtifact,
            "inspect_file_mutation loads diff artifact"
        )

        try Expect.equal(
            diffArtifact.artifact.kind,
            .diff,
            "loaded mutation artifact is a diff"
        )

        try Expect.contains(
            diffArtifact.content,
            "two changed",
            "loaded mutation diff contains changed text"
        )

        try Expect.true(
            inspection.diffArtifactIDs.contains(
                diffArtifact.artifact.id
            ),
            "inspection includes loaded diff artifact id"
        )

        return mutationPreflightDiagnostics(
            [
                ("mutationID", inspection.mutation.id.uuidString.lowercased()),
                ("diffArtifactID", diffArtifact.artifact.id)
            ]
        )
    }

    static func runInspectFileMutationRejectsMissingID() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.inspect_file_mutation_rejects_missing_id
        )
        defer {
            env.remove()
        }

        let tool = SystemIO.Tools.InspectFileMutation(
            store: env.store,
            artifactStore: env.artifactStore
        )

        try await Expect.throwsError(
            "inspect_file_mutation rejects malformed id"
        ) {
            _ = try await tool.call(
                input: try JSONToolBridge.encode(
                    SystemIO.Tools.InspectFileMutation.Input(
                        id: "not-a-uuid"
                    )
                ),
                workspace: env.workspace
            )
        }

        try await Expect.throwsError(
            "inspect_file_mutation rejects missing id"
        ) {
            _ = try await tool.call(
                input: try JSONToolBridge.encode(
                    SystemIO.Tools.InspectFileMutation.Input(
                        id: UUID().uuidString.lowercased()
                    )
                ),
                workspace: env.workspace
            )
        }

        return mutationPreflightDiagnostics(
            [
                ("malformedID", "rejected"),
                ("missingID", "rejected")
            ]
        )
    }
    static func runFileMutationStore() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_mutation_store
        )
        defer {
            env.remove()
        }

        let editor = FileEditor(
            workspace: env.workspace
        )

        let target = try env.write(
            "old\n",
            to: "store.txt"
        )

        let result = try await editor.writeRecorded(
            "new\n",
            to: "store.txt",
            recorder: env.recorder,
            options: .init(
                mutation: .init(
                    toolCallID: "tool-call-1",
                    preparedIntentID: .init("intent-1"),
                    metadata: [
                        "flow": AgenticIOMigratedMutationFlowID.file_mutation_store
                    ]
                )
            )
        )

        let loaded = try Expect.notNil(
            try await env.store.load(
                id: result.mutationID
            ),
            "stored mutation record loads by id"
        )

        try Expect.equal(
            loaded.writerRecordID,
            result.writerRecordID,
            "stored Agentic record points at the Writers record"
        )

        _ = try Expect.notNil(
            try await env.store.loadWriterRecord(
                for: loaded
            ),
            "stored Writers record loads from Agentic wrapper"
        )

        try Expect.equal(
            try await env.store.list(.all).count,
            1,
            "mutation store lists one record"
        )

        try Expect.equal(
            try await env.store.list(
                .init(
                    target: target
                )
            ).count,
            1,
            "mutation store filters by target"
        )

        try Expect.equal(
            try await env.store.list(
                .init(
                    toolCallID: "tool-call-1"
                )
            ).count,
            1,
            "mutation store filters by tool call id"
        )

        try Expect.equal(
            try await env.store.list(
                .init(
                    preparedIntentID: .init("intent-1")
                )
            ).count,
            1,
            "mutation store filters by prepared intent id"
        )

        try await env.store.delete(
            id: result.mutationID
        )

        try Expect.isNil(
            try await env.store.load(
                id: result.mutationID
            ),
            "mutation store deletes Agentic record"
        )

        return mutationDiagnostics(
            [
                ("records", "saved/listed/queried/deleted"),
                ("writerRecordID", result.writerRecordID.uuidString)
            ]
        )
    }

    static func runFileEditorRecordedWrite() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_editor_recorded_write
        )
        defer {
            env.remove()
        }

        try env.write(
            "old\n",
            to: "write.txt"
        )

        let editor = FileEditor(
            workspace: env.workspace
        )

        let result = try await editor.writeRecorded(
            "new\n",
            to: "write.txt",
            recorder: env.recorder,
            options: .init(
                mutation: .init(
                    metadata: [
                        "flow": AgenticIOMigratedMutationFlowID.file_editor_recorded_write
                    ]
                )
            )
        )

        try Expect.equal(
            try env.read("write.txt"),
            "new\n",
            "recorded write mutates the target file"
        )

        try Expect.true(
            result.mutation.hasChanges,
            "recorded write marks mutation as changed"
        )

        try Expect.true(
            result.mutation.rollbackable,
            "recorded write is rollbackable"
        )

        try Expect.equal(
            try await env.store.list(.all).count,
            1,
            "recorded write stores one mutation"
        )

        let before = try Expect.notNil(
            result.writerRecord.before?.content,
            "recorded write includes before snapshot content"
        )

        let after = try Expect.notNil(
            result.writerRecord.after?.content,
            "recorded write includes after snapshot content"
        )

        try Expect.equal(
            before,
            "old\n",
            "before snapshot matches original content"
        )

        try Expect.equal(
            after,
            "new\n",
            "after snapshot matches replacement content"
        )

        return mutationDiagnostics(
            [
                ("target", "write.txt"),
                ("writerRecordID", result.writerRecordID.uuidString)
            ]
        )
    }

    static func runFileEditorRecordedEdit() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_editor_recorded_edit
        )
        defer {
            env.remove()
        }

        try env.write(
            "alpha\nbeta\ngamma\n",
            to: "edit.txt"
        )

        let editor = FileEditor(
            workspace: env.workspace
        )

        let result = try await editor.editRecorded(
            [
                .replaceFirst(
                    of: "beta",
                    with: "BETA"
                )
            ],
            at: "edit.txt",
            recorder: env.recorder,
            options: .init(
                mutation: .init(
                    metadata: [
                        "flow": AgenticIOMigratedMutationFlowID.file_editor_recorded_edit
                    ]
                )
            )
        )

        try Expect.equal(
            try env.read("edit.txt"),
            "alpha\nBETA\ngamma\n",
            "recorded edit mutates the target file"
        )

        try Expect.true(
            result.mutation.hasChanges,
            "recorded edit marks mutation as changed"
        )

        try Expect.true(
            result.mutation.rollbackable,
            "recorded edit is rollbackable"
        )

        try Expect.equal(
            result.mutation.operationKind.rawValue,
            "edit_operations",
            "recorded edit stores edit operation kind"
        )

        try Expect.equal(
            try await env.store.list(.all).count,
            1,
            "recorded edit stores one mutation"
        )

        return mutationDiagnostics(
            [
                ("target", "edit.txt"),
                ("writerRecordID", result.writerRecordID.uuidString)
            ]
        )
    }

    static func runFileToolRecordedWrite() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_tool_recorded_write
        )
        defer {
            env.remove()
        }

        try env.write(
            "before\n",
            to: "tool-write.txt"
        )

        let tool = WriteFileTool(
            recorder: env.recorder
        )

        let value = try await tool.call(
            input: try JSONToolBridge.encode(
                WriteFileToolInput(
                    path: "tool-write.txt",
                    content: "after\n"
                )
            ),
            workspace: env.workspace
        )

        let output = try JSONToolBridge.decode(
            WriteFileToolOutput.self,
            from: value
        )

        let mutation = try Expect.notNil(
            output.mutation,
            "write_file output includes mutation summary"
        )

        try Expect.equal(
            try env.read("tool-write.txt"),
            "after\n",
            "write_file with recorder mutates file"
        )

        try Expect.equal(
            mutation.backupPolicy,
            .session_store,
            "write_file uses normal session backup policy"
        )

        try Expect.equal(
            mutation.payloadPolicy,
            .external_content,
            "write_file uses external Writers payload storage"
        )

        try Expect.equal(
            try await env.store.list(.all).count,
            1,
            "write_file with recorder stores one mutation"
        )

        return mutationDiagnostics(
            [
                ("target", output.path),
                ("writerRecordID", mutation.writerRecordID.uuidString)
            ]
        )
    }

    static func runFileToolRecordedEdit() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_tool_recorded_edit
        )
        defer {
            env.remove()
        }

        try env.write(
            "alpha\nbeta\ngamma\n",
            to: "tool-edit.txt"
        )

        let tool = EditFileTool(
            recorder: env.recorder
        )

        let value = try await tool.call(
            input: try JSONToolBridge.encode(
                EditFileToolInput(
                    path: "tool-edit.txt",
                    operations: [
                        .replace_first(
                            .init(
                                target: "beta",
                                replacement: "BETA"
                            )
                        )
                    ]
                )
            ),
            workspace: env.workspace
        )

        let output = try JSONToolBridge.decode(
            EditFileToolOutput.self,
            from: value
        )

        let mutation = try Expect.notNil(
            output.mutation,
            "edit_file output includes mutation summary"
        )

        let diffArtifactID = try Expect.notNil(
            output.appliedDiffArtifactID,
            "edit_file output includes applied diff artifact id"
        )

        let appliedDiff = try Expect.notNil(
            output.appliedDiff,
            "edit_file output includes applied diff"
        )

        let editedSlice = try Expect.notNil(
            output.editedChangedSlices.first,
            "edit_file output includes edited changed slice"
        )

        try Expect.equal(
            try env.read("tool-edit.txt"),
            "alpha\nBETA\ngamma\n",
            "edit_file with recorder mutates file"
        )

        try Expect.equal(
            output.operationCount,
            1,
            "edit_file output reports one operation"
        )

        try Expect.equal(
            output.changeCount,
            2,
            "edit_file output reports actual changed line count"
        )

        try Expect.false(
            output.appliedDiffTruncated,
            "small edit_file applied diff is not truncated"
        )

        try Expect.equal(
            output.appliedDiffArtifactID,
            mutation.artifactIDs.first,
            "edit_file output surfaces first recorded diff artifact id"
        )

        try Expect.notNil(
            output.originalFingerprint,
            "edit_file output includes original fingerprint"
        )

        try Expect.notNil(
            output.editedFingerprint,
            "edit_file output includes edited fingerprint"
        )

        try Expect.contains(
            appliedDiff,
            "BETA",
            "edit_file applied diff includes replacement text"
        )

        try Expect.contains(
            editedSlice.lines.joined(
                separator: "\n"
            ),
            "BETA",
            "edit_file edited changed slice includes replacement text"
        )

        try Expect.equal(
            try await env.store.list(.all).count,
            1,
            "edit_file with recorder stores one mutation"
        )

        return mutationDiagnostics(
            [
                ("target", output.path),
                ("writerRecordID", mutation.writerRecordID.uuidString),
                ("diffArtifactID", diffArtifactID)
            ]
        )
    }

    static func runNoLocalBackupDefault() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.no_local_backup_default
        )
        defer {
            env.remove()
        }

        try env.write(
            "before\n",
            to: "backup.txt"
        )

        let editor = FileEditor(
            workspace: env.workspace
        )

        _ = try await editor.writeRecorded(
            "after\n",
            to: "backup.txt",
            recorder: env.recorder,
            options: .init(
                mutation: .init(
                    metadata: [
                        "flow": AgenticIOMigratedMutationFlowID.no_local_backup_default
                    ]
                )
            )
        )

        let backupdir = env.mutationdir.appendingPathComponent(
            "backups",
            isDirectory: true
        )

        try Expect.notEmpty(
            childURLs(
                backupdir
            ),
            "default recorded write stores backups in Agentic session storage"
        )

        try Expect.false(
            containsPathComponent(
                "safe-file-backups",
                under: env.projectdir
            ),
            "default recorded write does not create project-local safe-file-backups"
        )

        return mutationDiagnostics(
            [
                ("sessionBackups", backupdir.path),
                ("localBackups", "absent")
            ]
        )
    }

    static func runFileMutationDiffArtifact() async throws -> [TestDiagnostic] {
        let env = try MutationFlowWorkspace.make(
            AgenticIOMigratedMutationFlowID.file_mutation_diff_artifact
        )
        defer {
            env.remove()
        }

        try env.write(
            "one\ntwo\n",
            to: "diff.txt"
        )

        let editor = FileEditor(
            workspace: env.workspace
        )

        let result = try await editor.writeRecorded(
            "one\ntwo changed\n",
            to: "diff.txt",
            recorder: env.recorder,
            options: .init(
                mutation: .init(
                    metadata: [
                        "flow": AgenticIOMigratedMutationFlowID.file_mutation_diff_artifact
                    ]
                )
            )
        )

        let artifact = try Expect.notNil(
            result.artifacts.first,
            "changed recorded mutation emits a diff artifact"
        )

        try Expect.equal(
            artifact.kind,
            .diff,
            "recorded mutation artifact is a diff"
        )

        let loaded = try Expect.notNil(
            try await env.artifactStore.load(
                id: artifact.id
            ),
            "diff artifact can be loaded"
        )

        try Expect.contains(
            loaded.content,
            "two changed",
            "diff artifact contains replacement text"
        )

        let noop = try await editor.writeRecorded(
            "one\ntwo changed\n",
            to: "diff.txt",
            recorder: env.recorder,
            options: .init(
                mutation: .init(
                    metadata: [
                        "flow": "no-op-diff-artifact-check"
                    ]
                )
            )
        )

        try Expect.isEmpty(
            noop.artifacts,
            "no-op recorded mutation does not emit diff artifact"
        )

        return mutationDiagnostics(
            [
                ("artifactID", artifact.id),
                ("artifactKind", artifact.kind.rawValue)
            ]
        )
    }
}

private struct MutationFlowWorkspace {
    let rootdir: URL
    let projectdir: URL
    let sessiondir: URL
    let mutationdir: URL
    let artifactdir: URL
    let sessionID: String
    let workspace: WorkspaceContext
    let store: FileAgentFileMutationStore
    let artifactStore: FileAgentArtifactStore
    let recorder: AgentFileMutationRecorder

    static func make(
        _ name: String
    ) throws -> Self {
        let rootdir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-\(safeName(name))-\(UUID().uuidString)",
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

        return .init(
            rootdir: rootdir,
            projectdir: projectdir,
            sessiondir: sessiondir,
            mutationdir: mutationdir,
            artifactdir: artifactdir,
            sessionID: sessionID,
            workspace: workspace,
            store: store,
            artifactStore: artifactStore,
            recorder: recorder
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

internal func mutationDiagnostics(
    _ pairs: [(String, String)]
) -> [TestDiagnostic] {
    pairs.map { key, value in
        .field(
            key,
            value
        )
    }
}

private func safeName(
    _ name: String
) -> String {
    name.map { character in
        character.isLetter || character.isNumber
            ? String(character)
            : "-"
    }
    .joined()
}

private func childURLs(
    _ url: URL
) -> [URL] {
    (
        try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [
                .skipsHiddenFiles
            ]
        )
    ) ?? []
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