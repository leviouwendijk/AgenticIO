import Agentic
import AgenticExecution
import AgenticIO
import AgenticWorkspace
import Foundation
import TestFlows

extension AgenticIOFlowTesting {
    static func runSearchContext() async throws -> [TestFlowDiagnostic] {
        let fixture = try SearchContextFixture.make()

        defer {
            fixture.remove()
        }

        var registry = ToolRegistry()

        try registry.register(
            CoreFileToolSet()
        )

        _ = try Expect.notNil(
            registry.tool(
                named: "load_search_context"
            ),
            "AgenticIO registers load_search_context"
        )

        let schema = String(
            describing: LoadSearchContextToolInput.jsonschema
        )

        for field in [
            "candidates",
            "sourceFingerprint",
            "lineRange",
            "beforeLines",
            "afterLines",
            "maximumCandidates",
            "maximumLinesPerCandidate",
            "maximumTotalLines",
        ] {
            try Expect.contains(
                schema,
                field,
                "load_search_context schema exposes \(field)"
            )
        }

        let searchOutput = try await SearchSourcesTool().call(
            input: try JSONToolBridge.encode(
                SearchSourcesToolInput(
                    includes: [
                        "Sources/**",
                    ],
                    probes: [
                        .init(
                            text: "needle",
                            id: "needle",
                            role: .preferred,
                            strategy: .contains
                        ),
                    ],
                    caseSensitive: true,
                    mergeDistanceLines: 1,
                    maximumCandidates: 8
                )
            ),
            workspace: fixture.workspace
        )
        let search = try JSONToolBridge.decode(
            SourceSearchResult.self,
            from: searchOutput
        )
        let candidate = try Expect.notNil(
            search.candidates.first,
            "source search provides a candidate for context admission"
        )

        try Expect.equal(
            candidate.path,
            "Sources/A.swift",
            "context admission starts from the searched source"
        )
        try Expect.equal(
            candidate.lineRange.start,
            2,
            "searched candidate begins on original source line 2"
        )
        try Expect.equal(
            candidate.lineRange.end,
            4,
            "searched candidate ends on original source line 4"
        )

        let tool = LoadSearchContextTool()
        let input = LoadSearchContextToolInput(
            candidates: [
                .init(
                    candidate
                ),
            ],
            beforeLines: 1,
            afterLines: 1,
            maximumCandidates: 4,
            maximumLinesPerCandidate: 16,
            maximumTotalLines: 32
        )
        let output = try await tool.call(
            input: try JSONToolBridge.encode(
                input
            ),
            workspace: fixture.workspace
        )
        let context = try JSONToolBridge.decode(
            SourceContextResult.self,
            from: output
        )

        try Expect.equal(
            context.candidateCount,
            1,
            "one search candidate is admitted"
        )
        try Expect.equal(
            context.sourceCount,
            1,
            "one source is materialized"
        )
        try Expect.equal(
            context.totalLineCount,
            5,
            "one line of context on each side expands lines 2...4 to the complete five-line fixture"
        )

        let source = try Expect.notNil(
            context.sources.first,
            "context result contains the searched source"
        )
        let slice = try Expect.notNil(
            source.slices.first,
            "context result contains an exact source slice"
        )

        try Expect.equal(
            source.path,
            "Sources/A.swift",
            "context preserves workspace-relative source identity"
        )
        try Expect.equal(
            source.sourceFingerprint,
            candidate.sourceFingerprint,
            "context reports the source fingerprint that was revalidated"
        )
        try Expect.equal(
            slice.lineRange.start,
            1,
            "expanded selected slice starts at source line 1"
        )
        try Expect.equal(
            slice.lineRange.end,
            5,
            "expanded selected slice ends at source line 5"
        )
        try Expect.equal(
            slice.lines.map(\.number),
            [
                1,
                2,
                3,
                4,
                5,
            ],
            "context lines retain original source coordinates"
        )
        try Expect.equal(
            slice.lines.map(\.text),
            [
                "header",
                "needle alpha",
                "middle",
                "needle beta",
                "footer",
            ],
            "SelectionResolver materializes the exact expanded source lines"
        )

        try "header\nchanged alpha\nmiddle\nneedle beta\nfooter\n".write(
            to: fixture.sourceA,
            atomically: true,
            encoding: .utf8
        )

        var staleRejected = false

        do {
            _ = try await tool.call(
                input: try JSONToolBridge.encode(
                    input
                ),
                workspace: fixture.workspace
            )
        } catch let error as SourceContextLoadError {
            switch error {
            case .staleSource:
                staleRejected = true
            default:
                throw error
            }
        }

        try Expect.equal(
            staleRejected,
            true,
            "load_search_context rejects a candidate after its searched source changes"
        )

        return [
            .message(
                "load_search_context reauthorizes searched sources, validates source fingerprints, expands bounded LineRanges, delegates exact materialization to SelectionResolver, and rejects stale candidates"
            ),
        ]
    }
}

private struct SearchContextFixture {
    let root: URL
    let sourceA: URL
    let workspace: AgentWorkspace

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-search-context-\(UUID().uuidString)",
                isDirectory: true
            )
        let sources = root.appendingPathComponent(
            "Sources",
            isDirectory: true
        )
        let sourceA = sources.appendingPathComponent(
            "A.swift"
        )
        let sourceB = sources.appendingPathComponent(
            "B.swift"
        )

        try FileManager.default.createDirectory(
            at: sources,
            withIntermediateDirectories: true
        )
        try "header\nneedle alpha\nmiddle\nneedle beta\nfooter\n".write(
            to: sourceA,
            atomically: true,
            encoding: .utf8
        )
        try "unrelated\nsource\ntext\n".write(
            to: sourceB,
            atomically: true,
            encoding: .utf8
        )

        return .init(
            root: root,
            sourceA: sourceA,
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
