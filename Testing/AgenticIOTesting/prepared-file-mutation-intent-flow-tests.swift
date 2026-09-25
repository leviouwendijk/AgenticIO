import Agentic
import AgenticExecution
import AgenticIO
import Foundation
import Testing

extension AgenticIOFlowTesting {
    static func runPreparedFileMutationIntentInvocation()
        async throws -> [TestDiagnostic]
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-prepared-intent-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: root
            )
        }

        let fileURL = root.appendingPathComponent(
            "sample.txt"
        )

        try "before\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        let workspace = try makeAgenticIOTestingWorkspace(
            root: root
        )
        let builder = FileMutationIntentBuilder(
            sessionID: "prepared-intent-fixture"
        )
        let writePreflight = try await AgentFileMutationPreflight.write(
            .init(
                path: "sample.txt",
                content: "after\n"
            ),
            workspace: workspace
        )
        let writeDraft = try builder.draft(
            for: writePreflight
        )
        let writeReview = writeDraft.invocation.review
        let writeInput = try JSONToolBridge.decode(
            SystemIO.Tools.MutateFiles.Input.self,
            from: writeReview.call.input
        )

        try Expect.equal(
            writeReview.call.tool.rawValue,
            SystemIO.Tools.MutateFiles.identifier.rawValue,
            "prepared write intent records mutate_files as its canonical reviewed call"
        )
        try Expect.equal(
            writeReview.requirement,
            .needs_human_review,
            "prepared file mutation remains explicitly review-gated"
        )
        try Expect.equal(
            writeInput.entries.count,
            1,
            "prepared write intent retains one mutate_files entry"
        )
        try Expect.equal(
            writeInput.entries[0].kind,
            .replace_text,
            "prepared write intent retains replace_text semantics"
        )
        try Expect.equal(
            writeInput.entries[0].path,
            "sample.txt",
            "prepared write intent retains the reviewed path"
        )
        try Expect.equal(
            writeInput.entries[0].content,
            "after\n",
            "prepared write intent retains the reviewed content"
        )
        try Expect.equal(
            writeDraft.invocation.operation.schema,
            PreparedFileMutationOperation.schema,
            "prepared write intent retains the durable prepared-operation envelope"
        )
        try Expect.contains(
            writeReview.preflight.summary,
            "Stage a file mutation write intent",
            "prepared write review uses the canonical ToolPreflight summary"
        )

        let editPreflight = try await AgentFileMutationPreflight.edit(
            .init(
                path: "sample.txt",
                operations: [
                    .replace_unique(
                        .init(
                            target: "before",
                            replacement: "after"
                        )
                    ),
                ]
            ),
            workspace: workspace
        )
        let editDraft = try builder.draft(
            for: editPreflight
        )
        let editReview = editDraft.invocation.review
        let editInput = try JSONToolBridge.decode(
            SystemIO.Tools.MutateFiles.Input.self,
            from: editReview.call.input
        )

        try Expect.equal(
            editReview.call.tool.rawValue,
            SystemIO.Tools.MutateFiles.identifier.rawValue,
            "prepared edit intent records mutate_files instead of an obsolete edit tool"
        )
        try Expect.equal(
            editInput.entries.count,
            1,
            "prepared edit intent retains one mutate_files entry"
        )
        try Expect.equal(
            editInput.entries[0].kind,
            .edit_text,
            "prepared edit intent retains edit_text semantics"
        )
        try Expect.equal(
            editInput.entries[0].operations?.count,
            1,
            "prepared edit intent retains its structured edit operation"
        )
        try Expect.equal(
            try String(
                contentsOf: fileURL,
                encoding: .utf8
            ),
            "before\n",
            "authoring prepared file mutation intents remains side-effect free"
        )

        return [
            .field(
                "write_tool",
                writeReview.call.tool.rawValue
            ),
            .field(
                "edit_tool",
                editReview.call.tool.rawValue
            ),
            .field(
                "operation",
                writeDraft.invocation.operation.schema.identifier.rawValue
            ),
        ]
    }
}
