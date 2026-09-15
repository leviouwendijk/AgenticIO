import AgenticWorkspace
import Foundation
import Path
import TestFlows

extension AgenticIOFlowTesting {
    static func runWorkspaceAccessOverlay()
        async throws
        -> [TestFlowDiagnostic]
    {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentic-workspace-overlay-\(UUID().uuidString)",
                isDirectory: true
            )
        let projectRoot = fixtureRoot.appendingPathComponent(
            "project",
            isDirectory: true
        )
        let externalRoot = fixtureRoot.appendingPathComponent(
            "external",
            isDirectory: true
        )
        let externalFile = externalRoot.appendingPathComponent(
            "sample.txt",
            isDirectory: false
        )

        try FileManager.default.createDirectory(
            at: projectRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: externalRoot,
            withIntermediateDirectories: true
        )
        try "overlay fixture\n".write(
            to: externalFile,
            atomically: true,
            encoding: .utf8
        )

        defer {
            try? FileManager.default.removeItem(
                at: fixtureRoot
            )
        }

        let base = try AgentWorkspace(
            root: projectRoot
        )
        let rootID = PathAccessRootIdentifier(
            rawValue: "fixture_external"
        )
        let overlay = try WorkspaceAccessOverlay(
            roots: [
                .init(
                    root: .init(
                        id: rootID,
                        label: "Fixture External",
                        scope: try PathAccessScope(
                            root: externalRoot,
                            policy: .defaults.workspace
                        ),
                        isDefault: false
                    ),
                    grant: .init(
                        id: "fixture-overlay-read",
                        rootID: rootID,
                        mode: .read_only,
                        capabilities: [
                            .list,
                            .scan,
                            .read
                        ],
                        allowedTools: [
                            "read_file"
                        ],
                        reason: "Exercise temporary workspace overlay composition."
                    )
                )
            ]
        )
        let encoded = try JSONEncoder().encode(
            overlay
        )
        let decoded = try JSONDecoder().decode(
            WorkspaceAccessOverlay.self,
            from: encoded
        )
        let effective = try base.applying(
            decoded
        )
        let authorized = try effective.accessController.authorize(
            rootID: rootID,
            path: "sample.txt",
            capability: .read,
            toolName: "read_file",
            type: .file
        )
        var baseRejectedExternalRoot = false
        var effectiveRejectedWrite = false

        do {
            _ = try base.accessController.authorize(
                rootID: rootID,
                path: "sample.txt",
                capability: .read,
                toolName: "read_file",
                type: .file
            )
        } catch {
            baseRejectedExternalRoot = true
        }

        do {
            _ = try effective.accessController.authorize(
                rootID: rootID,
                path: "sample.txt",
                capability: .write,
                toolName: "mutate_files",
                type: .file
            )
        } catch {
            effectiveRejectedWrite = true
        }

        try Expect.equal(
            decoded,
            overlay,
            "workspace access overlay survives durable encode/decode without changing authority"
        )
        try Expect.equal(
            base.accessController.rootIdentifiers.count,
            1,
            "base workspace remains unchanged after overlay composition"
        )
        try Expect.equal(
            effective.accessController.rootIdentifiers.count,
            2,
            "effective workspace composes the temporary root over the base definition"
        )
        try Expect.equal(
            baseRejectedExternalRoot,
            true,
            "base workspace does not gain temporary external authority"
        )
        try Expect.equal(
            authorized.absoluteURL.standardizedFileURL.path,
            externalFile.standardizedFileURL.path,
            "effective workspace authorizes the exact external file through the overlay root"
        )
        try Expect.equal(
            effectiveRejectedWrite,
            true,
            "read-only overlay does not expand write authority"
        )

        return [
            .field(
                "base_root_count",
                String(base.accessController.rootIdentifiers.count)
            ),
            .field(
                "effective_root_count",
                String(effective.accessController.rootIdentifiers.count)
            ),
            .field(
                "base_unchanged",
                String(baseRejectedExternalRoot)
            ),
            .field(
                "read_authorized",
                "true"
            ),
            .field(
                "write_rejected",
                String(effectiveRejectedWrite)
            )
        ]
    }
}
