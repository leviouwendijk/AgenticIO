import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Primitives
import Path

public struct ListPathGrantsToolInput: Sendable, Codable, Hashable {
    public let rootID: PathAccessRootIdentifier?
    public let includeExpired: Bool?

    public init(
        rootID: PathAccessRootIdentifier? = nil,
        includeExpired: Bool? = nil
    ) {
        self.rootID = rootID
        self.includeExpired = includeExpired
    }
}

public struct ListPathGrantsToolOutput: Sendable, Codable, Hashable {
    public let grants: [WorkspaceGrantToolSummary]

    public init(
        grants: [WorkspaceGrantToolSummary]
    ) {
        self.grants = grants
    }
}

public struct ListPathGrantsTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "list_path_grants"
    public static let description = "List active workspace path grants and their capabilities."
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
            summary: "List workspace path grants.",
            capabilitiesRequired: [
                .list
            ],
            policyChecks: [
                "no_file_content_access",
                "grant_metadata_only"
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
            ListPathGrantsToolInput.self,
            from: input
        )
        let now = Date()

        let grants = workspace.accessController.grants.filter { grant in
            if let rootID = decoded.rootID,
               grant.rootID != rootID {
                return false
            }

            if decoded.includeExpired != true,
               grant.isExpired(at: now) {
                return false
            }

            return true
        }

        return try JSONToolBridge.encode(
            ListPathGrantsToolOutput(
                grants: grants.map {
                    WorkspaceGrantToolSummary(
                        grant: $0,
                        now: now
                    )
                }
            )
        )
    }
}
