import AgenticWorkspace
import Foundation

enum WorkspaceToolSupport {
    static func requireWorkspace(
        _ workspace: AgentWorkspace?,
        toolName: String
    ) throws -> AgentWorkspace {
        guard let workspace else {
            throw PredefinedFileToolError.workspaceRequired(
                toolName
            )
        }

        return workspace
    }

    static func rootSummaries(
        workspace: AgentWorkspace,
        includeDiagnostics: Bool
    ) -> [WorkspaceRootToolSummary] {
        workspace.accessController.paths.summary.roots.map { summary in
            WorkspaceRootToolSummary(
                rootID: summary.rootIdentifier.rawValue,
                label: summary.label,
                details: summary.details,
                rootPath: summary.rootPath,
                isDefault: summary.isDefault,
                ruleCount: summary.ruleCount,
                defaultDecision: summary.defaultDecision.rawValue,
                diagnostics: includeDiagnostics
                    ? summary.diagnostics.map(\.message)
                    : []
            )
        }
    }

    static func grantSummaries(
        workspace: AgentWorkspace,
        now: Date = Date()
    ) -> [WorkspaceGrantToolSummary] {
        workspace.accessController.grants.map {
            WorkspaceGrantToolSummary(
                grant: $0,
                now: now
            )
        }
    }

    static func defaultCapabilities(
        for mode: PathGrantMode
    ) -> [PathCapability] {
        PathCapability.allCases.filter {
            mode.defaultCapabilities.contains($0)
        }
    }

    static func defaultAllowedTools(
        for mode: PathGrantMode,
        including toolName: String? = nil
    ) -> [String] {
        var tools: [String]

        switch mode {
        case .path_only:
            tools = [
                "scan_paths",
                "find_paths"
            ]

        case .read_only:
            tools = [
                "scan_paths",
                "find_paths",
                "search_sources",
                "load_search_context",
                "read_file",
                "compose_context"
            ]

        case .read_write:
            tools = [
                "scan_paths",
                "find_paths",
                "search_sources",
                "load_search_context",
                "read_file",
                "compose_context",
                "write_file",
                "edit_file"
            ]
        }

        if let toolName,
           toolName != "unspecified",
           !tools.contains(toolName) {
            tools.append(
                toolName
            )
        }

        return tools
    }
}
