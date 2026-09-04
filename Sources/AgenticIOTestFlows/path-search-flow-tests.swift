import Agentic
import AgenticExecution
import AgenticIO
import AgenticWorkspace
import Foundation
import TestFlows

extension AgenticIOFlowTesting {
    static func runPathSearch() async throws -> [TestFlowDiagnostic] {
        let fixture = try PathSearchFixture.make()

        defer {
            fixture.remove()
        }

        var registry = ToolRegistry()

        try registry.register(
            CoreWorkspaceToolSet()
        )

        _ = try Expect.notNil(
            registry.registeredTool(
                named: "find_paths"
            ),
            "AgenticIO registers find_paths in the workspace tool set"
        )

        let schema = String(
            describing: FindPathsToolInput.jsonschema
        )

        for field in [
            "query",
            "queries",
            "strategy",
            "caseSensitive",
            "minimumScore",
            "maxEntries",
        ] {
            try Expect.contains(
                schema,
                field,
                "find_paths schema exposes \(field)"
            )
        }

        let rankedOutput = try await FindPathsTool().call(
            FindPathsToolInput(
                                queries: [
                                    .init(
                                        text: "A.swift",
                                        id: "filename",
                                        weight: 4
                                    ),
                                    .init(
                                        text: "Sources",
                                        id: "directory"
                                    ),
                                ],
                                includes: [
                                    "Sources/**",
                                ],
                                includeFiles: true,
                                includeDirectories: false,
                                strategy: .contains,
                                caseSensitive: true,
                                maxEntries: 8
                            ),
            context: .init(
                workspace: fixture.workspace
            )
        )
        let ranked = rankedOutput

        try Expect.equal(
            ranked.searchedPathCount ?? -1,
            2,
            "find_paths searches the authorized admitted path universe"
        )

        let first = try Expect.notNil(
            ranked.entries.first,
            "find_paths returns a ranked path"
        )

        try Expect.equal(
            first.path,
            "Sources/A.swift",
            "weighted path probes rank the strongest match first"
        )
        try Expect.equal(
            first.probeCount ?? -1,
            2,
            "ranked path retains converging probe evidence"
        )
        try Expect.equal(
            (first.evidence ?? []).compactMap(\.queryID).sorted(),
            [
                "directory",
                "filename",
            ],
            "path evidence retains probe identity"
        )
        try Expect.equal(
            (first.evidence ?? []).map(\.strategy),
            [
                .contains,
                .contains,
            ],
            "path evidence retains compact matching strategy"
        )
        try Expect.equal(
            (first.evidence ?? []).allSatisfy {
                $0.score > 0
            },
            true,
            "path evidence retains scalar probe scores without Search ranking internals"
        )

        let legacyOutput = try await FindPathsTool().call(
            FindPathsToolInput(
                                query: "a.SWIFT",
                                includes: [
                                    "Sources/**",
                                ],
                                includeFiles: true,
                                includeDirectories: false
                            ),
            context: .init(
                workspace: fixture.workspace
            )
        )
        let legacy = legacyOutput

        try Expect.equal(
            legacy.entries.map(\.path),
            [
                "Sources/A.swift",
            ],
            "legacy query remains a case-insensitive contains search by default"
        )

        let excludedOutput = try await FindPathsTool().call(
            FindPathsToolInput(
                                queries: [
                                    .init(
                                        text: "Sources"
                                    ),
                                ],
                                includes: [
                                    "Sources/**",
                                ],
                                excludes: [
                                    "Sources/B.swift",
                                ],
                                includeFiles: true,
                                includeDirectories: false,
                                strategy: .contains,
                                caseSensitive: true
                            ),
            context: .init(
                workspace: fixture.workspace
            )
        )
        let excluded = excludedOutput

        try Expect.equal(
            excluded.searchedPathCount ?? -1,
            1,
            "path exclusions narrow the authorized universe before Search ranking"
        )
        try Expect.equal(
            excluded.entries.map(\.path),
            [
                "Sources/A.swift",
            ],
            "find_paths returns only the non-excluded ranked path"
        )

        return [
            .message(
                "find_paths preserves its workspace scan surface while adapting path names into weighted Search ranking with compact model-facing evidence"
            ),
        ]
    }
}

private struct PathSearchFixture {
    let root: URL
    let workspace: AgentWorkspace

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-path-search-\(UUID().uuidString)",
                isDirectory: true
            )
        let sources = root.appendingPathComponent(
            "Sources",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: sources,
            withIntermediateDirectories: true
        )
        try "alpha".write(
            to: sources.appendingPathComponent(
                "A.swift"
            ),
            atomically: true,
            encoding: .utf8
        )
        try "beta".write(
            to: sources.appendingPathComponent(
                "B.swift"
            ),
            atomically: true,
            encoding: .utf8
        )

        return .init(
            root: root,
            workspace: try AgentWorkspace(
                root: root
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}