import Agentic
import AgenticIO
import Foundation
import Testing

extension AgenticIOFlowTesting {
    static func runMutateFilesMove() async throws -> [TestDiagnostic] {
        let fixture = try CoreFileOperationFixture.make(
            "mutate-files-move"
        )
        defer {
            fixture.remove()
        }

        let source = fixture.url(
            "source.txt"
        )
        let destination = fixture.url(
            "_archive/source.txt"
        )

        try "fixture\n".write(
            to: source,
            atomically: true,
            encoding: .utf8
        )

        let input = try JSONToolBridge.encode(
            SystemIO.Tools.MutateFiles.Input(
                entries: [
                    .init(
                        kind: .move,
                        path: "source.txt",
                        destination: "_archive/source.txt"
                    ),
                ]
            )
        )
        let tool = SystemIO.Tools.MutateFiles()

        _ = try await tool.preflight(
            input: input,
            workspace: fixture.workspace
        )

        let output = try await tool.call(
            input: input,
            workspace: fixture.workspace
        )
        let result = try JSONToolBridge.decode(
            SystemIO.Tools.MutateFiles.Output.self,
            from: output
        )

        try Expect.equal(
            result.status,
            "applied",
            "mutate_files move status"
        )
        try Expect.equal(
            result.entryCount,
            1,
            "mutate_files move entry count"
        )
        try Expect.false(
            FileManager.default.fileExists(
                atPath: source.path
            ),
            "mutate_files move removes source"
        )
        try Expect.true(
            FileManager.default.fileExists(
                atPath: destination.path
            ),
            "mutate_files move creates destination"
        )
        try Expect.equal(
            try String(
                contentsOf: destination,
                encoding: .utf8
            ),
            "fixture\n",
            "mutate_files move preserves content"
        )

        return [
            .field(
                "status",
                result.status
            ),
            .field(
                "entries",
                "\(result.entryCount)"
            ),
        ]
    }

    static func runRemoveEmptyDirectories() async throws -> [TestDiagnostic] {
        let fixture = try CoreFileOperationFixture.make(
            "remove-empty-directories"
        )
        defer {
            fixture.remove()
        }

        let directory = fixture.url(
            "empty",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let input = try JSONToolBridge.encode(
            SystemIO.Tools.RemoveEmptyDirectories.Input(
                paths: [
                    "empty",
                ]
            )
        )
        let tool = SystemIO.Tools.RemoveEmptyDirectories()

        _ = try await tool.preflight(
            input: input,
            workspace: fixture.workspace
        )

        let output = try await tool.call(
            input: input,
            workspace: fixture.workspace
        )
        let result = try JSONToolBridge.decode(
            SystemIO.Tools.RemoveEmptyDirectories.Output.self,
            from: output
        )

        try Expect.equal(
            result.removed,
            [
                "empty",
            ],
            "remove_empty_directories reports removed path"
        )
        try Expect.false(
            FileManager.default.fileExists(
                atPath: directory.path
            ),
            "remove_empty_directories removes empty directory"
        )

        return [
            .field(
                "removed",
                "\(result.removed.count)"
            ),
        ]
    }

    static func runRemoveEmptyDirectoriesRejectsNonEmpty() async throws -> [TestDiagnostic] {
        let fixture = try CoreFileOperationFixture.make(
            "remove-empty-directories-rejects-nonempty"
        )
        defer {
            fixture.remove()
        }

        let directory = fixture.url(
            "nonempty",
            isDirectory: true
        )
        let child = directory.appendingPathComponent(
            "keep.txt"
        )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try "keep\n".write(
            to: child,
            atomically: true,
            encoding: .utf8
        )

        let input = try JSONToolBridge.encode(
            SystemIO.Tools.RemoveEmptyDirectories.Input(
                paths: [
                    "nonempty",
                ]
            )
        )
        let tool = SystemIO.Tools.RemoveEmptyDirectories()

        var preflightRejected = false
        do {
            _ = try await tool.preflight(
                input: input,
                workspace: fixture.workspace
            )
        } catch let error as RemoveEmptyDirectoriesToolError {
            switch error {
            case .notEmpty:
                preflightRejected = true

            default:
                throw error
            }
        }

        try Expect.true(
            preflightRejected,
            "remove_empty_directories preflight rejects non-empty directory"
        )

        var callRejected = false
        do {
            _ = try await tool.call(
                input: input,
                workspace: fixture.workspace
            )
        } catch let error as RemoveEmptyDirectoriesToolError {
            switch error {
            case .notEmpty:
                callRejected = true

            default:
                throw error
            }
        }

        try Expect.true(
            callRejected,
            "remove_empty_directories call rechecks non-empty directory"
        )
        try Expect.true(
            FileManager.default.fileExists(
                atPath: directory.path
            ),
            "non-empty directory remains"
        )
        try Expect.true(
            FileManager.default.fileExists(
                atPath: child.path
            ),
            "non-empty directory contents remain"
        )

        return [
            .field(
                "preflight",
                "rejected"
            ),
            .field(
                "call",
                "rejected"
            ),
        ]
    }
}

private struct CoreFileOperationFixture {
    let root: URL
    let workspace: WorkspaceContext

    static func make(
        _ name: String
    ) throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        return .init(
            root: root,
            workspace: try WorkspaceContext(
                root: root
            )
        )
    }

    func url(
        _ relativePath: String,
        isDirectory: Bool = false
    ) -> URL {
        root.appendingPathComponent(
            relativePath,
            isDirectory: isDirectory
        )
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}