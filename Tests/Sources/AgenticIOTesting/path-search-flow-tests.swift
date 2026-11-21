import Agentic
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

        try registry.register(SystemIO.Tools.Find())

        _ = try Expect.notNil(
            registry.registeredTool(
                named: "find"
            ),
            "AgenticIO registers find in the workspace tool set"
        )

        let schema = String(
            describing: SystemIO.Tools.Find.Input.jsonschema
        )

        for field in [
            "path",
            "query",
            "queries",
            "strategy",
            "caseSensitive",
            "minimumScore",
            "maxdepth",
            "maxEntries",
            "directoryState",
            "expand",
        ] {
            try Expect.contains(
                schema,
                field,
                "find schema exposes \(field)"
            )
        }

        try Expect.equal(
            schema.contains("maxDepth"),
            false,
            "find schema does not expose camelcase maxDepth"
        )

        let decodedFindInput = try JSONDecoder().decode(
            SystemIO.Tools.Find.Input.self,
            from: Data(
                #"{"maxdepth":2}"#.utf8
            )
        )
        try Expect.equal(
            decodedFindInput.maxdepth ?? -1,
            2,
            "find decodes flatcase maxdepth"
        )

        let rankedOutput = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(
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
            in: ToolContext(workspace: fixture.workspace)
        )
        let ranked = rankedOutput

        try Expect.equal(
            ranked.searchedPathCount ?? -1,
            2,
            "find searches the authorized admitted path universe"
        )

        let first = try Expect.notNil(
            ranked.entries.first,
            "find returns a ranked path"
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

        let shortOutput = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(
                query: "a.SWIFT",
                includes: [
                    "Sources/**",
                ],
                includeFiles: true,
                includeDirectories: false
            ),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            shortOutput.entries.map(\.path),
            [
                "Sources/A.swift",
            ],
            "query is a case-insensitive contains search by default"
        )

        let excludedOutput = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(
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
            in: ToolContext(workspace: fixture.workspace)
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
            "find returns only the non-excluded ranked path"
        )

        let shallowFind = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(
                query: "A.swift",
                recursive: true,
                maxdepth: 1,
                includeFiles: true,
                includeDirectories: false,
                strategy: .contains
            ),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            shallowFind.entries.contains {
                $0.path == "Sources/A.swift"
            },
            false,
            "find maxdepth 1 overrides recursive true"
        )

        let deepFind = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(
                query: "A.swift",
                recursive: false,
                maxdepth: 2,
                includeFiles: true,
                includeDirectories: false,
                strategy: .contains
            ),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            deepFind.entries.contains {
                $0.path == "Sources/A.swift"
            },
            true,
            "find maxdepth 2 overrides recursive false"
        )

        let defaultQuery = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(
                query: "A.swift",
                includeDirectories: false
            ),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            defaultQuery.entries.map(\.path),
            [
                "Sources/A.swift",
            ],
            "a query searches below the start directory by default"
        )

        let defaultListing = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            defaultListing.entries.map(\.path),
            [
                "Sources",
            ],
            "a plain listing shows direct entries only"
        )
        try Expect.true(
            defaultListing.isListing,
            "without a query, find lists"
        )

        let directoryListing = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(
                path: "Sources"
            ),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            directoryListing.entries.map(\.path).sorted(),
            [
                "Sources/A.swift",
                "Sources/B.swift",
            ],
            "path lists from a start directory"
        )
        try Expect.equal(
            directoryListing.directory,
            "Sources",
            "a listing names its start directory"
        )

        let globListing = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(
                includes: [
                    "**/*.swift",
                ]
            ),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            globListing.entries.map(\.path).sorted(),
            [
                "Sources/A.swift",
                "Sources/B.swift",
            ],
            "includes alone search below the start directory"
        )

        let shallowScan = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(
                recursive: true,
                maxdepth: 1,
                includeFiles: true,
                includeDirectories: true
            ),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            shallowScan.entries.contains {
                $0.path == "Sources/A.swift"
            },
            false,
            "a listing's maxdepth 1 overrides recursive true"
        )

        let deepScan = try await SystemIO.Tools.Find().call(
            SystemIO.Tools.Find.Input(
                recursive: false,
                maxdepth: 2,
                includeFiles: true,
                includeDirectories: true
            ),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            deepScan.entries.contains {
                $0.path == "Sources/A.swift"
            },
            true,
            "a listing's maxdepth 2 overrides recursive false"
        )

        // The model reads a listing as a tree; the output keeps every entry.
        let deepInput = SystemIO.Tools.Find.Input(maxdepth: 2)
        try Expect.equal(
            SystemIO.Tools.Find().render(deepScan, input: deepInput),
            """
            .: 3 entries (1 dirs, 2 files)
            Sources/
              A.swift
              B.swift
            """,
            "find renders a listing as an indented tree"
        )
        let collapsing = SystemIO.Tools.Find(projection: .init(collapseAbove: 1))
        try Expect.equal(
            collapsing.render(deepScan, input: deepInput),
            """
            .: 3 entries (1 dirs, 2 files)
            Sources/ (0 dirs, 2 files)
            [Directories with counts are not expanded. Find one by path, or pass expand: true, to list everything.]
            """,
            "A long listing summarizes deeper directories as counts"
        )
        try Expect.equal(
            collapsing.render(deepScan, input: .init(maxdepth: 2, expand: true))?.contains("A.swift"),
            true,
            "expand lists everything"
        )
        try Expect.equal(deepScan.entries.count, 3, "The output keeps every entry")

        let rankedText = SystemIO.Tools.Find().render(
            rankedOutput,
            input: .init()
        ) ?? ""
        try Expect.true(
            rankedText.hasPrefix("\(rankedOutput.entries.count) matches"),
            "find renders matches as ranked lines under a count"
        )
        try Expect.true(!rankedText.contains("{"), "No JSON reaches the model")

        return [
            .message(
                "find lists shallowly by default, searches below with a query or includes, and keeps flatcase maxdepth as bounded depth control"
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