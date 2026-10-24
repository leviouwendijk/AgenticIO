import Agentic
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
        let input = SystemIO.Tools.MutateFiles.Input(
                        entries: [
                            .init(
                                kind: .replace_text,
                                path: "target.txt",
                                content: "targeted\n"
                            ),
                        ]
                    )

        let prepared = try await tool.prepare(
            input,
            in: ToolContext(workspace: fixture.workspace)
        )
        let preflight = prepared.review

        try Expect.equal(
            preflight.access.targets,
            [
                "Package/target.txt",
            ],
            "workspace-targeted mutate_files preflight resolves relative to the working location"
        )

        // The preflight's two views derive from Writers, not the deprecated
        // Agentic-specific FileMutationDifference tree reconstruction.
        guard let preview = preflight.preview.difference else {
            throw MutateFilesNativeDifferenceTestError.missing_preview
        }
        try Expect.equal(
            preview.file_mutations,
            nil,
            "new native preflight previews do not construct legacy file mutation entries"
        )
        try Expect.true(
            preview.tree_layout?.lines.contains(where: {
                $0.change == .modified && $0.label == "target.txt"
            }) == true,
            "content-only replace marks the native path tree as modified"
        )
        try Expect.true(
            preview.text_layout.lines.contains(where: {
                $0.role == .headerNew && $0.text == "b/Package/target.txt"
            }),
            "text section headers retain authorized workspace-relative paths"
        )
        let restored = try JSONDecoder().decode(
            ToolPreflight.self,
            from: JSONEncoder().encode(preflight)
        )
        try Expect.equal(
            restored.preview.difference?.tree_layout,
            preview.tree_layout,
            "native tree layout survives preflight Codable round trip"
        )

        _ = try await tool.call(
            input,
            prepared: prepared.operation,
            in: ToolContext(workspace: fixture.workspace)
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

        let copyInput = SystemIO.Tools.MutateFiles.Input(
            failurePolicy: .stop,
            entries: [
                .init(
                    kind: .copy,
                    path: "CopySource",
                    destination: "CopyDestination"
                ),
            ]
        )
        let copyPrepared = try await tool.prepare(
            copyInput,
            in: ToolContext(workspace: fixture.workspace)
        )
        let copyPreflight = copyPrepared.review

        try Expect.equal(
            copyPreflight.access.targets,
            [
                "Package/CopySource",
                "Package/CopyDestination",
            ],
            "workspace-targeted mutate_files copy authorizes source and destination"
        )

        try Expect.true(
            copyPreflight.preview.difference?.tree_layout?.lines.contains(where: {
                $0.change == .added && $0.label == "CopyDestination/"
            }) == true,
            "native tree represents a copy destination as added"
        )

        let copyOutput = try await tool.call(
            copyInput,
            prepared: copyPrepared.operation,
            in: ToolContext(workspace: fixture.workspace)
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

        let escapingInput = SystemIO.Tools.MutateFiles.Input(
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
                in: ToolContext(workspace: fixture.workspace)
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

private enum MutateFilesNativeDifferenceTestError: Error {
    case missing_preview
}
