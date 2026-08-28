import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives

public struct ListPathRootsToolInput: Sendable, Codable, Hashable {
    public let includeDiagnostics: Bool?

    public init(
        includeDiagnostics: Bool? = nil
    ) {
        self.includeDiagnostics = includeDiagnostics
    }
}

public struct ListPathRootsToolOutput: Sendable, Codable, Hashable {
    public let defaultRootID: String?
    public let roots: [WorkspaceRootToolSummary]

    public init(
        defaultRootID: String?,
        roots: [WorkspaceRootToolSummary]
    ) {
        self.defaultRootID = defaultRootID
        self.roots = roots
    }
}

public struct ListPathRootsTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "list_path_roots"
    public static let description = "List named workspace path roots without scanning or reading file contents."
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
            summary: "List workspace path roots.",
            capabilitiesRequired: [
                .list
            ],
            policyChecks: [
                "no_file_content_access",
                "root_metadata_only"
            ]
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let workspace = try WorkspaceToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )
        let decoded = try JSONToolBridge.decode(
            ListPathRootsToolInput.self,
            from: input
        )

        return try JSONToolBridge.encode(
            ListPathRootsToolOutput(
                defaultRootID: workspace.accessController.defaultRootID?.rawValue,
                roots: WorkspaceToolSupport.rootSummaries(
                    workspace: workspace,
                    includeDiagnostics: decoded.includeDiagnostics ?? true
                )
            )
        )
    }
}
