import Agentic
import AgenticIO
import Workspace
import Foundation
import Schema
import Testing

extension AgenticIOFlowTesting {
    static func runMutateFilesPositionRange()
        async throws -> [TestDiagnostic]
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-position-range-\(UUID().uuidString)",
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
        let multilineURL = root.appendingPathComponent(
            "multiline.txt"
        )

        try "alpha βeta\n🐕gamma delta\nomega\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
        try "one abc\ntwo def\nthree\n".write(
            to: multilineURL,
            atomically: true,
            encoding: .utf8
        )

        let workspace = try makeAgenticIOTestingWorkspace(
            root: root
        )
        let tool = SystemIO.Tools.MutateFiles()
        let schema = String(
            describing: SystemIO.Tools.MutateFiles.Input.jsonschema
        )

        try Expect.contains(
            schema,
            "replace_range",
            "mutate_files schema exposes replace_range"
        )
        try Expect.contains(
            schema,
            "position_range",
            "mutate_files schema exposes the line/column position range payload"
        )

        let decoded = try JSONDecoder().decode(
            FileEditOperation.self,
            from: Data(
                """
                {
                  "kind": "replace_range",
                  "position_range": {
                    "start": {
                      "line": 1,
                      "column": 7
                    },
                    "end": {
                      "line": 1,
                      "column": 11
                    }
                  },
                  "replacement": "BETA-LONG"
                }
                """.utf8
            )
        )

        try Expect.equal(
            decoded.kind,
            .replace_range,
            "replace_range decodes from the model-facing JSON shape"
        )

        let encoded = String(
            decoding: try JSONEncoder().encode(
                decoded
            ),
            as: UTF8.self
        )

        try Expect.contains(
            encoded,
            "position_range",
            "replace_range encodes the explicit position_range field"
        )

        let input = SystemIO.Tools.MutateFiles.Input(
            entries: [
                .init(
                    kind: .edit_text,
                    path: "sample.txt",
                    operations: [
                        decoded,
                        .replace_range(
                            .init(
                                range: .init(
                                    start: .init(
                                        line: 2,
                                        column: 8
                                    ),
                                    end: .init(
                                        line: 2,
                                        column: 13
                                    )
                                ),
                                replacement: "DELTA"
                            )
                        ),
                    ]
                ),
            ]
        )

        _ = try await tool.call(
            input,
            in: ToolContext(
                workspace: workspace
            )
        )

        try Expect.equal(
            try String(
                contentsOf: fileURL,
                encoding: .utf8
            ),
            "alpha BETA-LONG\n🐕gamma DELTA\nomega\n",
            "multiple position ranges resolve against the original Character-coordinate snapshot"
        )

        let multiline = SystemIO.Tools.MutateFiles.Input(
            entries: [
                .init(
                    kind: .edit_text,
                    path: "multiline.txt",
                    operations: [
                        .replace_range(
                            .init(
                                range: .init(
                                    start: .init(
                                        line: 1,
                                        column: 5
                                    ),
                                    end: .init(
                                        line: 2,
                                        column: 4
                                    )
                                ),
                                replacement: "X"
                            )
                        ),
                    ]
                ),
            ]
        )

        _ = try await tool.call(
            multiline,
            in: ToolContext(
                workspace: workspace
            )
        )

        try Expect.equal(
            try String(
                contentsOf: multilineURL,
                encoding: .utf8
            ),
            "one X def\nthree\n",
            "replace_range may cross line boundaries without replacing either entire line"
        )

        let invalid = SystemIO.Tools.MutateFiles.Input(
            entries: [
                .init(
                    kind: .edit_text,
                    path: "sample.txt",
                    operations: [
                        .replace_range(
                            .init(
                                range: .init(
                                    start: .init(
                                        line: 1,
                                        column: 99
                                    ),
                                    end: .init(
                                        line: 2,
                                        column: 2
                                    )
                                ),
                                replacement: "invalid"
                            )
                        ),
                    ]
                ),
            ]
        )
        var invalidCoordinateRejected = false

        do {
            _ = try await tool.preflight(
                invalid,
                in: ToolContext(
                    workspace: workspace
                )
            )
        } catch {
            invalidCoordinateRejected = true
        }

        try Expect.true(
            invalidCoordinateRejected,
            "replace_range rejects unresolved line/column coordinates during preflight"
        )

        let mixed = SystemIO.Tools.MutateFiles.Input(
            entries: [
                .init(
                    kind: .edit_text,
                    path: "sample.txt",
                    operations: [
                        .replace_range(
                            .init(
                                range: .init(
                                    start: .init(
                                        line: 1,
                                        column: 1
                                    ),
                                    end: .init(
                                        line: 1,
                                        column: 2
                                    )
                                ),
                                replacement: "A"
                            )
                        ),
                        .replace_line(
                            .init(
                                line: 3,
                                content: "OMEGA"
                            )
                        ),
                    ]
                ),
            ]
        )
        var mixedCoordinatesRejected = false

        do {
            _ = try await tool.preflight(
                mixed,
                in: ToolContext(
                    workspace: workspace
                )
            )
        } catch {
            mixedCoordinatesRejected = true
        }

        try Expect.true(
            mixedCoordinatesRejected,
            "replace_range cannot be mixed with line-coordinate operations because snapshot coordinate families differ"
        )

        return [
            .field(
                "position_range",
                "1-based line/column -> Character-offset PositionRange"
            ),
            .field(
                "guard",
                "derived from original raw file content"
            ),
            .field(
                "snapshot",
                "range-only batches retain original coordinates"
            ),
        ]
    }
}
