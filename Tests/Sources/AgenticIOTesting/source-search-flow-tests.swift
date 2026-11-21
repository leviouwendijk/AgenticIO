import Agentic
import AgenticIO
import Workspace
import Concatenation
import Foundation
import Path
import PathParsing
import Position
import Schema
import Search
import Selection
import Testing


enum AgenticIOFlowTesting {
    static func runSourceSearch() async throws -> [TestDiagnostic] {
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
        try await proveLexicalSearch(
            fixture
        )
        try await proveRichProbeSemantics()
        try await proveStatelessContinuation(
            fixture
        )
        try await proveCandidateRefinement(
            fixture
        )
        try await proveCandidateRefinementBudgets(
            fixture
        )

        return [
            .message(
                "search is schema-derived, workspace-authorized, retained through Concatenation, rebases source coordinates, and bounds repeated candidate regions per source document"
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

        try registry.register(SystemIO.Tools.Search())

        _ = try Expect.notNil(
            registry.registeredTool(
                named: "io_tool_search"
            ),
            "AgenticIO registers search"
        )

        let schema = String(
            describing: SystemIO.Tools.Search.Input.jsonschema
        )

        try Expect.contains(
            schema,
            "probes",
            "search schema exposes canonical probes"
        )
        try Expect.contains(
            schema,
            "subsequence",
            "search schema derives strategy enum cases"
        )
        try Expect.contains(
            schema,
            "identifier",
            "search schema exposes identifier-boundary matching"
        )
        try Expect.contains(
            schema,
            "maximumCandidatesPerDocument",
            "search schema exposes per-document frontier diversity"
        )
        try Expect.contains(
            schema,
            "mode",
            "search schema exposes search mode"
        )
        try Expect.contains(
            schema,
            "exhaustive",
            "search schema derives exhaustive mode"
        )
        try Expect.equal(
            schema.contains("maximumResults"),
            false,
            "search does not expose a pre-frontier Search hit delivery limit"
        )
        try Expect.contains(
            schema,
            "offset",
            "search schema exposes stateless continuation offset"
        )
        try Expect.contains(
            schema,
            "expectedCorpusFingerprint",
            "search schema exposes continuation freshness guard"
        )
        try Expect.contains(
            schema,
            "within",
            "search schema exposes explicit candidate-local refinement"
        )
        try Expect.contains(
            schema,
            "lexicalPattern",
            "search schema exposes bounded lexical search"
        )
        try Expect.contains(
            schema,
            "capture",
            "search schema exposes lexical capture nodes"
        )
        try Expect.contains(
            schema,
            "gap",
            "search schema exposes bounded lexical gaps"
        )
        try Expect.contains(
            schema,
            "token",
            "search schema exposes exact token nodes"
        )

        let tool = SystemIO.Tools.Search()
        let input = SystemIO.Tools.Search.Input(
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
            mode: .ranked,
            caseSensitive: true,
            mergeDistanceLines: 1,
            maximumCandidates: 8
        )

        let output = try await tool.call(
            input,
            in: ToolContext(workspace: fixture.workspace)
        )
        let result = output

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

        let rendered = try Expect.notNil(tool.render(output, input: input), "search renders")
        let fileLines = rendered.split(separator: "\n").filter { $0.hasPrefix("Sources/A.swift") }
        try Expect.equal(fileLines.count, 1, "Each file is named once")
        try Expect.true(
            rendered.contains("\n2:needle alpha\n4:needle beta"),
            "Hits show their matching lines, as rg prints them"
        )
        try Expect.true(
            !rendered.contains(candidate.sourceFingerprint.description)
                && !rendered.contains(output.corpusFingerprint.description),
            "Fingerprints appear only when a result pages"
        )
        try Expect.true(!rendered.contains("{"), "No JSON reaches the model when nothing pages")

        // The short form: literal text, a pattern, context lines.
        let context = ToolContext(workspace: fixture.workspace)
        let literal = try await tool.call(
            .init(includes: ["Sources/**"], query: "NEEDLE beta", contextLines: 1),
            in: context
        )
        let literalText = try Expect.notNil(
            tool.render(literal, input: .init(query: "NEEDLE beta")),
            "short form renders"
        )
        try Expect.true(
            literalText.contains("3-middle\n4:needle beta\n5-footer"),
            "query matches literal text, case-insensitively, with context lines"
        )
        let pattern = try await tool.call(
            .init(includes: ["Sources/**"], pattern: "^needle (alpha|beta)$"),
            in: context
        )
        try Expect.equal(
            pattern.candidates.flatMap { $0.lines ?? [] }.filter(\.isMatch).map(\.number),
            [2, 4],
            "pattern matches a regular expression per line"
        )
        let exact = try await tool.call(
            .init(includes: ["Sources/**"], probes: [.init(text: "NEEDLE", strategy: .exact)]),
            in: context
        )
        try Expect.equal(exact.candidates.count, 0, "exact is literal and case-sensitive")
        let exactHit = try await tool.call(
            .init(includes: ["Sources/**"], probes: [.init(text: "alpha", strategy: .exact)]),
            in: context
        )
        try Expect.equal(
            exactHit.candidates.first?.evidence.first?.queryID,
            "alpha",
            "exact matches inside a line and keeps the asked text"
        )
        do {
            _ = try await tool.call(.init(pattern: "needle("), in: context)
            try Expect.true(false, "an invalid pattern is refused")
        } catch {
            try Expect.true(
                "\(error)".contains("regular expression"),
                "an invalid pattern is refused with a reason"
            )
        }

        // read: several windows in one call, each under its own header.
        let files = SystemIO.Tools.Read()
        let reads = SystemIO.Tools.Read.Input(reads: [
            .init(path: "Sources/A.swift", startLine: 2, endLine: 3),
            .init(path: "Sources/B.swift"),
        ])
        let preflight = try await files.preflight(reads, in: context)
        try Expect.equal(preflight.risk, .observe, "several ordinary reads stay observe")
        try Expect.equal(preflight.access.targets, ["Sources/A.swift", "Sources/B.swift"], "every file is a target")
        let read = try await files.call(reads, in: context)
        try Expect.equal(
            read.files.map(\.content),
            ["needle alpha\nmiddle", "unrelated\nsource\ntext"],
            "read returns each window"
        )
        let readText = try Expect.notNil(files.render(read, input: reads), "read renders")
        try Expect.true(
            readText.contains("Sources/A.swift · lines 2–3 of 5\nneedle alpha")
                && readText.contains("\n\nSources/B.swift · 3 lines\nunrelated"),
            "each window under its own header"
        )
        do {
            _ = try JSONDecoder().decode(
                SystemIO.Tools.Read.Input.self,
                from: Data(#"{"path": "Sources/A.swift", "reads": [{"path": "Sources/B.swift"}]}"#.utf8)
            )
            try Expect.true(false, "path and reads together are refused")
        } catch is DecodingError {
        }
    }

    static func proveLexicalSearch(
        _ fixture: SourceSearchFixture
    ) async throws {
        let source = fixture.root.appendingPathComponent(
            "Sources/Lexical.swift"
        )

        try """
        target client.fetch(value)
        target client.fetch(other)
        noise client.fetch(value)
        lhs -> rhs
        """.write(
            to: source,
            atomically: true,
            encoding: .utf8
        )

        let tool = SystemIO.Tools.Search()
        let pattern = LexicalPatternInput(
            nodes: [
                .identifier(
                    value: "client"
                ),
                .symbol(
                    value: "."
                ),
                .identifier(
                    value: "fetch"
                ),
                .capture(
                    name: "member",
                    child: 2
                ),
                .symbol(
                    value: "("
                ),
                .gap(
                    minimum: 1,
                    maximum: 1
                ),
                .symbol(
                    value: ")"
                ),
                .sequence(
                    children: [
                        0,
                        1,
                        3,
                        4,
                        5,
                        6,
                    ]
                ),
            ],
            root: 7
        )
        let lexical = try await tool.call(
            SystemIO.Tools.Search.Input(
                includes: [
                    "Sources/Lexical.swift",
                ],
                lexicalPattern: pattern,
                mode: .exhaustive,
                caseSensitive: true,
                maximumCandidates: 8
            ),
            in: ToolContext(
                workspace: fixture.workspace
            )
        )

        try Expect.equal(
            lexical.kind,
            .lexical,
            "source search reports lexical query semantics explicitly"
        )
        try Expect.equal(
            lexical.candidates.count,
            3,
            "lexical source search finds every matching token sequence"
        )
        try Expect.equal(
            lexical.candidates.map(\.lineRange.start),
            [
                1,
                2,
                3,
            ],
            "lexical source search preserves source line coordinates"
        )
        try Expect.equal(
            lexical.candidates.flatMap(\.captures).map(\.name),
            [
                "member",
                "member",
                "member",
            ],
            "lexical captures survive the AgenticIO result boundary"
        )
        try Expect.equal(
            lexical.candidates.flatMap(\.captures).flatMap(\.tokens),
            [
                "fetch",
                "fetch",
                "fetch",
            ],
            "lexical capture token spellings remain compact and inspectable"
        )

        let tokenPattern = LexicalPatternInput(
            nodes: [
                .token(
                    value: "->"
                ),
            ],
            root: 0
        )
        let exactToken = try await tool.call(
            SystemIO.Tools.Search.Input(
                includes: [
                    "Sources/Lexical.swift",
                ],
                lexicalPattern: tokenPattern,
                mode: .exhaustive,
                caseSensitive: true,
                maximumCandidates: 8
            ),
            in: ToolContext(
                workspace: fixture.workspace
            )
        )

        try Expect.equal(
            exactToken.candidates.map(\.lineRange.start),
            [
                4,
            ],
            "model-facing exact-token patterns lower through Parsing tokenization"
        )

        let broad = try await tool.call(
            SystemIO.Tools.Search.Input(
                includes: [
                    "Sources/Lexical.swift",
                ],
                probes: [
                    .init(
                        text: "target",
                        role: .required,
                        strategy: .contains
                    ),
                ],
                mode: .exhaustive,
                caseSensitive: true,
                mergeDistanceLines: 0,
                maximumCandidates: 8
            ),
            in: ToolContext(
                workspace: fixture.workspace
            )
        )
        let targetRegion = try Expect.notNil(
            broad.candidates.first,
            "text search produces the lexical refinement region"
        )
        let refined = try await tool.call(
            SystemIO.Tools.Search.Input(
                includes: [
                    "Sources/Lexical.swift",
                ],
                within: [
                    .init(
                        targetRegion
                    ),
                ],
                lexicalPattern: pattern,
                mode: .exhaustive,
                caseSensitive: true,
                maximumCandidates: 8
            ),
            in: ToolContext(
                workspace: fixture.workspace
            )
        )

        try Expect.equal(
            refined.candidates.map(\.lineRange.start),
            [
                1,
                2,
            ],
            "lexical refinement searches only the supplied freshness-validated region"
        )
        try Expect.equal(
            refined.searchedDocumentCount,
            1,
            "candidate-local lexical refinement searches only the supplied region document"
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

        let output = try await SystemIO.Tools.Search().call(
            SystemIO.Tools.Search.Input(
                                includes: [
                                    "Sources/DiversityA.swift",
                                    "Sources/DiversityB.swift",
                                ],
                                probes: [
                                    .init(
                                        text: "needle",
                                        id: "needle",
                                        role: .preferred,
                                        strategy: .contains
                                    ),
                                    .init(
                                        text: "alpha",
                                        id: "alpha",
                                        weight: 4,
                                        role: .preferred,
                                        strategy: .contains
                                    ),
                                ],
                                mode: .ranked,
                                caseSensitive: true,
                                mergeDistanceLines: 0,
                                maximumCandidates: 3
                            ),
            in: ToolContext(workspace: fixture.workspace)
        )
        let result = output

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

        let output = try await SystemIO.Tools.Search().call(
            SystemIO.Tools.Search.Input(
                                includes: [
                                    "Sources/Identifier.swift",
                                ],
                                probes: [
                                    .init(
                                        text: "Foo",
                                        id: "Foo",
                                        role: .preferred,
                                        strategy: .identifier
                                    ),
                                ],
                                mode: .exhaustive,
                                caseSensitive: true,
                                mergeDistanceLines: 0,
                                maximumCandidates: 16,
                                maximumCandidatesPerDocument: 16
                            ),
            in: ToolContext(workspace: fixture.workspace)
        )
        let result = output

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
    let workspace: WorkspaceContext

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

private extension AgenticIOFlowTesting {
    static func proveCandidateRefinement(
        _ fixture: SourceSearchFixture
    ) async throws {
        let tool = SystemIO.Tools.Search()
        let broad = try await tool.call(
            SystemIO.Tools.Search.Input(
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
                mode: .exhaustive,
                caseSensitive: true,
                mergeDistanceLines: 0,
                maximumCandidates: 8
            ),
            in: ToolContext(workspace: fixture.workspace)
        )
        let candidate = try Expect.notNil(
            broad.candidates.first {
                $0.path == "Sources/A.swift"
                    && $0.lineRange.start == 2
                    && $0.lineRange.end == 2
            },
            "broad source search returns the first exact candidate region"
        )

        let refined = try await tool.call(
            SystemIO.Tools.Search.Input(
                includes: [
                    "Sources/**",
                ],
                within: [
                    .init(candidate),
                ],
                probes: [
                    .init(
                        text: "alpha",
                        id: "alpha",
                        role: .required,
                        strategy: .contains
                    ),
                ],
                mode: .exhaustive,
                caseSensitive: true,
                mergeDistanceLines: 0,
                maximumCandidates: 8
            ),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            refined.searchedDocumentCount,
            1,
            "candidate refinement searches only the supplied candidate region"
        )
        try Expect.equal(
            refined.candidates.count,
            1,
            "candidate refinement retains the matching region"
        )

        let refinedCandidate = try Expect.notNil(
            refined.candidates.first,
            "candidate refinement returns one candidate"
        )

        try Expect.equal(
            refinedCandidate.lineRange.start,
            2,
            "candidate refinement preserves original source coordinates"
        )
        try Expect.equal(
            refinedCandidate.lineRange.end,
            2,
            "candidate refinement preserves the exact original source range"
        )

        let outside = try await tool.call(
            SystemIO.Tools.Search.Input(
                includes: [
                    "Sources/**",
                ],
                within: [
                    .init(candidate),
                ],
                probes: [
                    .init(
                        text: "footer",
                        id: "footer",
                        role: .required,
                        strategy: .contains
                    ),
                ],
                mode: .exhaustive,
                caseSensitive: true,
                mergeDistanceLines: 0,
                maximumCandidates: 8
            ),
            in: ToolContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            outside.candidates.count,
            0,
            "candidate refinement cannot escape the supplied source range"
        )

        try """
        header
        needle changed
        middle
        needle beta
        footer
        """.write(
            to: fixture.root
                .appendingPathComponent(
                    "Sources/A.swift"
                ),
            atomically: true,
            encoding: .utf8
        )

        var staleRejected = false

        do {
            _ = try await tool.call(
                SystemIO.Tools.Search.Input(
                    includes: [
                        "Sources/**",
                    ],
                    within: [
                        .init(candidate),
                    ],
                    probes: [
                        .init(
                            text: "alpha",
                            id: "alpha",
                            role: .required,
                            strategy: .contains
                        ),
                    ],
                    mode: .exhaustive,
                    caseSensitive: true,
                    mergeDistanceLines: 0,
                    maximumCandidates: 8
                ),
                in: ToolContext(workspace: fixture.workspace)
            )
        } catch let error as SourceContextLoadError {
            switch error {
            case .staleSource:
                staleRejected = true

            default:
                throw error
            }
        }

        try Expect.true(
            staleRejected,
            "candidate refinement rejects stale source fingerprints"
        )
    }
}

private extension AgenticIOFlowTesting {
    static func proveCandidateRefinementBudgets(
        _ fixture: SourceSearchFixture
    ) async throws {
        let tool = SystemIO.Tools.Search()
        let broad = try await tool.call(
            SystemIO.Tools.Search.Input(
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
                mode: .exhaustive,
                caseSensitive: true,
                mergeDistanceLines: 0,
                maximumCandidates: 8
            ),
            in: ToolContext(
                workspace: fixture.workspace
            )
        )
        let candidate = try Expect.notNil(
            broad.candidates.first {
                $0.path == "Sources/A.swift"
            },
            "refinement budget fixture yields a candidate"
        )

        var tooManyRejected = false

        do {
            _ = try await tool.call(
                SystemIO.Tools.Search.Input(
                    includes: [
                        "Sources/**",
                    ],
                    within: Array(
                        repeating: .init(candidate),
                        count: 9
                    ),
                    probes: [
                        .init(
                            text: "needle",
                            id: "needle",
                            role: .required,
                            strategy: .contains
                        ),
                    ],
                    mode: .exhaustive,
                    caseSensitive: true,
                    mergeDistanceLines: 0,
                    maximumCandidates: 8
                ),
                in: ToolContext(
                    workspace: fixture.workspace
                )
            )
        } catch let error as SourceContextLoadError {
            switch error {
            case .tooManyCandidates:
                tooManyRejected = true

            default:
                throw error
            }
        }

        try Expect.true(
            tooManyRejected,
            "candidate refinement retains the SourceContextLoader candidate-count bound"
        )

        let oversized = SourceContextCandidateInput(
            path: candidate.path,
            sectionKey: candidate.sectionKey,
            sourceFingerprint: .init(
                candidate.sourceFingerprint
            ),
            lineRange: .init(
                start: 1,
                end: 121
            )
        )
        var oversizedRejected = false

        do {
            _ = try await tool.call(
                SystemIO.Tools.Search.Input(
                    includes: [
                        "Sources/**",
                    ],
                    within: [
                        oversized,
                    ],
                    probes: [
                        .init(
                            text: "needle",
                            id: "needle",
                            role: .required,
                            strategy: .contains
                        ),
                    ],
                    mode: .exhaustive,
                    caseSensitive: true,
                    mergeDistanceLines: 0,
                    maximumCandidates: 8
                ),
                in: ToolContext(
                    workspace: fixture.workspace
                )
            )
        } catch let error as SourceContextLoadError {
            switch error {
            case .candidateRangeTooLarge:
                oversizedRejected = true

            default:
                throw error
            }
        }

        try Expect.true(
            oversizedRejected,
            "candidate refinement retains the 120-line per-candidate bound"
        )

        let hundredLines = SourceContextCandidateInput(
            path: candidate.path,
            sectionKey: candidate.sectionKey,
            sourceFingerprint: .init(
                candidate.sourceFingerprint
            ),
            lineRange: .init(
                start: 1,
                end: 100
            )
        )
        var totalBudgetRejected = false

        do {
            _ = try await tool.call(
                SystemIO.Tools.Search.Input(
                    includes: [
                        "Sources/**",
                    ],
                    within: Array(
                        repeating: hundredLines,
                        count: 4
                    ),
                    probes: [
                        .init(
                            text: "needle",
                            id: "needle",
                            role: .required,
                            strategy: .contains
                        ),
                    ],
                    mode: .exhaustive,
                    caseSensitive: true,
                    mergeDistanceLines: 0,
                    maximumCandidates: 8
                ),
                in: ToolContext(
                    workspace: fixture.workspace
                )
            )
        } catch let error as SourceContextLoadError {
            switch error {
            case .totalLineBudgetExceeded:
                totalBudgetRejected = true

            default:
                throw error
            }
        }

        try Expect.true(
            totalBudgetRejected,
            "candidate refinement retains the 320-line aggregate bound"
        )
    }
}
