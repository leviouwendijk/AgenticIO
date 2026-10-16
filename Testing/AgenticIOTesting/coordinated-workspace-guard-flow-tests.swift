import Agentic
import AgenticIO
import Workspace
import Writers
import Foundation
import Path
import Testing

extension AgenticIOFlowTesting {
    static func runCoordinatedWorkspaceGuard() async throws -> [TestDiagnostic] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "workspace-coordinated-guard-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sample.txt")
        try "original\n".write(to: file, atomically: true, encoding: .utf8)

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
        let coordinator = StandardEditCoordinator()
        let context = try authority.context(
            execution: .init(io: .blocking, mutations: .coordinated(coordinator))
        )
        let tool = SystemIO.Tools.MutateFiles()
        let input = SystemIO.Tools.MutateFiles.Input(entries: [
            .init(kind: .replace_text, path: "sample.txt", content: "modified\n")
        ])

        var rejected_preflight = false
        do {
            _ = try await tool.preflight(input, in: ToolContext(workspace: context))
        } catch WorkspaceExecutionError.coordinatedMutationRequiresSubmission {
            rejected_preflight = true
        }
        try Expect.true(rejected_preflight, "coordinated mode rejects immediate-write preflight")

        var rejected_call = false
        do {
            _ = try await tool.call(input, in: ToolContext(workspace: context))
        } catch WorkspaceExecutionError.coordinatedMutationRequiresSubmission {
            rejected_call = true
        }
        try Expect.true(rejected_call, "coordinated mode rejects direct tool execution")

        var rejected_editor = false
        do {
            _ = try FileEditor(workspace: context).write("modified\n", to: "sample.txt")
        } catch WorkspaceExecutionError.coordinatedMutationRequiresSubmission {
            rejected_editor = true
        }
        try Expect.true(rejected_editor, "coordinated mode rejects direct FileEditor writes")
        try Expect.equal(
            try String(contentsOf: file, encoding: .utf8),
            "original\n",
            "coordinated mode never writes through immediate mutation paths"
        )
        let nested = try context.context(atRootPath: ".")
        switch nested.execution.mutations {
        case .coordinated(let preserved):
            try Expect.true(preserved === coordinator, "derived context retains coordinator")
        case .immediate:
            try Expect.true(false, "derived context lost coordinator")
        }
        return [.field("coordinator", "preserved-and-guarded")]
    }
}
