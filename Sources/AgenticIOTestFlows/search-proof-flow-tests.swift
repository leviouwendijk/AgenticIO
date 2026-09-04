import Agentic
import AgenticExecution
import AgenticIO
import AgenticWorkspace
import Foundation
import TestFlows

extension AgenticIOFlowTesting {
    static func runSearchProof() async throws -> [TestFlowDiagnostic] {
        let fixture = try SearchProofFixture.make()

        defer {
            fixture.remove()
        }

        let schema = String(
            describing: ProveSearchResultsToolInput.jsonschema
        )

        for field in [
            "candidates",
            "specification",
            "nodes",
            "root",
            "literal",
            "identifier",
            "capture",
            "cardinality",
        ] {
            try Expect.contains(
                schema,
                field,
                "prove_search_results schema exposes \(field)"
            )
        }

        var registry = ToolRegistry()

        try registry.register(
            CoreFileToolSet()
        )

        _ = try Expect.notNil(
            registry.registeredTool(
                named: "prove_search_results"
            ),
            "AgenticIO registers prove_search_results"
        )

        let searchOutput = try await SearchSourcesTool().call(
            SearchSourcesToolInput(
                                includes: [
                                    "Sources/**",
                                ],
                                probes: [
                                    .init(
                                        text: "user",
                                        id: "user",
                                        role: .preferred,
                                        strategy: .contains
                                    ),
                                ],
                                mode: .exhaustive,
                                caseSensitive: true,
                                mergeDistanceLines: 0,
                                maximumCandidates: 8
                            ),
            context: .init(
                workspace: fixture.workspace
            )
        )
        let search = searchOutput

        try Expect.equal(
            search.candidates.count,
            2,
            "text search leaves two candidate-local regions before structural proof"
        )

        let candidates = search.candidates.map(
            SourceContextCandidateInput.init
        )
        let input = ProveSearchResultsToolInput(
            candidates: candidates,
            specification: .init(
                nodes: [
                    .literal(
                        value: "user="
                    ),
                    .identifier,
                    .capture(
                        name: "name",
                        child: 1
                    ),
                    .sequence(
                        children: [
                            0,
                            2,
                        ]
                    ),
                ],
                root: 3
            ),
            cardinality: .atLeast(
                count: 1
            )
        )
        let tool = ProveSearchResultsTool()
        let output = try await tool.call(
            input,
            context: .init(
                workspace: fixture.workspace
            )
        )
        let proof = output

        try Expect.equal(
            proof.candidateCount,
            2,
            "proof evaluates both source candidates"
        )
        try Expect.equal(
            proof.provenCandidateCount,
            1,
            "structural proof rejects the textual false positive"
        )
        try Expect.equal(
            proof.matchCount,
            1,
            "one structural match remains"
        )
        try Expect.equal(
            proof.proofs.count,
            1,
            "one candidate proof remains"
        )

        let proven = try Expect.notNil(
            proof.proofs.first,
            "structural proof returns the matching candidate"
        )
        let match = try Expect.notNil(
            proven.matches.first,
            "structural proof returns its exact match"
        )
        let capture = try Expect.notNil(
            match.captures.first,
            "structural proof returns the capture"
        )

        try Expect.equal(
            proven.path,
            "Sources/Proof.txt",
            "proof preserves source path"
        )
        try Expect.equal(
            match.range.startLine,
            2,
            "proof rebases candidate-local match to source line"
        )
        try Expect.equal(
            capture.name,
            "name",
            "proof preserves capture name"
        )
        try Expect.equal(
            capture.value,
            "Levi",
            "proof preserves captured value"
        )
        try Expect.equal(
            capture.range.startLine,
            2,
            "capture rebases to source line"
        )

        try fixture.write(
            """
            header
            user=Changed
            gap
            user Changed
            tail
            """
        )

        var staleRejected = false

        do {
            _ = try await tool.call(
                input,
                context: .init(
                    workspace: fixture.workspace
                )
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
            "structural proof rejects stale candidate fingerprints"
        )

        return [
            .field(
                "candidates",
                "\(proof.candidateCount)"
            ),
            .field(
                "proven",
                "\(proof.provenCandidateCount)"
            ),
            .field(
                "matches",
                "\(proof.matchCount)"
            ),
            .field(
                "stale",
                staleRejected ? "rejected" : "accepted"
            ),
        ]
    }
}

private struct SearchProofFixture {
    let root: URL
    let workspace: AgentWorkspace

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-search-proof-\(UUID().uuidString)",
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

        let fixture = Self(
            root: root,
            workspace: try AgentWorkspace(
                root: root
            )
        )

        try fixture.write(
            """
            header
            user=Levi
            gap
            user Levi
            tail
            """
        )

        return fixture
    }

    func write(
        _ content: String
    ) throws {
        try content.write(
            to: root.appendingPathComponent(
                "Sources/Proof.txt"
            ),
            atomically: true,
            encoding: .utf8
        )
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}