import Foundation
import Path
import Workspace

func makeAgenticIOTestingWorkspace(
    root: URL,
    at path: String = "."
) throws -> WorkspaceContext {
    let rootIdentifier = PathAccessRootIdentifier(
        rawValue: "project"
    )
    let accessRoot = PathAccessRoot(
        id: rootIdentifier,
        label: "Project",
        scope: try PathAccessScope(
            root: root,
            policy: .defaults.workspace
        ),
        isDefault: true
    )
    let grant = try WorkspaceGrant(
        id: try WorkspaceGrantIdentifier(
            "agentic-io-testing"
        ),
        rootIdentifier: rootIdentifier,
        capabilities: Set(
            WorkspaceCapability.allCases
        )
    )
    let workspace = try Workspace(
        root: accessRoot,
        grants: [
            grant,
        ]
    )

    return try workspace.context(
        at: path,
        rootIdentifier: rootIdentifier
    )
}
