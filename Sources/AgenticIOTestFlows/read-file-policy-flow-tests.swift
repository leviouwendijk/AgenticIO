import Agentic
import AgenticExecution
import AgenticIO
import AgenticWorkspace
import Foundation
import Path
import TestFlows

extension AgenticIOFlowTesting {
    static func runReadFilePolicy() async throws -> [TestFlowDiagnostic] {
        let fixture = try ReadFilePolicyFixture.make()

        defer {
            fixture.remove()
        }

        let tool = ReadFileTool()
        let policy = ToolExecutionPolicy(
            autonomyMode: .auto_observe
        )

        let ordinary = try await tool.preflight(
            input: try JSONToolBridge.encode(
                ReadFileToolInput(
                    path: "Sources/example.swift"
                )
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            ordinary.risk,
            .observe,
            "ordinary read keeps inherent observe risk"
        )
        try Expect.equal(
            policy.evaluate(ordinary),
            .no_approval_needed,
            "ordinary source read remains automatic"
        )
        try Expect.true(
            ordinary.policyDirectives == nil
                || ordinary.policyDirectives?.isEmpty == true,
            "ordinary source read has no escalation directive"
        )

        let sensitive = try await tool.preflight(
            input: try JSONToolBridge.encode(
                ReadFileToolInput(
                    path: "notes/private-notes.txt"
                )
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            sensitive.risk,
            .observe,
            "sensitive read keeps inherent observe risk"
        )
        try Expect.equal(
            policy.evaluate(sensitive),
            .needs_human_review,
            "private path escalates observe read to human review"
        )
        try Expect.true(
            sensitive.policyDirectives?.contains(
                .require_human_review
            ) == true,
            "private path emits review directive"
        )
        try Expect.true(
            sensitive.summary.contains(
                "Path contains private marker."
            ),
            "private path explains the escalation"
        )

        let forbidden = try await tool.preflight(
            input: try JSONToolBridge.encode(
                ReadFileToolInput(
                    path: "notes/do-not-read.txt"
                )
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            forbidden.risk,
            .observe,
            "denied read keeps inherent observe risk"
        )
        try Expect.equal(
            policy.evaluate(forbidden),
            .denied_forbidden,
            "do-not-read path is denied by sensitivity policy"
        )
        try Expect.true(
            forbidden.policyDirectives?.contains(
                .require_deny
            ) == true,
            "do-not-read path emits deny directive"
        )
        try Expect.true(
            forbidden.summary.contains(
                "Path explicitly indicates it should not be read."
            ),
            "denied path explains the denial"
        )

        return [
            .field(
                "ordinary",
                policy.evaluate(ordinary).rawValue
            ),
            .field(
                "sensitive",
                policy.evaluate(sensitive).rawValue
            ),
            .field(
                "forbidden",
                policy.evaluate(forbidden).rawValue
            ),
        ]
    }
}

private struct ReadFilePolicyFixture {
    let root: URL
    let workspace: AgentWorkspace

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-read-policy-\(UUID().uuidString)",
                isDirectory: true
            )
        let sources = root.appendingPathComponent(
            "Sources",
            isDirectory: true
        )
        let notes = root.appendingPathComponent(
            "notes",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: sources,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: notes,
            withIntermediateDirectories: true
        )

        try "let value = 1\n".write(
            to: sources.appendingPathComponent(
                "example.swift"
            ),
            atomically: true,
            encoding: .utf8
        )
        try "private\n".write(
            to: notes.appendingPathComponent(
                "private-notes.txt"
            ),
            atomically: true,
            encoding: .utf8
        )
        try "blocked\n".write(
            to: notes.appendingPathComponent(
                "do-not-read.txt"
            ),
            atomically: true,
            encoding: .utf8
        )

        return .init(
            root: root,
            workspace: try AgentWorkspace(
                root: root,
                accessPolicy: .allowAll
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}
