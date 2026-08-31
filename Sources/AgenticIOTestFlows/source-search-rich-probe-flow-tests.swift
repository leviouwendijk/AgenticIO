import Agentic
import AgenticIO
import AgenticWorkspace
import Foundation
import Schema
import TestFlows

extension AgenticIOFlowTesting {
    static func proveRichProbeSemantics() async throws {
        let fixture = try RichSourceSearchFixture.make()
        defer {
            fixture.remove()
        }

        let schema = String(
            describing: SearchSourcesToolInput.jsonschema
        )

        try Expect.contains(
            schema,
            "probes",
            "search_sources schema exposes rich probes"
        )
        try Expect.contains(
            schema,
            "required",
            "search_sources schema exposes required probe role"
        )
        try Expect.contains(
            schema,
            "preferred",
            "search_sources schema exposes preferred probe role"
        )
        try Expect.contains(
            schema,
            "excluded",
            "search_sources schema exposes excluded probe role"
        )
        try Expect.contains(
            schema,
            "queries",
            "search_sources schema retains legacy query compatibility"
        )

        let output = try await SearchSourcesTool().call(
            input: try JSONToolBridge.encode(
                SearchSourcesToolInput(
                    includes: [
                        "Sources/RichPlain.swift",
                        "Sources/RichStrong.swift",
                        "Sources/RichEmbedded.swift",
                        "Sources/RichMissing.swift",
                        "Sources/RichDeprecated.swift",
                    ],
                    probes: [
                        .init(
                            text: "ToolPlan",
                            id: "type",
                            role: .required,
                            strategy: .identifier
                        ),
                        .init(
                            text: "resume",
                            id: "operation",
                            role: .required,
                            strategy: .contains
                        ),
                        .init(
                            text: "failure",
                            id: "context",
                            role: .preferred,
                            strategy: .identifier
                        ),
                        .init(
                            text: "Deprecated",
                            id: "deprecated",
                            role: .excluded,
                            strategy: .identifier
                        ),
                    ],
                    mode: .exhaustive,
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
            2,
            "rich source probes require ToolPlan and resume, veto Deprecated, and keep preferred failure optional"
        )
        try Expect.equal(
            result.discoveredCandidateCount,
            2,
            "rich source probes produce one admitted candidate for each surviving document"
        )
        try Expect.equal(
            result.candidates.map(\.path).sorted(),
            [
                "Sources/RichPlain.swift",
                "Sources/RichStrong.swift",
            ],
            "rich source probes exclude embedded identifiers, missing required probes, and excluded documents"
        )

        let plain = try Expect.notNil(
            result.candidates.first {
                $0.path == "Sources/RichPlain.swift"
            },
            "required-only rich source candidate exists"
        )
        let strong = try Expect.notNil(
            result.candidates.first {
                $0.path == "Sources/RichStrong.swift"
            },
            "preferred-enriched rich source candidate exists"
        )

        try Expect.equal(
            plain.probeCount,
            2,
            "preferred probes are not required for document admission"
        )
        try Expect.equal(
            strong.probeCount,
            3,
            "preferred evidence enriches an admitted source candidate"
        )
        try Expect.equal(
            strong.evidence.filter {
                $0.role == "required"
            }.count,
            2,
            "source evidence preserves both required probes"
        )
        try Expect.equal(
            strong.evidence.filter {
                $0.role == "preferred"
            }.count,
            1,
            "source evidence preserves preferred probe provenance"
        )
        try Expect.equal(
            Set(
                strong.evidence.map {
                    "\($0.role):\($0.strategy)"
                }
            ),
            Set([
                "required:identifier",
                "required:contains",
                "preferred:identifier",
            ]),
            "source evidence preserves independently selected role and strategy pairs"
        )
        try Expect.equal(
            strong.evidence.contains {
                $0.role == "excluded"
            },
            false,
            "excluded probes veto documents rather than becoming positive candidate evidence"
        )
    }
}

private struct RichSourceSearchFixture {
    let root: URL
    let workspace: AgentWorkspace

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-rich-source-search-\(UUID().uuidString)",
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

        let fixtures = [
            "RichPlain.swift": "ToolPlan resume\n",
            "RichStrong.swift": "ToolPlan resume failure\n",
            "RichEmbedded.swift": "ToolPlanState resume failure\n",
            "RichMissing.swift": "ToolPlan failure\n",
            "RichDeprecated.swift": "ToolPlan resume failure Deprecated\n",
        ]

        for (name, content) in fixtures {
            try content.write(
                to: sources.appendingPathComponent(
                    name
                ),
                atomically: true,
                encoding: .utf8
            )
        }

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
