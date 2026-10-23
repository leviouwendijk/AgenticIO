import Agentic
import AgenticIO
import Workspace
import Writers
import Foundation
import Path
import Testing
import Primitives
import Schema

extension AgenticIOFlowTesting {
    static func runCoordinatedWorkspaceGuard() async throws -> [TestDiagnostic] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "workspace-coordinated-guard-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sample.txt")
        try "original\n".write(to: file, atomically: true, encoding: .utf8)
        let second_file = root.appendingPathComponent("second.txt")
        try "second\n".write(to: second_file, atomically: true, encoding: .utf8)

        let id = PathAccessRootIdentifier(rawValue: "project")
        let grant = try WorkspaceGrant(
            id: WorkspaceGrantIdentifier("coordinated-guard"),
            rootIdentifier: id,
            capabilities: Set(WorkspaceCapability.allCases)
        )
        let authority = try Workspace(
            root: PathAccessRoot(
                id: id,
                label: "Project",
                scope: try PathAccessScope(root: root, policy: .defaults.workspace),
                isDefault: true
            ),
            grants: [grant]
        )
        let coordinator = StandardMutationCoordinator()
        let participant = await coordinator.participant(name: "agenticio-guard")
        let submission = WorkspaceCoordinatedSubmission(participant: participant)
        let context = try authority.context(
            execution: .init(io: .blocking, mutations: .coordinated(submission))
        )
        let tool = SystemIO.Tools.MutateFiles()
        let input = SystemIO.Tools.MutateFiles.Input(entries: [
            .init(kind: .replace_text, path: "sample.txt", content: "modified\n")
        ])

        let tool_context = ToolContext(workspace: context)
        let preparation = try await tool.prepare(input, in: tool_context)
        let preview = preparation.review
        try Expect.true(preview.summary.contains("Stage"), "coordinated tool preflight advertises staging")
        let result = try await tool.call(input, prepared: preparation.operation, in: tool_context)
        try Expect.equal(result.status, "staged", "mutate_files stages under coordination")
        let staged_work = try Expect.notNil(preparation.operation, "staged preparation has plan")
        try Expect.equal(result.planID, try staged_work.plan.decode(MutateFilesPreparedWork.self).plan.id, "staged plan uses reviewed identity")
        try Expect.true(result.submissionID != nil, "staged result carries submission ID")
        try Expect.true(result.resultID == nil, "staged result is not a published result")
        try Expect.equal(result.records.count, 0, "no disk mutation records before publication")
        try Expect.equal(
            try String(contentsOf: file, encoding: .utf8),
            "original\n",
            "coordinated mutate_files does not publish"
        )

        var rejected_editor = false
        do {
            _ = try FileEditor(workspace: context).write("modified\n", to: "sample.txt")
        } catch WorkspaceExecutionError.coordinatedMutationRequiresSubmission {
            rejected_editor = true
        }
        try Expect.true(rejected_editor, "coordinated mode rejects direct FileEditor writes")

        let nested = try context.context(atRootPath: ".")
        switch nested.execution.mutations {
        case .coordinated(let preserved):
            try Expect.equal(preserved.id, submission.id, "derived context retains participant")
        case .immediate:
            try Expect.true(false, "derived context lost coordinator")
        }

        let staged_plan = try Expect.notNil(try await coordinator.staged_plan(), "coordinated.plan")
        try Expect.equal(staged_plan.report.entryCount, 1, "coordinated.one_entry")
        try Expect.equal(
            try String(contentsOf: file, encoding: .utf8), "original\n",
            "staged content remains off disk"
        )
        let published = try Expect.notNil(try await coordinator.publish(), "coordinated.publication")
        try Expect.equal(published.result.status, .applied, "coordinated.owner_publication")
        try Expect.equal(
            try String(contentsOf: file, encoding: .utf8), "modified\n",
            "owner publication uses canonical mutation applier"
        )
        try await submission.close()
        return [.field("coordinator", "participant-preserved-and-guarded")]
    }
}


