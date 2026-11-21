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
        let tool = SystemIO.Tools.Mutate()
        let input = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: "sample.txt", content: "modified\n")
        ])

        let tool_context = ToolContext(workspace: context)
        let preparation = try await tool.prepare(input, in: tool_context)

        let multiInput = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: "sample.txt", content: "modified\n"),
            .init(kind: .replace_text, path: "second.txt", content: "changed\n")
        ])
        let multiPrepared = try await tool.prepare(multiInput, in: tool_context)
        let multiDifference = try Expect.notNil(
            multiPrepared.review.preview.differences.first,
            "multi-file mutation retains a review difference"
        )
        try Expect.true(
            multiDifference.source == nil,
            "multi-file previews must not collapse distinct files into one TextDifference"
        )
        try Expect.true(
            multiDifference.layout.changes.insertions.count >= 2,
            "multi-file fallback retains both text changes"
        )
        let multiSections = try Expect.notNil(
            multiDifference.sections,
            "multi-file mutation exposes bounded semantic sections"
        )
        try Expect.equal(multiSections.count, 2, "both changed files have sections")
        try Expect.true(
            Set(multiSections.map(\.path)) == Set(["sample.txt", "second.txt"]),
            "semantic section paths use authorized presentation names"
        )
        try Expect.true(
            multiSections.allSatisfy { section in
                section.projection.rows.contains { row in
                    row.old?.role == .delete || row.new?.role == .insert
                }
            },
            "each semantic section preserves changed lines"
        )
        try Expect.equal(
            try JSONDecoder().decode(
                ToolPreflight.Preview.Difference.self,
                from: JSONEncoder().encode(multiDifference)
            ),
            multiDifference,
            "multi-file semantic preview survives serialization"
        )

        // A change in the middle of a long file must not transport untouched
        // source lines outside the existing three-line review context.
        let longFile = root.appendingPathComponent("large.txt")
        let hidden = "untouched-source-outside-review"
        let longOld = ([hidden] + (1...120).map { "record-\($0)" })
            .joined(separator: "\n") + "\n"
        let longNew = longOld.replacingOccurrences(
            of: "record-60\n", with: "modified-record-60\n"
        )
        try longOld.write(to: longFile, atomically: true, encoding: .utf8)
        let longInput = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: "large.txt", content: longNew)
        ])
        let longPrepared = try await tool.prepare(longInput, in: tool_context)
        let longDifference = try Expect.notNil(
            longPrepared.review.preview.differences.first,
            "long text mutation produces a review"
        )
        try Expect.true(
            longDifference.source == nil,
            "partial-context previews must not transport whole source differences"
        )
        let longSections = try Expect.notNil(
            longDifference.sections,
            "partial-context mutation uses semantic sections"
        )
        try Expect.equal(longSections.count, 1, "one changed file has one section")
        let visible = longSections[0].projection.rows
        try Expect.true(
            visible.contains { $0.old?.text == "record-60" },
            "review retains the original changed line"
        )
        try Expect.true(
            visible.contains { $0.new?.text == "modified-record-60" },
            "review retains the replacement line"
        )
        try Expect.true(
            !visible.contains { $0.old?.text == hidden || $0.new?.text == hidden },
            "semantic projection excludes out-of-context source text"
        )
        try Expect.true(
            visible.contains { row in
                if case .collapsed = row.kind { return true }
                return false
            },
            "long-file projection preserves collapsed regions"
        )
        let preview = preparation.review
        try Expect.true(preview.summary.contains("Stage"), "coordinated tool preflight advertises staging")
        let result = try await tool.call(input, prepared: preparation.operation, in: tool_context)
        try Expect.equal(result.status, "staged", "mutate stages under coordination")
        let staged_work = try Expect.notNil(preparation.operation, "staged preparation has plan")
        try Expect.equal(result.planID, try staged_work.plan.decode(MutatePreparedWork.self).plan.id, "staged plan uses reviewed identity")
        try Expect.true(result.submissionID != nil, "staged result carries submission ID")
        try Expect.true(result.resultID == nil, "staged result is not a published result")
        try Expect.equal(result.records.count, 0, "no disk mutation records before publication")
        try Expect.equal(
            try String(contentsOf: file, encoding: .utf8),
            "original\n",
            "coordinated mutate does not publish"
        )
        try Expect.true(result.note != nil, "staged output explains it is not yet on disk")
        let stagedRead = try await SystemIO.Tools.Read().call(
            .init(path: "sample.txt"),
            in: tool_context
        )
        try Expect.equal(
            stagedRead.files.first?.content, "modified\n",
            "a participant reads its own staged change before publication"
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

        // An owner-granted participant publishes on admission.
        let granted = WorkspaceCoordinatedSubmission(
            participant: await coordinator.participant(name: "agenticio-root")
        ) { id in
            try await coordinator.publish(submissions: [id])
        }
        let grantedContext = ToolContext(workspace: try authority.context(
            execution: .init(io: .blocking, mutations: .coordinated(granted))
        ))
        let rootInput = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: "second.txt", content: "root\n")
        ])
        let rootPrepared = try await tool.prepare(rootInput, in: grantedContext)
        let rootResult = try await tool.call(
            rootInput, prepared: rootPrepared.operation, in: grantedContext
        )
        try Expect.equal(rootResult.status, "applied", "granted publication applies on approval")
        try Expect.equal(rootResult.entries.map(\.path), ["second.txt"], "entry paths are workspace-relative")
        try Expect.equal(rootResult.records.map(\.target), ["second.txt"], "record paths are workspace-relative")
        try Expect.true(
            !String(decoding: try JSONEncoder().encode(rootResult), as: UTF8.self).contains(root.path),
            "no absolute workspace paths reach the model"
        )
        try Expect.equal(
            try String(contentsOf: second_file, encoding: .utf8), "root\n",
            "granted publication reaches the disk"
        )

        // Recovery: not blocked yet, so the tool refuses.
        let recovering = WorkspaceCoordinatedSubmission(
            participant: await coordinator.participant(name: "agenticio-recovering"),
            publication: { id in try await coordinator.publish(submissions: [id]) },
            recovery: .init(
                cause: { await coordinator.recovery_cause() },
                recover: { await coordinator.recover() }
            )
        )
        let recoveringContext = ToolContext(workspace: try authority.context(
            execution: .init(io: .blocking, mutations: .coordinated(recovering))
        ))
        let recover = SystemIO.Tools.RecoverMutations()
        let recoverInput = SystemIO.Tools.RecoverMutations.Input(reason: "checked second.txt")
        var idle = false
        do {
            _ = try await recover.preflight(recoverInput, in: recoveringContext)
        } catch RecoverMutationsToolError.nothing_to_recover {
            idle = true
        }
        try Expect.true(idle, "recover refuses when nothing is blocked")

        // A stale rollback blocks the coordinator; mutate then names the recovery tool.
        let later = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: "second.txt", content: "later\n")
        ])
        _ = try await tool.call(
            later, prepared: try await tool.prepare(later, in: grantedContext).operation, in: grantedContext
        )
        let first_publication = try Expect.notNil(await coordinator.journal().compactMap { submission -> UUID? in
            if case .committed(let id) = submission.state { return id }
            return nil
        }.dropLast().last, "recover.earlier_publication")
        _ = try await coordinator.rollback(publication_id: first_publication)
        try Expect.true(await coordinator.requires_recovery(), "recover.blocked")
        var named = false
        do {
            let blocked = SystemIO.Tools.Mutate.Input(entries: [
                .init(kind: .replace_text, path: "second.txt", content: "blocked\n")
            ])
            _ = try await tool.call(
                blocked,
                prepared: try await tool.prepare(blocked, in: recoveringContext).operation,
                in: recoveringContext
            )
        } catch let error as PreparedWritersPublicationError {
            named = error.localizedDescription.contains("io_tool_recover_mutations")
        }
        try Expect.true(named, "blocked mutate names io_tool_recover_mutations")

        let review = try await recover.preflight(recoverInput, in: recoveringContext)
        try Expect.equal(review.risk, .privileged, "recovery is always reviewed")
        try Expect.true(review.summary.contains("checked second.txt"), "review carries the agent's reason")
        let recovered = try await recover.call(recoverInput, in: recoveringContext)
        try Expect.true(recovered.recovered, "recover unblocks")
        try Expect.false(await coordinator.requires_recovery(), "coordinator unblocked")
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
        let tool = SystemIO.Tools.Mutate()
        let input = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: "approved.txt", content: "approved\n")
        ])
        let prepared = try await tool.prepare(input, in: context)
        let envelope = try Expect.notNil(prepared.operation, "review retains a serializable plan")
        let work = try envelope.plan.decode(MutatePreparedWork.self)
        let presentedPath = try FileToolAccess.authorize(
            workspace: workspace,
            path: "approved.txt",
            capability: .write,
            toolName: SystemIO.Tools.Mutate.identifier.rawValue
        ).presentationPath
        let projected = try PreparedMutationDifferenceProjection.project(
            work.plan,
            root: workspace.rootURL,
            presentationPaths: [[presentedPath]]
        )
        try Expect.equal(
            prepared.review.preview.differences.first,
            projected,
            "mutate and semantic refactoring share an identical review diff"
        )
        try Expect.true(
            projected?.layout.lines.contains(where: { $0.role == .headerNew }) == true,
            "native projection retains line-level diff headers"
        )

        do {
            _ = try await tool.call(input, in: context)
            try Expect.true(false, "direct unprepared call should fail")
        } catch ToolPreparationError.prepared_operation_required {}

        let modified = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: "approved.txt", content: "other\n")
        ])
        do {
            _ = try await tool.call(modified, prepared: envelope, in: context)
            try Expect.true(false, "input substitution must fail")
        } catch MutatePreparedWorkError.context_mismatch {}
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), "before\n", "unchanged before execution")

        // Transport and checkpoint persistence preserve the *same* plan bytes.
        let reviewed = ToolInvocation.Review(
            invocation: ToolInvocation(
                id: "roundtrip",
                tool: SystemIO.Tools.Mutate.identifier,
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

        let stale = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: "approved.txt", content: "stale-write\n")
        ])
        let stale_prepared = try await tool.prepare(stale, in: context)
        try "external\n".write(to: file, atomically: true, encoding: .utf8)
        var rejected = false
        do {
            _ = try await tool.call(stale, prepared: stale_prepared.operation, in: context)
        } catch MutateToolError.publication_failed(let status, _, _, _, let recoveryRequired) {
            rejected = status == .failed && !recoveryRequired
        }
        try Expect.true(rejected, "Writers rejects stale source snapshots as a clean tool error")
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), "external\n", "no stale overwrite")

        var registry = ToolRegistry()
        try registry.register(SystemIO.Tools.Mutate())
        let invoked_input = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: "approved.txt", content: "invoked\n")
        ])
        let invocation = ToolInvocation(
            id: "prepared-plan-invocation",
            tool: SystemIO.Tools.Mutate.identifier,
            arguments: try JSONValue.encoding(invoked_input)
        )
        let invoked = try await ToolExecutor(
            registry: registry,
            policy: .init(autonomyMode: .auto_bounded_mutate)
        ).invoke(invocation, context: context)
        try Expect.true(invoked.execution != nil, "invoker executes reviewed plan")
        try Expect.equal(try String(contentsOf: file, encoding: .utf8), "invoked\n", "bound plan applied")
        return [.field("bound_plan", work.plan.id.uuidString)]
    }

}
