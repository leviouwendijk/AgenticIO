import Agentic
import AgenticExecution
import AgenticIO
import AgenticWorkspace
import Concatenation
import Foundation
import Path
import PathParsing
import Position
import Schema
import Search
import Selection
import TestFlows


enum AgenticIOFlowTesting {
    static func runSourceSearch() async throws -> [TestFlowDiagnostic] {
        let fixture = try SourceSearchFixture.make()
        defer {
            fixture.remove()
        }

        try proveCompleteHitUniverseContract()

        try await proveToolSurface(
            fixture
        )
        try await proveSelectedSliceRebasing(
            fixture
        )
        try await proveSourceFrontierDiversity(
            fixture
        )
        try await proveIdentifierStrategy(
            fixture
        )
        try await proveStatelessContinuation(
            fixture
        )

        return [
            .message(
                "search_sources is schema-derived, workspace-authorized, retained through Concatenation, rebases source coordinates, and bounds repeated candidate regions per source document"
            ),
        ]
    }
}

private extension AgenticIOFlowTesting {
    static func proveCompleteHitUniverseContract() throws {
        let request = SourceSearchRequest(
            definition: ConcatenationCorpusDefinition(
                selections: []
            ),
            queries: [
                SearchQuery(
                    "needle",
                    id: "needle"
                ),
            ],
            options: SearchOptions(
                mode: .ranked,
                strategy: .contains,
                caseSensitive: true,
                minimumScore: 1,
                maximumResults: 0
            )
        )

        try Expect.equal(
            request.options.maximumResults == nil,
            true,
            "SourceSearchRequest preserves the complete admitted Search hit universe before frontier construction"
        )
    }

    static func proveToolSurface(
        _ fixture: SourceSearchFixture
    ) async throws {
        var registry = ToolRegistry()

        try registry.register(
            CoreFileToolSet()
        )

        _ = try Expect.notNil(
            registry.tool(
                named: "search_sources"
            ),
            "AgenticIO registers search_sources"
        )

        let schema = String(
            describing: SearchSourcesToolInput.jsonschema
        )

        try Expect.contains(
            schema,
            "queries",
            "search_sources schema exposes queries"
        )
        try Expect.contains(
            schema,
            "subsequence",
            "search_sources schema derives strategy enum cases"
        )
        try Expect.contains(
            schema,
            "identifier",
            "search_sources schema exposes identifier-boundary matching"
        )
        try Expect.contains(
            schema,
            "maximumCandidatesPerDocument",
            "search_sources schema exposes per-document frontier diversity"
        )
        try Expect.contains(
            schema,
            "mode",
            "search_sources schema exposes search mode"
        )
        try Expect.contains(
            schema,
            "exhaustive",
            "search_sources schema derives exhaustive mode"
        )
        try Expect.equal(
            schema.contains("maximumResults"),
            false,
            "search_sources does not expose a pre-frontier Search hit delivery limit"
        )
        try Expect.contains(
            schema,
            "offset",
            "search_sources schema exposes stateless continuation offset"
        )
        try Expect.contains(
            schema,
            "expectedCorpusFingerprint",
            "search_sources schema exposes continuation freshness guard"
        )

        let tool = SearchSourcesTool()
        let input = SearchSourcesToolInput(
            includes: [
                "Sources/**",
            ],
            queries: [
                .init(
                    text: "needle",
                    id: "needle"
                ),
            ],
            mode: .ranked,
            strategy: .contains,
            caseSensitive: true,
            mergeDistanceLines: 1,
            maximumCandidates: 8
        )

        let output = try await tool.call(
            input: try JSONToolBridge.encode(
                input
            ),
            workspace: fixture.workspace
        )
        let result = try JSONToolBridge.decode(
            SourceSearchResult.self,
            from: output
        )

        try Expect.equal(
            result.mode,
            .ranked,
            "source search defaults to ranked mode"
        )
        try Expect.equal(
            result.sourceCount,
            2,
            "source search retained file count"
        )
        try Expect.equal(
            result.matchedDocumentCount,
            1,
            "source search reports the complete matching document count"
        )
        try Expect.equal(
            result.totalCandidateCount,
            1,
            "source search reports the semantic candidate universe"
        )
        try Expect.equal(
            result.returnedCandidateCount,
            1,
            "source search reports delivered candidate count"
        )
        try Expect.equal(
            result.truncated,
            false,
            "source search reports complete candidate delivery"
        )
        try Expect.equal(
            result.hasMore,
            false,
            "source search reports no hidden candidate page"
        )
        try Expect.equal(
            result.candidates.count,
            1,
            "source search candidate count"
        )

        let candidate = try Expect.notNil(
            result.candidates.first,
            "source search first candidate"
        )

        try Expect.equal(
            candidate.path,
            "Sources/A.swift",
            "source search candidate path"
        )
        try Expect.equal(
            candidate.lineRange.start,
            2,
            "source search merged candidate start line"
        )
        try Expect.equal(
            candidate.lineRange.end,
            4,
            "source search merged candidate end line"
        )
    }