extension AgenticIOFlowTesting {
    static func runMutationApprovalIdentity() async throws -> [TestDiagnostic] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mutation-approval-binding-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("approved.txt")
        try "before\n".write(to: file, atomically: true, encoding: .utf8)
        let grant = try WorkspaceGrant(
            id: WorkspaceGrantIdentifier("approval-binding"),
            rootIdentifier: .project,
            capabilities: Set(WorkspaceCapability.allCases)
        )
        let authority = try Workspace(
            root: PathAccessRoot(
                id: .project,
                label: "Project",
                scope: try PathAccessScope(root: root, policy: .defaults.workspace),
                isDefault: true
            ),
            grants: [grant]
        )
        let workspace = try authority.context(execution: .init(io: .blocking, mutations: .immediate))
        let context = ToolContext(workspace: workspace)
        let tool = SystemIO.Tools.MutateFiles()
        let input = SystemIO.Tools.MutateFiles.Input(entries: [
            .init(kind: .replace_text, path: "approved.txt", content: "approved\n")
        ])
        let prepared = try await tool.prepare(input, in: context)
        let envelope = try Expect.notNil(prepared.operation, "review retains a serializable plan")
        let work = try envelope.plan.decode(MutateFilesPreparedWork.self)

        do {
            _ = try await tool.call(input, in: context)
            try Expect.true(false, "direct unprepared call should fail")
        } catch ToolPreparationError.prepared_operation_required {}

        let modified = SystemIO.Tools.MutateFiles.Input(entries: [
            .init(kind: .replace_text, path: "approved.txt", content: "other\n")
        ])
        do {
            _ = try await tool.call(modified, prepared: envelope, in: context)
            try Expect.true(false, "input substitution must fail")
        } catch MutateFilesPreparedWorkError.context_mismatch {}
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), "before\n", "unchanged before execution")

        // Transport and checkpoint persistence preserve the *same* plan bytes.
        let reviewed = ToolInvocation.Review(
            invocation: ToolInvocation(
                id: "roundtrip",
                tool: SystemIO.Tools.MutateFiles.identifier,
                arguments: try JSONValue.encoding(input)
            ),
            preflight: prepared.review,
            requirement: .needs_human_review,
            preparedOperation: envelope
        )
        let stored_review = try JSONEncoder().encode(reviewed)
        let resumed_review = try JSONDecoder().decode(ToolInvocation.Review.self, from: stored_review)
        try Expect.equal(resumed_review.preparedOperation, envelope, "checkpoint preserves exact review operation")
        let serialized = try JSONEncoder().encode(envelope)
        let restored = try JSONDecoder().decode(PreparedOperation.Envelope.self, from: serialized)
        try Expect.equal(restored, envelope, "durable prepared operation roundtrips")
        let result = try await tool.call(input, prepared: restored, in: context)
        try Expect.equal(result.planID, work.plan.id, "execution used exact prepared plan")
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), "approved\n", "approved content applied")

        let stale = SystemIO.Tools.MutateFiles.Input(entries: [
            .init(kind: .replace_text, path: "approved.txt", content: "stale-write\n")
        ])
        let stale_prepared = try await tool.prepare(stale, in: context)
        try "external\n".write(to: file, atomically: true, encoding: .utf8)
        let failed = try await tool.call(stale, prepared: stale_prepared.operation, in: context)
        try Expect.true(failed.status != "applied", "Writers rejects stale source snapshots")
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), "external\n", "no stale overwrite")

        var registry = ToolRegistry()
        try registry.register(SystemIO.Tools.MutateFiles())
        let invoked_input = SystemIO.Tools.MutateFiles.Input(entries: [
            .init(kind: .replace_text, path: "approved.txt", content: "invoked\n")
        ])
        let invocation = ToolInvocation(
            id: "prepared-plan-invocation",
            tool: SystemIO.Tools.MutateFiles.identifier,
            arguments: try JSONValue.encoding(invoked_input)
        )
        let invoked = try await ToolInvoker(
            registry: registry,
            policy: .init(autonomyMode: .auto_bounded_mutate)
        ).invoke(invocation, context: context)
        try Expect.true(invoked.execution != nil, "invoker executes reviewed plan")
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), "invoked\n", "bound plan applied")
        return [.field("bound_plan", work.plan.id.uuidString)]
    }

}
