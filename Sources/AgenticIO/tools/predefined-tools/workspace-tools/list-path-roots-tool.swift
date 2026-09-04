import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

/// Model-facing input for List pathRoots.
@JSONSchema
public struct ListPathRootsToolInput: Sendable, Codable, Hashable {
    /// Whether root diagnostics are included.
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
    public typealias Input = ListPathRootsToolInput
    public typealias Output = ListPathRootsToolOutput

    public static let identifier: AgentToolIdentifier = "list_path_roots"
    public static let description = "List named workspace path roots without scanning or reading file contents."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }


    public var risk: ActionRisk {
        Self.risk
    }

    public init() {}

    public func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {
        .init(
            toolName: name,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
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
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {
        let workspace = try WorkspaceToolSupport.requireWorkspace(
            context.workspace,
            toolName: name
        )

        return ListPathRootsToolOutput(
            defaultRootID: workspace.accessController.defaultRootID?.rawValue,
            roots: WorkspaceToolSupport.rootSummaries(
                workspace: workspace,
                includeDiagnostics: input.includeDiagnostics ?? true
            )
        )
        
    }
}