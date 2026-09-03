import Agentic
import AgenticExecution
import AgenticIO
import AgenticWorkspace
import Foundation
import TestFlows

extension AgenticIOFlowTesting {
    static func runMutateFilesWorkspaceTargeting() async throws -> [TestFlowDiagnostic] {
        let fixture = try MutateFilesWorkspaceTargetFixture.make()

        defer {
            fixture.remove()
        }

        let tool = MutateFilesTool()
        let _: any WorkspaceTargetableTool = tool
        let location = try fixture.workspace.location(
            for: WorkspaceTarget(
                subpath: "Package"
            )
        )
        let context = AgentToolExecutionContext(
            workspace: fixture.workspace,
            workspaceLocation: location
        )
        let input = try JSONToolBridge.encode(
            MutateFilesToolInput(
                entries: [
                    .init(
                        kind: .replace_text,
                        path: "target.txt",
                        content: "targeted\n"
                    ),
                ]
            )
        )

        let preflight = try await tool.preflight(
            input: input,
            context: context
        )

        try Expect.equal(
            preflight.targetPaths,
            [
                "Package/target.txt",
            ],
            "workspace-targeted mutate_files preflight resolves relative to the working location"
        )

        _ = try await tool.call(
            input: input,
            context: context
        )

        try Expect.equal(
            try String(
                contentsOf: fixture.targetFileURL,
                encoding: .utf8
            ),
            "targeted\n",
            "workspace-targeted mutate_files changes the target-local file"
        )
        try Expect.equal(
            try String(
                contentsOf: fixture.rootFileURL,
                encoding: .utf8
            ),
            "root\n",
            "workspace-targeted mutate_files does not reinterpret the path at the authority root"
        )

        let escapingInput = try JSONToolBridge.encode(
            MutateFilesToolInput(
                entries: [
                    .init(
                        kind: .replace_text,
                        path: "../../outside.txt",
                        content: "escaped\n"
                    ),
                ]
            )
        )
        var escapeRejected = false

        do {
            _ = try await tool.preflight(
                input: escapingInput,
                context: context
            )
        } catch {
            escapeRejected = true
        }

        try Expect.true(
            escapeRejected,
            "workspace targeting cannot escape the original workspace authority"
        )
        try Expect.equal(
            try String(
                contentsOf: fixture.outsideFileURL,
                encoding: .utf8
            ),
            "outside\n",
            "rejected workspace-target traversal leaves outside material unchanged"
        )

        return [
            .field(
                "target",
                "Package/target.txt"
            ),
            .field(
                "authority",
                "preserved"
            ),
        ]
    }
}

private struct MutateFilesWorkspaceTargetFixture {
    let containerURL: URL
    let workspaceURL: URL
    let targetDirectoryURL: URL
    let workspace: AgentWorkspace

    var rootFileURL: URL {
        workspaceURL.appendingPathComponent(
            "target.txt"
        )
    }

    var targetFileURL: URL {
        targetDirectoryURL.appendingPathComponent(
            "target.txt"
        )
    }

    var outsideFileURL: URL {
        containerURL.appendingPathComponent(
            "outside.txt"
        )
    }

    static func make() throws -> Self {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-workspace-target-\(UUID().uuidString)",
                isDirectory: true
            )
        let workspaceURL = containerURL.appendingPathComponent(
            "workspace",
            isDirectory: true
        )
        let targetDirectoryURL = workspaceURL.appendingPathComponent(
            "Package",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: targetDirectoryURL,
            withIntermediateDirectories: true
        )

        let fixture = try Self(
            containerURL: containerURL,
            workspaceURL: workspaceURL,
            targetDirectoryURL: targetDirectoryURL,
            workspace: AgentWorkspace(
                root: workspaceURL
            )
        )

        try "root\n".write(
            to: fixture.rootFileURL,
            atomically: true,
            encoding: .utf8
        )
        try "target\n".write(
            to: fixture.targetFileURL,
            atomically: true,
            encoding: .utf8
        )
        try "outside\n".write(
            to: fixture.outsideFileURL,
            atomically: true,
            encoding: .utf8
        )

        return fixture
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: containerURL
        )
    }
}
