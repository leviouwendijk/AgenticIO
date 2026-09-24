import Agentic
import AgenticExecution
import AgenticIO
import Workspace
import Foundation
import Testing

extension AgenticIOFlowTesting {
    static func runPathSearch() async throws -> [TestDiagnostic] {
        let fixture = try PathSearchFixture.make()

        defer {
            fixture.remove()
        }

        var registry = ToolRegistry()

        try registry.register(
            from: CoreWorkspaceToolSet()
        )

        _ = try Expect.notNil(
            registry.registeredTool(
                named: "find_paths"
            ),
            "AgenticIO registers find_paths in the workspace tool set"
        )

        let schema = String(
            describing: SystemIO.Tools.FindPaths.Input.jsonschema
        )

        for field in [
            "query",
            "queries",
            "strategy",
            "caseSensitive",
            "minimumScore",
            "maxdepth",
            "maxEntries",
        ] {
            try Expect.contains(
                schema,
                field,
                "find_paths schema exposes \(field)"
            )
        }

        let scanSchema = String(
            describing: SystemIO.Tools.ScanPaths.Input.jsonschema
        )

        try Expect.contains(
            scanSchema,
            "maxdepth",
            "scan_paths schema exposes flatcase maxdepth"
        )
        try Expect.equal(
            scanSchema.contains("maxDepth"),
            false,
            "scan_paths schema does not expose camelcase maxDepth"
        )
        try Expect.equal(
            schema.contains("maxDepth"),
            false,
            "find_paths schema does not expose camelcase maxDepth"
        )

        let decodedScanInput = try JSONDecoder().decode(
            SystemIO.Tools.ScanPaths.Input.self,
            from: Data(
                #"{"maxdepth":2}"#.utf8
            )
        )
        try Expect.equal(
            decodedScanInput.maxdepth ?? -1,
            2,
            "scan_paths decodes flatcase maxdepth"
        )

        let decodedFindInput = try JSONDecoder().decode(
            SystemIO.Tools.FindPaths.Input.self,
            from: Data(
                #"{"maxdepth":2}"#.utf8
            )
        )
        try Expect.equal(
            decodedFindInput.maxdepth ?? -1,
            2,
            "find_paths decodes flatcase maxdepth"
        )

        let rankedOutput = try await SystemIO.Tools.FindPaths().call(
            SystemIO.Tools.FindPaths.Input(
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
            workspace: fixture.workspace
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

        let legacyOutput = try await SystemIO.Tools.FindPaths().call(
            SystemIO.Tools.FindPaths.Input(
                                query: "a.SWIFT",
                                includes: [
                                    "Sources/**",
                                ],
                                includeFiles: true,
                                includeDirectories: false
                            ),
            workspace: fixture.workspace
        )
        let legacy = legacyOutput

        try Expect.equal(
            legacy.entries.map(\.path),
            [
                "Sources/A.swift",
            ],
            "legacy query remains a case-insensitive contains search by default"
        )

        let excludedOutput = try await SystemIO.Tools.FindPaths().call(
            SystemIO.Tools.FindPaths.Input(
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
            workspace: fixture.workspace
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

        let shallowFind = try await SystemIO.Tools.FindPaths().call(
            SystemIO.Tools.FindPaths.Input(
                query: "A.swift",
                recursive: true,
                maxdepth: 1,
                includeFiles: true,
                includeDirectories: false,
                strategy: .contains
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            shallowFind.entries.contains {
                $0.path == "Sources/A.swift"
            },
            false,
            "find_paths maxdepth 1 overrides recursive true"
        )

        let deepFind = try await SystemIO.Tools.FindPaths().call(
            SystemIO.Tools.FindPaths.Input(
                query: "A.swift",
                recursive: false,
                maxdepth: 2,
                includeFiles: true,
                includeDirectories: false,
                strategy: .contains
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            deepFind.entries.contains {
                $0.path == "Sources/A.swift"
            },
            true,
            "find_paths maxdepth 2 overrides recursive false"
        )

        let shallowScan = try await SystemIO.Tools.ScanPaths().call(
            SystemIO.Tools.ScanPaths.Input(
                includeFiles: true,
                includeDirectories: true,
                recursive: true,
                maxdepth: 1
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            shallowScan.entries.contains {
                $0.path == "Sources/A.swift"
            },
            false,
            "scan_paths maxdepth 1 overrides recursive true"
        )

        let deepScan = try await SystemIO.Tools.ScanPaths().call(
            SystemIO.Tools.ScanPaths.Input(
                includeFiles: true,
                includeDirectories: true,
                recursive: false,
                maxdepth: 2
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            deepScan.entries.contains {
                $0.path == "Sources/A.swift"
            },
            true,
            "scan_paths maxdepth 2 overrides recursive false"
        )

        return [
            .message(
                "find_paths and scan_paths preserve existing traversal defaults while explicit flatcase maxdepth provides bounded depth control"
            ),
        ]
    }
}

private struct PathSearchFixture {
    let root: URL
    let workspace: WorkspaceContext

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
            workspace: try makeAgenticIOTestingWorkspace(
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