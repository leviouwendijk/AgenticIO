import Workspace
import Foundation
import Path

enum WorkspaceToolSupport {
    static func requireWorkspace(
        _ workspace: WorkspaceContext?,
        toolName: String
    ) throws -> WorkspaceContext {
        guard let workspace else {
            throw PredefinedFileToolError.workspaceRequired(
                toolName
            )
        }

        return workspace
    }

    static func rootSummaries(
        workspace: WorkspaceContext,
        includeDiagnostics: Bool
    ) -> [WorkspaceRootToolSummary] {
        workspace.roots
            .sorted {
                $0.id.rawValue < $1.id.rawValue
            }
            .map { root in
                WorkspaceRootToolSummary(
                    rootID: root.id.rawValue,
                    label: root.label,
                    details: root.details,
                    rootPath: root.rootPath,
                    isDefault: root.id == workspace.defaultRootIdentifier,
                    ruleCount: root.scope.policy.rules.count,
                    defaultDecision: root.scope.policy.default.rawValue,
                    diagnostics: includeDiagnostics
                        ? rootDiagnostics(
                            root,
                            roots: workspace.roots
                        )
                        : []
                )
            }
    }

    static func grantSummaries(
        workspace: WorkspaceContext
    ) -> [WorkspaceGrantToolSummary] {
        workspace.grants.map { grant in
            WorkspaceGrantToolSummary(
                grant: grant,
                status: workspace.status(
                    of: grant.id
                )
            )
        }
    }

    static func diagnostics(
        workspace: WorkspaceContext
    ) -> [String] {
        var values: [String] = []

        if workspace.defaultRootIdentifier == nil {
            values.append(
                "Workspace has no default root identifier."
            )
        }

        for root in workspace.roots {
            values.append(
                contentsOf: rootDiagnostics(
                    root,
                    roots: workspace.roots
                )
            )
        }

        return Array(
            Set(values)
        ).sorted()
    }

    private static func rootDiagnostics(
        _ root: PathAccessRoot,
        roots: [PathAccessRoot]
    ) -> [String] {
        let rootPath = root.rootURL.standardizedFileURL.path

        return roots.compactMap { other in
            guard other.id != root.id else {
                return nil
            }

            let otherPath = other.rootURL.standardizedFileURL.path
            let prefix = rootPath.hasSuffix("/")
                ? rootPath
                : rootPath + "/"
            let otherPrefix = otherPath.hasSuffix("/")
                ? otherPath
                : otherPath + "/"

            if otherPath.hasPrefix(prefix) {
                return "Root '\(other.id.rawValue)' is nested under '\(root.id.rawValue)'."
            }

            if rootPath.hasPrefix(otherPrefix) {
                return "Root '\(root.id.rawValue)' is nested under '\(other.id.rawValue)'."
            }

            return nil
        }
    }
}
