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

        let workspaceRequest = try await RequestPathGrantTool().call(
            .init(
                requestedRootPath: fixture.rootURL.path,
                suggestedRootID: "fixture_external",
                reason: "Exercise native workspace access request authoring.",
                expiresInSeconds: 300
            ),
            context: .init(
                workspace: fixture.workspace
            )
        )

        try Expect.equal(
            workspaceRequest.durationSeconds,
            300,
            "workspace access request retains optional wall-clock duration independently from human-selected authority lifetime"
        )
        try Expect.equal(
            workspaceRequest.overlay.roots.count,
            1,
            "workspace access request captures one exact temporary root overlay"
        )

        guard let grantedRoot = workspaceRequest.overlay.roots.first else {
            throw PreparedOperationAuthoringFixtureError.missingGrantedRoot
        }

        try Expect.equal(
            grantedRoot.root.id.rawValue,
            "fixture_external",
            "workspace access request retains the exact requested root identifier"
        )
        try Expect.equal(
            grantedRoot.root.rootURL.standardizedFileURL.path,
            fixture.rootURL.standardizedFileURL.path,
            "workspace access request retains the exact normalized requested root"
        )
        try Expect.equal(
            grantedRoot.grant.mode,
            .read_only,
            "workspace access request retains the exact requested grant mode"
        )

        return [
            .field(
                "file_operation",
                preflight.operation.schema.identifier.rawValue
            ),
            .field(
                "workspace_access_request",
                grantedRoot.root.id.rawValue
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
