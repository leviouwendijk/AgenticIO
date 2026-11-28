import Agentic
import AgenticIO
import Workspace
import Foundation
import IO
import Writers
import Testing

extension AgenticIOFlowTesting {
    static func runReadSelections() async throws -> [TestDiagnostic] {
        let fixture = try ReadRemoveFixture.make()

        defer {
            fixture.remove()
        }

        let context = CapabilityContext(workspace: fixture.workspace)

        let output = try await SystemIO.Tools.Read().call(
            .init(
                path: "Sources/A.swift",
                selections: [
                    .lines(start: 1, end: 1),
                    .anchor(text: "needle", offset: nil, count: nil),
                ]
            ),
            in: context
        )

        try Expect.equal(
            output.files.map { $0.lines.map(\.number) },
            [
                [1],
                [3],
            ],
            "each selection reads as its own slice with original line numbers"
        )
        try Expect.equal(
            output.files.map(\.content),
            [
                "header",
                "needle",
            ],
            "selected slices carry raw text"
        )
        let whole = try await SystemIO.Tools.Read().call(
            .init(path: "Sources/A.swift"),
            in: context
        )
        try Expect.equal(
            output.files.first?.totalLineCount ?? -1,
            whole.files.first?.totalLineCount ?? -2,
            "a selected slice reports the same total lines as a whole read"
        )

        let mixed = try await SystemIO.Tools.Read().call(
            .init(
                reads: [
                    .init(path: "Sources/A.swift", startLine: 2, endLine: 2),
                    .init(path: "Sources/A.swift", selections: [.point(line: 5, column: 1)]),
                ]
            ),
            in: context
        )

        try Expect.equal(
            mixed.files.map(\.content),
            [
                "middle",
                "footer",
            ],
            "line windows and selections mix across reads"
        )

        var rejected = false
        do {
            _ = try await SystemIO.Tools.Read().call(
                .init(
                    path: "Sources/A.swift",
                    startLine: 1,
                    selections: [.lines(start: 1, end: 2)]
                ),
                in: context
            )
        } catch {
            rejected = true
        }
        try Expect.true(rejected, "selections and a line window in one read are refused")

        let decoded = try JSONDecoder().decode(
            SystemIO.Tools.Read.Input.self,
            from: Data(
                #"{"path":"Sources/A.swift","selections":[{"lines":{"start":2,"end":3}}]}"#.utf8
            )
        )
        try Expect.equal(
            decoded.windows.first?.selections ?? [],
            [.lines(start: 2, end: 3)],
            "read decodes selections"
        )

        return [
            .message(
                "read resolves selections into one slice each, beside line windows"
            ),
        ]
    }

    static func runRemove() async throws -> [TestDiagnostic] {
        let fixture = try ReadRemoveFixture.make()

        defer {
            fixture.remove()
        }

        let context = CapabilityContext(workspace: fixture.workspace)
        let tool = SystemIO.Tools.Remove()

        let emptyPreflight = try await tool.preflight(
            .init(paths: ["Empty"]),
            in: context
        )
        try Expect.equal(emptyPreflight.risk, .boundedmutate, "an empty directory removal is a bounded mutation")

        let empty = try await tool.call(
            .init(paths: ["Empty"]),
            in: context
        )
        try Expect.equal(empty.removed, ["Empty"], "an empty directory is removed")
        try Expect.equal(
            FileSystem.default.exists(fixture.root.appendingPathComponent("Empty")),
            false,
            "the empty directory is gone"
        )

        var notEmpty = false
        do {
            _ = try await tool.call(.init(paths: ["Sources"]), in: context)
        } catch RemoveToolError.notEmpty {
            notEmpty = true
        }
        try Expect.true(notEmpty, "a non-empty directory needs recursive")

        var notDirectory = false
        do {
            _ = try await tool.call(.init(paths: ["Sources/A.swift"]), in: context)
        } catch {
            notDirectory = true
        }
        try Expect.true(notDirectory, "files are left to mutate")

        let recursivePreflight = try await tool.preflight(
            .init(paths: ["Sources"], recursive: true),
            in: context
        )
        try Expect.equal(recursivePreflight.risk, .privileged, "recursive removal asks first")

        let recursive = try await tool.call(
            .init(paths: ["Sources"], recursive: true),
            in: context
        )
        try Expect.equal(recursive.removed, ["Sources"], "a directory is removed with its contents")
        try Expect.equal(
            FileSystem.default.exists(fixture.root.appendingPathComponent("Sources")),
            false,
            "the tree is gone"
        )

        return [
            .message(
                "remove takes empty directories by default, trees with recursive, and leaves files to mutate"
            ),
        ]
    }
}

private struct ReadRemoveFixture {
    let root: URL
    let workspace: WorkspaceContext

    static func make() throws -> Self {
        let root = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent(
            "agentic-io-read-remove-\(UUID().uuidString)",
            isDirectory: true
        )

        try FileSystem.default.directory.create(
            root.appendingPathComponent("Sources", isDirectory: true)
        )
        try FileSystem.default.directory.create(
            root.appendingPathComponent("Empty", isDirectory: true)
        )
        try FileWriter(
            root.appendingPathComponent("Sources/A.swift")
        ).write(
            "header\nmiddle\nneedle\nmore\nfooter\n",
            options: .overwriteWithoutBackup
        )

        return .init(
            root: root,
            workspace: try makeAgenticIOTestingWorkspace(
                root: root
            )
        )
    }

    func remove() {
        try? FileSystem.default.remove(
            root
        )
    }
}
