import Agentic
import AgenticExecution
import AgenticIO
import AgenticWorkspace
import Foundation
import TestFlows

extension AgenticIOFlowTesting {
    static func runPreparedOperationAuthoring()
        async throws
        -> [TestFlowDiagnostic]
    {
        let fixture = try PreparedOperationAuthoringFixture.make()

        defer {
            fixture.remove()
        }

        let preflight = try await AgentFileMutationPreflight.write(
            .init(
                path: "sample.txt",
                content: "after\n"
            ),
            workspace: fixture.workspace
        )

        try Expect.equal(
            preflight.operation.schema,
            PreparedFileMutationOperation.schema,
            "file mutation preflight authors the versioned prepared-operation schema"
        )
        try Expect.equal(
            try String(
                contentsOf: fixture.fileURL,
                encoding: .utf8
            ),
            "before\n",
            "prepared file mutation authoring remains side-effect free"
        )

        let preparedFilePlan = try PreparedFileMutationOperation.plan(
            from: preflight.operation
        )

        try Expect.equal(
            preparedFilePlan.action,
            .write,
            "prepared file operation retains the semantic mutation action"
        )
        try Expect.equal(
            preparedFilePlan.authorizations.count,
            1,
            "prepared file operation retains Agentic path authorization provenance"
        )

        switch preparedFilePlan.work {
        case .mutation(let writersPlan, let failurePolicy):
            try Expect.equal(
                writersPlan.entries.count,
                1,
                "prepared file operation stores the exact Writers mutation plan"
            )
            try Expect.equal(
                failurePolicy,
                .rollback_applied,
                "prepared file operation stores the approved Writers failure policy"
            )

        case .rollback:
            throw PreparedOperationAuthoringFixtureError.unexpectedWork
        }

        let draft = try FileMutationIntentBuilder(
            sessionID: "fixture-session"
        ).draft(
            for: preflight
        )

        try Expect.equal(
            draft.operation,
            preflight.operation,
            "prepared intent draft uses the typed operation envelope as its execution authority"
        )

        let store = PreparedOperationAuthoringIntentStore()
        let manager = PreparedIntentManager(
            store: store
        )
        let pathGrantOutput = try await RequestPathGrantTool(
            manager: manager
        ).call(
            .init(
                sessionID: "fixture-session",
                requestedRootPath: fixture.rootURL.path,
                suggestedRootID: "fixture_external",
                reason: "Exercise typed path grant prepared-operation authoring.",
                expiresInSeconds: 300
            ),
            context: .init(
                workspace: fixture.workspace
            )
        )
        let pathGrantIntent = try await manager.get(
            pathGrantOutput.intentID
        )
        let pathGrantPlan = try PreparedPathGrantOperation.plan(
            from: pathGrantIntent.operation
        )

        try Expect.equal(
            pathGrantOutput.operationIdentifier,
            PreparedPathGrantOperation.schema.identifier.rawValue,
            "path grant output exposes prepared-operation identity instead of a legacy action type"
        )
        try Expect.equal(
            pathGrantPlan.lifetime,
            .turn,
            "path grant requests default to turn-scoped temporary authority"
        )
        try Expect.equal(
            pathGrantPlan.durationSeconds,
            300,
            "path grant operation retains optional wall-clock duration independently from authority lifetime"
        )
        try Expect.equal(
            pathGrantPlan.overlay.roots.count,
            1,
            "path grant operation captures one exact temporary root overlay"
        )

        guard let grantedRoot = pathGrantPlan.overlay.roots.first else {
            throw PreparedOperationAuthoringFixtureError.missingGrantedRoot
        }

        try Expect.equal(
            grantedRoot.root.id.rawValue,
            "fixture_external",
            "path grant operation retains the exact requested root identifier"
        )
        try Expect.equal(
            grantedRoot.root.rootURL.standardizedFileURL.path,
            fixture.rootURL.standardizedFileURL.path,
            "path grant operation retains the exact normalized requested root"
        )
        try Expect.equal(
            grantedRoot.grant.mode,
            .read_only,
            "path grant operation retains the exact requested grant mode"
        )
        try Expect.equal(
            pathGrantIntent.expiresAt,
            nil,
            "temporary grant lifetime is not conflated with prepared-intent approval expiry"
        )

        return [
            .field(
                "file_operation",
                preflight.operation.schema.identifier.rawValue
            ),
            .field(
                "path_grant_operation",
                pathGrantIntent.operation.schema.identifier.rawValue
            ),
            .field(
                "typed_writers_plan",
                "true"
            ),
            .field(
                "authoring_side_effect_free",
                "true"
            ),
        ]
    }
}

private enum PreparedOperationAuthoringFixtureError: Error {
    case unexpectedWork
    case missingGrantedRoot
}

private actor PreparedOperationAuthoringIntentStore:
    PreparedIntentStore
{
    private var intents:
        [PreparedIntentIdentifier: PreparedIntent] = [:]

    func load(
        id: PreparedIntentIdentifier
    ) async throws -> PreparedIntent? {
        intents[id]
    }

    func list() async throws -> [PreparedIntent] {
        Array(
            intents.values
        )
    }

    func save(
        _ intent: PreparedIntent
    ) async throws {
        intents[intent.id] = intent
    }

    func delete(
        id: PreparedIntentIdentifier
    ) async throws {
        intents.removeValue(
            forKey: id
        )
    }
}

private struct PreparedOperationAuthoringFixture {
    let rootURL: URL
    let workspace: AgentWorkspace

    var fileURL: URL {
        rootURL.appendingPathComponent(
            "sample.txt"
        )
    }

    static func make() throws -> Self {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-io-prepared-operation-authoring-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let fixture = try Self(
            rootURL: rootURL,
            workspace: AgentWorkspace(
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
