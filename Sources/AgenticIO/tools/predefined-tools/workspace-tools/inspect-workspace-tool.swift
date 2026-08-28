import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

public struct InspectWorkspaceToolInput: Sendable, Codable, Hashable {
    public let includeDiagnostics: Bool?
    public let includeGrants: Bool?

    public init(
        includeDiagnostics: Bool? = nil,
        includeGrants: Bool? = nil
    ) {
        self.includeDiagnostics = includeDiagnostics
        self.includeGrants = includeGrants
    }
}

public struct InspectWorkspaceToolOutput: Sendable, Codable, Hashable {
    public let hasWorkspace: Bool
    public let defaultRootID: String?
    public let rootCount: Int
    public let grantCount: Int
    public let roots: [WorkspaceRootToolSummary]
    public let grants: [WorkspaceGrantToolSummary]
    public let diagnostics: [String]

    public init(
        hasWorkspace: Bool,
        defaultRootID: String?,
        rootCount: Int,
        grantCount: Int,
        roots: [WorkspaceRootToolSummary],
        grants: [WorkspaceGrantToolSummary],
        diagnostics: [String]
    ) {
        self.hasWorkspace = hasWorkspace
        self.defaultRootID = defaultRootID
        self.rootCount = rootCount
        self.grantCount = grantCount
        self.roots = roots
        self.grants = grants
        self.diagnostics = diagnostics
    }
}

public struct InspectWorkspaceTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "inspect_workspace"
    public static let description = "Inspect attached workspace roots, grants, and diagnostics without reading file contents."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }

    public var inputSchema: JSONValue? {
        nil
    }

    public var risk: ActionRisk {
        Self.risk
    }

    public init() {}

    public func preflight(
        input _: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: "Inspect workspace roots, grants, and diagnostics.",
            capabilitiesRequired: [
                .list
            ],
            policyChecks: [
                "no_file_content_access",
                "workspace_metadata_only"
            ]
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let decoded = try JSONToolBridge.decode(
            InspectWorkspaceToolInput.self,
            from: input
        )

        guard let workspace else {
            return try JSONToolBridge.encode(
                InspectWorkspaceToolOutput(
                    hasWorkspace: false,
                    defaultRootID: nil,
                    rootCount: 0,
                    grantCount: 0,
                    roots: [],
                    grants: [],
                    diagnostics: [
                        "No AgentWorkspace is attached."
                    ]
                )
            )
        }

        let includeDiagnostics = decoded.includeDiagnostics ?? true
        let includeGrants = decoded.includeGrants ?? true

        return try JSONToolBridge.encode(
            InspectWorkspaceToolOutput(
                hasWorkspace: true,
                defaultRootID: workspace.accessController.defaultRootID?.rawValue,
                rootCount: workspace.accessController.paths.roots.count,
                grantCount: workspace.accessController.grants.count,
                roots: WorkspaceToolSupport.rootSummaries(
                    workspace: workspace,
                    includeDiagnostics: includeDiagnostics
                ),
                grants: includeGrants
                    ? WorkspaceToolSupport.grantSummaries(
                        workspace: workspace
                    )
                    : [],
                diagnostics: includeDiagnostics
                    ? workspace.accessController.paths.summary.diagnostics.map(\.message)
                    : []
            )
        )
    }
}