    static func proveSourceFrontierDiversity(
        _ fixture: SourceSearchFixture
    ) async throws {
        let sources = fixture.root.appendingPathComponent(
            "Sources",
            isDirectory: true
        )

        try """
        needle alpha
        gap
        needle beta
        gap
        needle gamma
        """.write(
            to: sources.appendingPathComponent(
                "DiversityA.swift"
            ),
            atomically: true,
            encoding: .utf8
        )

        try """
        needle delta
        """.write(
            to: sources.appendingPathComponent(
                "DiversityB.swift"
            ),
            atomically: true,
            encoding: .utf8
        )

        let output = try await SearchSourcesTool().call(
            input: try JSONToolBridge.encode(
                SearchSourcesToolInput(
                    includes: [
                        "Sources/DiversityA.swift",
                        "Sources/DiversityB.swift",
                    ],
                    queries: [
                        .init(
                            text: "needle",
                            id: "needle"
                        ),
                        .init(
                            text: "alpha",
                            id: "alpha",
                            weight: 4
                        ),
                    ],
                    mode: .ranked,
                    strategy: .contains,
                    caseSensitive: true,
                    mergeDistanceLines: 0,
                    maximumCandidates: 3
                )
            ),
            workspace: fixture.workspace
        )
        let result = try JSONToolBridge.decode(
            SourceSearchResult.self,
            from: output
        )

        try Expect.equal(
            result.candidates.count,
            3,
            "source search fills the bounded diversified frontier"
        )

        let counts = Dictionary(
            grouping: result.candidates,
            by: \.path
        )
        .mapValues(\.count)

        try Expect.equal(
            counts["Sources/DiversityA.swift"] ?? 0,
            2,
            "source search defaults to at most two candidate regions per document"
        )
        try Expect.equal(
            counts["Sources/DiversityB.swift"] ?? 0,
            1,
            "source search admits another matching document after the dominant document reaches its cap"
        )
    }

