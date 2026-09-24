import Agentic
import AgenticExecution
import AgenticIO
import Workspace
import Foundation
import Testing

extension AgenticIOFlowTesting {
    static func runMutateFilesWorkspaceTargeting() async throws -> [TestDiagnostic] {
        let fixture = try MutateFilesWorkspaceTargetFixture.make()

        defer {
            fixture.remove()
        }

        let tool = SystemIO.Tools.MutateFiles()
        let input = MutateFilesToolInput(
                        entries: [
                            .init(
                                kind: .replace_text,
                                path: "target.txt",
                                content: "targeted\n"
                            ),
                        ]
                    )

        let preflight = try await tool.preflight(
            input,
            workspace: fixture.workspace
        )

        try Expect.equal(
            preflight.access.targets,
            [
                "Package/target.txt",
            ],
            "workspace-targeted mutate_files preflight resolves relative to the working location"
        )

        _ = try await tool.call(
            input,
            workspace: fixture.workspace
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

        let copySourceDirectory = fixture.targetDirectoryURL
            .appendingPathComponent(
                "CopySource",
                isDirectory: true
            )
        let copySourceFile = copySourceDirectory
            .appendingPathComponent(
                "nested/fixture.txt"
            )
        let copyDestinationDirectory = fixture.targetDirectoryURL
            .appendingPathComponent(
                "CopyDestination",
                isDirectory: true
            )
        let copyDestinationFile = copyDestinationDirectory
            .appendingPathComponent(
                "nested/fixture.txt"
            )

        try FileManager.default.createDirectory(
            at: copySourceFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "copy fixture\n".write(
            to: copySourceFile,
            atomically: true,
            encoding: .utf8
        )

        let copyInput = MutateFilesToolInput(
            failurePolicy: .stop,
            entries: [
                .init(
                    kind: .copy,
                    path: "CopySource",
                    destination: "CopyDestination"
                ),
            ]
        )
        let copyPreflight = try await tool.preflight(
            copyInput,
            workspace: fixture.workspace
        )

        try Expect.equal(
            copyPreflight.access.targets,
            [
                "Package/CopySource",
                "Package/CopyDestination",
            ],
            "workspace-targeted mutate_files copy authorizes source and destination"
        )

        let copyOutput = try await tool.call(
            copyInput,
            workspace: fixture.workspace
        )

        try Expect.equal(
            copyOutput.status,
            "applied",
            "workspace-targeted mutate_files copy applies"
        )
        try Expect.true(
            FileManager.default.fileExists(
                atPath: copySourceFile.path
            ),
            "workspace-targeted mutate_files copy preserves the source"
        )
        try Expect.equal(
            try String(
                contentsOf: copyDestinationFile,
                encoding: .utf8
            ),
            "copy fixture\n",
            "workspace-targeted mutate_files copy recursively copies directory contents"
        )
        try Expect.equal(
            copyOutput.rollbackAvailable,
            false,
            "workspace-targeted mutate_files directory copy reports no rollback plan"
        )

        let escapingInput = MutateFilesToolInput(
                        entries: [
                            .init(
                                kind: .replace_text,
                                path: "../../outside.txt",
                                content: "escaped\n"
                            ),
                        ]
                    )
        var escapeRejected = false

        do {
            _ = try await tool.preflight(
                escapingInput,
                workspace: fixture.workspace
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
    let workspace: WorkspaceContext

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

        let fixture = Self(
            containerURL: containerURL,
            workspaceURL: workspaceURL,
            targetDirectoryURL: targetDirectoryURL,
            workspace: try makeAgenticIOTestingWorkspace(
                root: workspaceURL,
                at: "Package"
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
