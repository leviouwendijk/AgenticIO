import Agentic
import AgenticIO
import Workspace
import Foundation
import Path
import Testing

extension AgenticIOFlowTesting {
    static func runReadFilePolicy() async throws -> [TestDiagnostic] {
        let fixture = try ReadFilePolicyFixture.make()

        defer {
            fixture.remove()
        }

        let tool = SystemIO.Tools.Read()
        let policy = ToolExecutionPolicy(
            autonomyMode: .auto_observe
        )

        let ordinary = try await tool.preflight(
            SystemIO.Tools.Read.Input(
                                path: "Sources/example.swift"
                            ),
            in: CapabilityContext(workspace: fixture.workspace)
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
        let sensitive = try await tool.preflight(
            SystemIO.Tools.Read.Input(
                                path: "notes/private-notes.txt"
                            ),
            in: CapabilityContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            sensitive.risk,
            .privileged,
            "private path elevates the read to privileged risk"
        )
        try Expect.equal(
            policy.evaluate(sensitive),
            .needs_human_review,
            "private path privileged risk requires human review"
        )
        try Expect.true(
            sensitive.summary.contains(
                "Path contains private marker."
            ),
            "private path explains the escalation"
        )

        let forbidden = try await tool.preflight(
            SystemIO.Tools.Read.Input(
                                path: "notes/do-not-read.txt"
                            ),
            in: CapabilityContext(workspace: fixture.workspace)
        )

        try Expect.equal(
            forbidden.risk,
            .forbidden,
            "do-not-read path elevates the read to forbidden risk"
        )
        try Expect.equal(
            policy.evaluate(forbidden),
            .denied_forbidden,
            "do-not-read path is denied by sensitivity policy"
        )
        try Expect.true(
            forbidden.summary.contains(
                "Path explicitly indicates it should not be read."
            ),
            "denied path explains the denial"
        )

        // The model reads the file text once, under a header.
        let plainInput = SystemIO.Tools.Read.Input(path: "Sources/example.swift")
        let plainOutput = try await tool.call(plainInput, in: CapabilityContext(workspace: fixture.workspace))
        let plain = try Expect.notNil(plainOutput.files.first, "one read, one file")
        let plainText = try Expect.notNil(tool.render(plainOutput, input: plainInput), "read renders")
        try Expect.equal(
            plainText,
            "Sources/example.swift · \(plain.totalLineCount) lines\n" + plain.content,
            "read renders the header and raw text"
        )
        try Expect.true(!plain.lines.isEmpty, "The output still carries structured lines")
        let numberedInput = SystemIO.Tools.Read.Input(
            path: "Sources/example.swift",
            maxLines: 1,
            includeLineNumbers: true
        )
        let numberedOutput = try await tool.call(numberedInput, in: CapabilityContext(workspace: fixture.workspace))
        let numbered = try Expect.notNil(numberedOutput.files.first, "one window, one file")
        let numberedText = try Expect.notNil(tool.render(numberedOutput, input: numberedInput), "read renders a window")
        try Expect.true(
            numberedText.hasSuffix("\n" + (numbered.display ?? "-")),
            "Line numbers are read from the display text"
        )
        try Expect.true(
            numberedText.hasPrefix("Sources/example.swift · lines 1–1 of \(numbered.totalLineCount)"),
            "A window names its range"
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
    let workspace: WorkspaceContext

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