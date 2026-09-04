import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Primitives
import Schema
import SchemaMacros
import Path

/// Model-facing input for List pathGrants.
@JSONSchema
public struct ListPathGrantsToolInput: Sendable, Codable, Hashable {
    /// Optional root identifier used to filter grants.
    public let rootID: PathAccessRootIdentifier?
    /// Whether expired grants are included.
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
    public typealias Input = ListPathGrantsToolInput
    public typealias Output = ListPathGrantsToolOutput

    public static let identifier: AgentToolIdentifier = "list_path_grants"
    public static let description = "List active workspace path grants and their capabilities."
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
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {
        let workspace = try WorkspaceToolSupport.requireWorkspace(
            context.workspace,
            toolName: name
        )
        let now = Date()

        let grants = workspace.accessController.grants.filter { grant in
            if let rootID = input.rootID,
               grant.rootID != rootID {
                return false
            }

            if input.includeExpired != true,
               grant.isExpired(at: now) {
                return false
            }

            return true
        }

        return ListPathGrantsToolOutput(
            grants: grants.map {
                WorkspaceGrantToolSummary(
                    grant: $0,
                    now: now
                )
            }
        )
        
    }
}