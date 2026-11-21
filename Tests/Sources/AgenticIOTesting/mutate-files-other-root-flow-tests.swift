import Agentic
import AgenticIO
import Foundation
import Path
import Testing
import Workspace
import Writers

extension AgenticIOFlowTesting {
    /// A mutation whose targets all lie in another root of the workspace
    /// runs there: that root's grants and policy, written in place.
    static func runMutateFilesOtherRoot() async throws -> [TestDiagnostic] {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("mutate-other-root-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        let project = base.appendingPathComponent("project", isDirectory: true)
        let notes = base.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let note = notes.appendingPathComponent("n.txt")
        try "before\n".write(to: note, atomically: true, encoding: .utf8)

        func root(_ id: String, _ url: URL, isDefault: Bool) throws -> PathAccessRoot {
            PathAccessRoot(
                id: .init(rawValue: id),
                label: id,
                scope: try PathAccessScope(root: url, policy: .defaults.workspace),
                isDefault: isDefault
            )
        }
        let workspace = try Workspace(
            roots: [try root("project", project, isDefault: true), try root("notes", notes, isDefault: false)],
            defaultRootIdentifier: .init(rawValue: "project"),
            grants: [
                try WorkspaceGrant(
                    id: try WorkspaceGrantIdentifier("project-all"),
                    rootIdentifier: .init(rawValue: "project"),
                    capabilities: Set(WorkspaceCapability.allCases)
                ),
                try WorkspaceGrant(
                    id: try WorkspaceGrantIdentifier("notes-all"),
                    rootIdentifier: .init(rawValue: "notes"),
                    capabilities: Set(WorkspaceCapability.allCases)
                ),
            ]
        )
        let context = try workspace.context(execution: .init(io: .blocking, mutations: .immediate))
        let tool = SystemIO.Tools.Mutate()
        let input = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: note.path, content: "after\n"),
        ])
        let prepared = try await tool.prepare(input, in: ToolContext(workspace: context))
        _ = try await tool.call(input, prepared: prepared.operation, in: ToolContext(workspace: context))
        try Expect.equal(try String(contentsOf: note, encoding: .utf8), "after\n", "written in the other root")

        // Coordinated: staged under the other root, published by the owner.
        let coordinator = StandardMutationCoordinator()
        let participant = await coordinator.participant(name: "other-root")
        let staged = try workspace.context(execution: .init(
            io: .blocking,
            mutations: .coordinated(WorkspaceCoordinatedSubmission(participant: participant))
        ))
        let second = SystemIO.Tools.Mutate.Input(entries: [
            .init(kind: .replace_text, path: note.path, content: "staged\n"),
        ])
        let preparedStaged = try await tool.prepare(second, in: ToolContext(workspace: staged))
        _ = try await tool.call(second, prepared: preparedStaged.operation, in: ToolContext(workspace: staged))
        try Expect.equal(try String(contentsOf: note, encoding: .utf8), "after\n", "staged, not yet written")
        let pending = await coordinator.pending_submission_ids()
        try Expect.equal(pending.count, 1, "one staged unit")
        _ = try await coordinator.publish(submissions: pending)
        try Expect.equal(try String(contentsOf: note, encoding: .utf8), "staged\n", "published into the other root")

        // One call mutates one root.
        let project_file = project.appendingPathComponent("p.txt")
        try "p\n".write(to: project_file, atomically: true, encoding: .utf8)
        do {
            _ = try await tool.prepare(.init(entries: [
                .init(kind: .replace_text, path: note.path, content: "x\n"),
                .init(kind: .replace_text, path: "p.txt", content: "y\n"),
            ]), in: ToolContext(workspace: context))
            try Expect.true(false, "targets in two roots are refused")
        } catch {
            try Expect.true(String(describing: error).contains("several workspace roots"), "\(error)")
        }
        return []
    }
}
