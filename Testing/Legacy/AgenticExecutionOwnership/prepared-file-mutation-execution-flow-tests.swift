import Agentic
import AgenticExecution
import AgenticIO
import Workspace
import Foundation
import Testing

extension AgenticIOFlowTesting {
    static func runPreparedFileMutationExecution()
        async throws
        -> [TestDiagnostic]
    {
        let fixture = try PreparedFileMutationExecutionFixture.make()

        defer {
            fixture.remove()
        }

        let sessionID = "fixture-session"
        let store = FileAgentFileMutationStore(
            sessionID: sessionID,
            mutationdir: fixture.mutationDirectoryURL
        )
        let recorder = AgentFileMutationRecorder(
            sessionID: sessionID,
            store: store,
            backups: store.backupStore(),
            policy: .normal
        )
        let preflight = try await AgentFileMutationPreflight.write(
            .init(
                path: "sample.txt",
                content: "after\n"
            ),
            workspace: fixture.workspace,
            recorder: recorder
        )
        let authoredPlan = try PreparedFileMutationOperation.plan(
            from: preflight.operation
        )
        let authoredMutationPlanID: UUID

        switch authoredPlan.work {
        case .mutation(let writersPlan, _):
            authoredMutationPlanID = writersPlan.id

        case .rollback:
            throw PreparedFileMutationExecutionFixtureError
                .unexpectedWork
        }

        var registry = PreparedOperationRegistry()

        try AgenticIOPreparedOperationSet(
            fileMutationRecorder: recorder
        ).register(
            into: &registry
        )

        try Expect.equal(
            registry.contains(
                PreparedFileMutationOperation.schema
            ),
            true,
            "AgenticIO installs its executable file mutation prepared operation"
        )

        let writeIntentID = PreparedIntentIdentifier(
            "fixture-write-intent"
        )
        let resultEnvelope = try await registry.execute(
            preflight.operation,
            context: .init(
                workspace: fixture.workspace,
                sessionID: sessionID,
                preparedIntentID: writeIntentID,
                metadata: [
                    "flow": "prepared-file-mutation-execution",
                ]
            )
        )
        let result = try PreparedFileMutationExecutor.result(
            from: resultEnvelope
        )

        try Expect.equal(
            try String(
                contentsOf: fixture.fileURL,
                encoding: .utf8
            ),
            "after\n",
            "prepared execution applies the stored Writers mutation plan"
        )

        let executedWriterRecordID: UUID

        switch result.writers {
        case .mutation(let writersResult):
            try Expect.equal(
                writersResult.plan.id,
                authoredMutationPlanID,
                "prepared execution returns the same Writers plan identity that was authored before approval"
            )
            try Expect.equal(
                writersResult.records.count,
                1,
                "prepared execution produces one canonical Writers mutation record"
            )

            guard let writerRecord = writersResult.records.first else {
                throw PreparedFileMutationExecutionFixtureError
                    .missingWriterRecord
            }

            try Expect.equal(
                writerRecord.backupRecord != nil,
                true,
                "prepared execution realizes the durable external-store backup policy through the live write execution context"
            )

            executedWriterRecordID = writerRecord.id

        case .rollback:
            throw PreparedFileMutationExecutionFixtureError
                .unexpectedWork
        }

        guard let recordedMutation = result.recordedMutations.first else {
            throw PreparedFileMutationExecutionFixtureError
                .missingRecordedMutation
        }

        try Expect.equal(
            result.recordedMutations.count,
            1,
            "prepared execution uses the existing Agentic mutation recorder"
        )
        try Expect.equal(
            recordedMutation.writerRecordID,
            executedWriterRecordID,
            "Agentic mutation storage records the Writers record produced by exact-plan execution"
        )
        try Expect.equal(
            recordedMutation.preparedIntentID?.rawValue ?? "",
            writeIntentID.rawValue,
            "prepared mutation recording preserves prepared-intent provenance"
        )
        try Expect.equal(
            recordedMutation.rollbackable,
            true,
            "prepared exact-plan mutation remains rollbackable under the authored session backup policy"
        )

        let persistedWrite = try await store.list(
            .init(
                preparedIntentID: writeIntentID
            )
        )

        try Expect.equal(
            persistedWrite.count,
            1,
            "prepared file mutation execution persists exactly one mutation under its prepared intent"
        )

        let rollbackPreflight = try await AgentFileMutationPreflight.rollback(
            .init(
                mutationID: recordedMutation.id
                    .uuidString
                    .lowercased()
            ),
            store: store,
            workspace: fixture.workspace,
            recorder: recorder
        )
        let authoredRollback = try PreparedFileMutationOperation.plan(
            from: rollbackPreflight.operation
        )
        let authoredRollbackContent: String
        let authoredRollbackStrategy: String

        switch authoredRollback.work {
        case .mutation:
            throw PreparedFileMutationExecutionFixtureError
                .unexpectedWork

        case .rollback(let rollbackPlan, let sourceMutationID):
            try Expect.equal(
                sourceMutationID,
                recordedMutation.id,
                "prepared rollback stores the source mutation identity"
            )
            authoredRollbackContent =
                rollbackPlan.preview.rollbackContent
            authoredRollbackStrategy =
                rollbackPlan.preview.strategy.rawValue
        }

        let rollbackIntentID = PreparedIntentIdentifier(
            "fixture-rollback-intent"
        )
        let rollbackEnvelope = try await registry.execute(
            rollbackPreflight.operation,
            context: .init(
                workspace: fixture.workspace,
                sessionID: sessionID,
                preparedIntentID: rollbackIntentID
            )
        )
        let rollbackResult = try PreparedFileMutationExecutor.result(
            from: rollbackEnvelope
        )

        try Expect.equal(
            try String(
                contentsOf: fixture.fileURL,
                encoding: .utf8
            ),
            "before\n",
            "prepared rollback applies the stored Writers rollback plan"
        )

        switch rollbackResult.writers {
        case .mutation:
            throw PreparedFileMutationExecutionFixtureError
                .unexpectedWork

        case .rollback(let sourceMutationID, let writersResult):
            try Expect.equal(
                sourceMutationID,
                recordedMutation.id,
                "prepared rollback result preserves source mutation provenance"
            )
            try Expect.equal(
                writersResult.preview.rollbackContent,
                authoredRollbackContent,
                "prepared rollback executes the exact authored rollback content"
            )
            try Expect.equal(
                writersResult.preview.strategy.rawValue,
                authoredRollbackStrategy,
                "prepared rollback executes the exact authored rollback strategy"
            )
        }

        guard let recordedRollback =
            rollbackResult.recordedMutations.first
        else {
            throw PreparedFileMutationExecutionFixtureError
                .missingRecordedMutation
        }

        try Expect.equal(
            rollbackResult.recordedMutations.count,
            1,
            "prepared rollback records its resulting mutation through the existing recorder"
        )
        try Expect.equal(
            recordedRollback.preparedIntentID?.rawValue ?? "",
            rollbackIntentID.rawValue,
            "prepared rollback recording links to the rollback prepared intent"
        )
        try Expect.equal(
            recordedRollback.metadata[
                "rollback_source_mutation_id"
            ] ?? "",
            recordedMutation.id
                .uuidString
                .lowercased(),
            "prepared rollback recording preserves the source Agentic mutation identity"
        )

        return [
            .field(
                "registered_schema",
                PreparedFileMutationOperation
                    .schema
                    .identifier
                    .rawValue
            ),
            .field(
                "exact_writers_plan",
                "true"
            ),
            .field(
                "recorded_mutation",
                "true"
            ),
            .field(
                "prepared_rollback",
                "true"
            ),
        ]
    }
}

private enum PreparedFileMutationExecutionFixtureError: Error {
    case unexpectedWork
    case missingWriterRecord
    case missingRecordedMutation
}

private struct PreparedFileMutationExecutionFixture {
    let rootURL: URL
    let workspace: WorkspaceContext

    var fileURL: URL {
        rootURL.appendingPathComponent(
            "sample.txt"
        )
    }

    var mutationDirectoryURL: URL {
        rootURL.appendingPathComponent(
            "mutation-store",
            isDirectory: true
        )
    }

    static func make() throws -> Self {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-prepared-file-mutation-execution-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let fixture = try Self(
            rootURL: rootURL,
            workspace: WorkspaceContext(
                root: rootURL
            )
        )

        try "before\n".write(
            to: fixture.fileURL,
            atomically: true,
            encoding: .utf8
        )

        return fixture
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: rootURL
        )
    }
}
