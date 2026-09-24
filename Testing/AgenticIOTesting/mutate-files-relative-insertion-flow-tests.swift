import Agentic
import AgenticExecution
import AgenticIO
import Workspace
import Foundation
import Schema
import Testing

extension AgenticIOFlowTesting {
    static func runMutateFilesRelativeInsertion()
        async throws -> [TestDiagnostic]
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-relative-insertion-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: root
            )
        }

        let fileURL = root.appendingPathComponent(
            "sample.txt"
        )

        try "alpha\nbeta\ngamma\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        let workspace = try makeAgenticIOTestingWorkspace(
            root: root
        )
        let tool = SystemIO.Tools.MutateFiles()
        let schema = String(
            describing: MutateFilesToolInput.jsonschema
        )

        try Expect.contains(
            schema,
            "insert_before",
            "mutate_files schema exposes insert_before"
        )
        try Expect.contains(
            schema,
            "insert_after",
            "mutate_files schema exposes insert_after"
        )

        let input = MutateFilesToolInput(
            entries: [
                .init(
                    kind: .edit_text,
                    path: "sample.txt",
                    operations: [
                        .insert_before(
                            .init(
                                line: 2,
                                lines: [
                                    "before-beta",
                                ]
                            )
                        ),
                        .insert_after(
                            .init(
                                line: 2,
                                lines: [
                                    "after-beta",
                                ]
                            )
                        ),
                    ]
                ),
            ]
        )

        let preflight = try await tool.preflight(
            input,
            workspace: workspace
        )

        try Expect.equal(
            preflight.access.targets,
            [
                "sample.txt",
            ],
            "relative insertion preflight targets the edited file"
        )

        _ = try await tool.call(
            input,
            workspace: workspace
        )

        try Expect.equal(
            try String(
                contentsOf: fileURL,
                encoding: .utf8
            ),
            "alpha\nbefore-beta\nbeta\nafter-beta\ngamma\n",
            "insert_before and insert_after lower against the original line snapshot"
        )

        let invalid = MutateFilesToolInput(
            entries: [
                .init(
                    kind: .edit_text,
                    path: "sample.txt",
                    operations: [
                        .insert_before(
                            .init(
                                line: 7,
                                lines: [
                                    "invalid",
                                ]
                            )
                        ),
                    ]
                ),
            ]
        )

        var invalidLineRejected = false

        do {
            _ = try await tool.preflight(
                invalid,
                workspace: workspace
            )
        } catch {
            invalidLineRejected = true
        }

        try Expect.true(
            invalidLineRejected,
            "insert_before rejects Writers lineCount + 1 because the referenced line must exist"
        )

        return [
            .field(
                "insert_before",
                "line 2 -> insertion position 2"
            ),
            .field(
                "insert_after",
                "line 2 -> insertion position 3"
            ),
        ]
    }
}