    static func proveStatelessContinuation(
        _ fixture: SourceSearchFixture
    ) async throws {
        let definition = ConcatenationCorpusDefinition(
            selections: [
                PathSelectionExpression(
                    path: try PathParse.expression(
                        "Sources/A.swift"
                    ),
                    content: .lines(
                        LineRange(
                            uncheckedStart: 1,
                            uncheckedEnd: 5
                        )
                    )
                ),
            ]
        )
        let queries = [
            SearchQuery(
                "needle",
                id: "needle"
            ),
        ]
        let options = SearchOptions(
            mode: .exhaustive,
            strategy: .contains,
            caseSensitive: true,
            minimumScore: 1,
            maximumResults: nil
        )
        let searcher = SourceSearcher()

        let first = try await searcher.search(
            SourceSearchRequest(
                definition: definition,
                queries: queries,
                options: options,
                frontierOptions: SearchFrontierOptions(
                    mergeDistanceLines: 0,
                    maximumCandidates: 1,
                    maximumCandidatesPerDocument: 1,
                    offset: 0
                )
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            first.discoveredCandidateCount,
            2,
            "source continuation discovers both candidate regions"
        )
        try Expect.equal(
            first.totalCandidateCount,
            2,
            "source continuation semantic universe contains both regions"
        )
        try Expect.equal(
            first.offset,
            0,
            "source continuation first page starts at zero"
        )
        try Expect.equal(
            first.returnedCandidateCount,
            1,
            "source continuation first page is bounded"
        )
        try Expect.equal(
            first.nextOffset ?? -1,
            1,
            "source continuation first page exposes next offset"
        )
        try Expect.equal(
            first.hasMore,
            true,
            "source continuation first page reports more results"
        )

        let second = try await searcher.search(
            SourceSearchRequest(
                definition: definition,
                queries: queries,
                options: options,
                frontierOptions: SearchFrontierOptions(
                    mergeDistanceLines: 0,
                    maximumCandidates: 1,
                    maximumCandidatesPerDocument: 1,
                    offset: first.nextOffset ?? -1
                ),
                expectedCorpusFingerprint: first.corpusFingerprint
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            second.corpusFingerprint.description,
            first.corpusFingerprint.description,
            "source continuation keeps the same corpus fingerprint"
        )
        try Expect.equal(
            second.offset,
            1,
            "source continuation second page preserves requested offset"
        )
        try Expect.equal(
            second.returnedCandidateCount,
            1,
            "source continuation second page returns the remaining region"
        )
        try Expect.equal(
            second.hasMore,
            false,
            "source continuation final page reports no later page"
        )
        try Expect.equal(
            second.nextOffset == nil,
            true,
            "source continuation final page has no next offset"
        )
        try Expect.equal(
            second.truncated,
            true,
            "source continuation final page remains a partial response"
        )
        try Expect.equal(
            first.candidates[0].lineRange.start,
            2,
            "source continuation first page returns the first region"
        )
        try Expect.equal(
            second.candidates[0].lineRange.start,
            4,
            "source continuation second page returns the next region"
        )

        let sourceA = fixture.root
            .appendingPathComponent(
                "Sources",
                isDirectory: true
            )
            .appendingPathComponent(
                "A.swift"
            )

        try "changed header\nneedle alpha\nmiddle\nneedle beta\nfooter\n".write(
            to: sourceA,
            atomically: true,
            encoding: .utf8
        )

        var staleRejected = false

        do {
            _ = try await searcher.search(
                SourceSearchRequest(
                    definition: definition,
                    queries: queries,
                    options: options,
                    frontierOptions: SearchFrontierOptions(
                        mergeDistanceLines: 0,
                        maximumCandidates: 1,
                        maximumCandidatesPerDocument: 1,
                        offset: 1
                    ),
                    expectedCorpusFingerprint: first.corpusFingerprint
                ),
                workspace: fixture.workspace
            )
        } catch let error as SourceSearchError {
            switch error {
            case .staleCorpus(let expected, let actual):
                staleRejected =
                    expected.description
                        == first.corpusFingerprint.description
                    && actual.description
                        != expected.description

            default:
                throw error
            }
        }

        try Expect.equal(
            staleRejected,
            true,
            "source continuation rejects a page request after the corpus changes"
        )
    }

    static func proveIdentifierStrategy(
        _ fixture: SourceSearchFixture
    ) async throws {
        let source = fixture.root
            .appendingPathComponent(
                "Sources",
                isDirectory: true
            )
            .appendingPathComponent(
                "Identifier.swift"
            )

        try """
        Foo
        FooBar
        MyFoo
        Foo()
        _Foo
        Foo_
        """.write(
            to: source,
            atomically: true,
            encoding: .utf8
        )

        let output = try await SearchSourcesTool().call(
            input: try JSONToolBridge.encode(
                SearchSourcesToolInput(
                    includes: [
                        "Sources/Identifier.swift",
                    ],
                    queries: [
                        .init(
                            text: "Foo",
                            id: "Foo"
                        ),
                    ],
                    mode: .exhaustive,
                    strategy: .identifier,
                    caseSensitive: true,
                    mergeDistanceLines: 0,
                    maximumCandidates: 16,
                    maximumCandidatesPerDocument: 16
                )
            ),
            workspace: fixture.workspace
        )
        let result = try JSONToolBridge.decode(
            SourceSearchResult.self,
            from: output
        )

        try Expect.equal(
            result.matchedDocumentCount,
            1,
            "identifier source search matches the fixture document"
        )
        try Expect.equal(
            result.discoveredCandidateCount,
            2,
            "identifier source search discovers only bounded Foo occurrences"
        )
        try Expect.equal(
            result.totalCandidateCount,
            2,
            "identifier exhaustive search preserves both bounded occurrences"
        )
        try Expect.equal(
            result.returnedCandidateCount,
            2,
            "identifier source search returns both bounded occurrences"
        )
        try Expect.equal(
            result.candidates.map {
                $0.lineRange.start
            },
            [
                1,
                4,
            ],
            "identifier source search excludes FooBar, MyFoo, _Foo, and Foo_"
        )
        try Expect.equal(
            result.candidates.flatMap(\.evidence).map(\.strategy),
            [
                "identifier",
                "identifier",
            ],
            "identifier source search preserves strategy provenance"
        )
    }

    static func proveSelectedSliceRebasing(
        _ fixture: SourceSearchFixture
    ) async throws {
        let definition = ConcatenationCorpusDefinition(
            selections: [
                PathSelectionExpression(
                    path: try PathParse.expression(
                        "Sources/A.swift"
                    ),
                    content: .lines(
                        LineRange(
                            uncheckedStart: 2,
                            uncheckedEnd: 4
                        )
                    )
                ),
            ]
        )
        let searcher = SourceSearcher()
        let result = try await searcher.search(
            SourceSearchRequest(
                definition: definition,
                queries: [
                    SearchQuery(
                        "beta",
                        id: "beta"
                    ),
                ],
                options: SearchOptions(
                    strategy: .contains,
                    caseSensitive: true,
                    minimumScore: 1,
                    maximumResults: 0
                ),
                frontierOptions: SearchFrontierOptions(
                    mergeDistanceLines: 0,
                    maximumCandidates: 8
                )
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            result.searchedDocumentCount,
            1,
            "selected source becomes one search slice document"
        )

        let candidate = try Expect.notNil(
            result.candidates.first,
            "selected source search candidate"
        )

        try Expect.equal(
            candidate.path,
            "Sources/A.swift",
            "selected source candidate path"
        )
        try Expect.equal(
            candidate.lineRange.start,
            4,
            "selected source candidate rebased start line"
        )
        try Expect.equal(
            candidate.lineRange.end,
            4,
            "selected source candidate rebased end line"
        )
    }
}

private struct SourceSearchFixture {
    let root: URL
    let workspace: AgentWorkspace

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-source-search-\(UUID().uuidString)",
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

        try """
        header
        needle alpha
        middle
        needle beta
        footer
        """.write(
            to: sources.appendingPathComponent(
                "A.swift"
            ),
            atomically: true,
            encoding: .utf8
        )

        try """
        unrelated
        source
        text
        """.write(
            to: sources.appendingPathComponent(
                "B.swift"
            ),
            atomically: true,
            encoding: .utf8
        )

        return Self(
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
