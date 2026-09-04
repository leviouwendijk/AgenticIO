import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros
import Path

/// Model-facing input for Explain pathAccess.
@JSONSchema
public struct ExplainPathAccessToolInput: Sendable, Codable, Hashable {
    /// Optional workspace root identifier.
    public let rootID: PathAccessRootIdentifier?
    /// Root-relative path whose access should be explained.
    public let path: String
    /// Requested path capability to evaluate.
    public let capability: PathCapability
    /// Optional tool name to evaluate against grant restrictions.
    public let toolName: String?
    /// Optional expected path segment type.
    public let type: PathSegmentType?

    public init(
        rootID: PathAccessRootIdentifier? = nil,
        path: String,
        capability: PathCapability = .read,
        toolName: String? = nil,
        type: PathSegmentType? = nil
    ) {
        self.rootID = rootID
        self.path = path
        self.capability = capability
        self.toolName = toolName
        self.type = type
    }
}

public struct ExplainPathAccessToolOutput: Sendable, Codable, Hashable {
    public let allowed: Bool
    public let rootID: String
    public let path: String
    public let capability: PathCapability
    public let toolName: String
    public let resolvedPath: String?
    public let decision: String?
    public let matchedRule: String?
    public let reason: String
    public let policyChecks: [String]
    public let suggestedGrant: PathGrantSuggestion?

    public init(
        allowed: Bool,
        rootID: String,
        path: String,
        capability: PathCapability,
        toolName: String,
        resolvedPath: String?,
        decision: String?,
        matchedRule: String?,
        reason: String,
        policyChecks: [String],
        suggestedGrant: PathGrantSuggestion? = nil
    ) {
        self.allowed = allowed
        self.rootID = rootID
        self.path = path
        self.capability = capability
        self.toolName = toolName
        self.resolvedPath = resolvedPath
        self.decision = decision
        self.matchedRule = matchedRule
        self.reason = reason
        self.policyChecks = policyChecks
        self.suggestedGrant = suggestedGrant
    }
}

public struct ExplainPathAccessTool: AgentTool {
    public typealias Input = ExplainPathAccessToolInput
    public typealias Output = ExplainPathAccessToolOutput

    public static let identifier: AgentToolIdentifier = "explain_path_access"
    public static let description = "Explain whether a root-relative path is accessible for a requested capability and why."
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
        let rootID = input.rootID ?? .project

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            targetPaths: [
                input.path
            ],
            summary: "Explain \(input.capability.rawValue) access for \(rootID.rawValue):\(input.path).",
            rootIDs: [
                rootID.rawValue
            ],
            capabilitiesRequired: [
                .list
            ],
            policyChecks: [
                "no_file_content_access",
                "access_explanation_only"
            ]
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {
        let rootID = input.rootID ?? .project
        let requestedToolName = normalizedToolName(
            input.toolName
        )

        guard let workspace = context.workspace else {
            return ExplainPathAccessToolOutput(
                allowed: false,
                rootID: rootID.rawValue,
                path: input.path,
                capability: input.capability,
                toolName: requestedToolName,
                resolvedPath: nil,
                decision: nil,
                matchedRule: nil,
                reason: "No AgentWorkspace is attached.",
                policyChecks: [
                    "workspace_missing"
                ]
            )
            
        }

        do {
            let descendant = try workspace.accessController.paths.resolve(
                input.path,
                rootIdentifier: rootID,
                type: input.type
            )
            let evaluation = try workspace.accessController.paths.evaluate(
                descendant,
                rootIdentifier: rootID,
                type: input.type
            )
            let resolvedPath = descendant.presentingRelative(
                filetype: true
            )

            guard evaluation.isAllowed else {
                return ExplainPathAccessToolOutput(
                    allowed: false,
                    rootID: rootID.rawValue,
                    path: input.path,
                    capability: input.capability,
                    toolName: requestedToolName,
                    resolvedPath: resolvedPath,
                    decision: evaluation.decision.rawValue,
                    matchedRule: evaluation.matchedRule?.matcher.summary,
                    reason: evaluation.matchedRule?.reason ?? "Path access policy denied this path.",
                    policyChecks: [
                        "root_resolved",
                        "path_sandboxed",
                        "path_policy_denied"
                    ]
                )
                
            }

            let grants = workspace.accessController.activeGrants(
                rootID: rootID,
                capability: input.capability,
                toolName: requestedToolName
            )

            guard let grant = grants.first else {
                return ExplainPathAccessToolOutput(
                    allowed: false,
                    rootID: rootID.rawValue,
                    path: input.path,
                    capability: input.capability,
                    toolName: requestedToolName,
                    resolvedPath: resolvedPath,
                    decision: evaluation.decision.rawValue,
                    matchedRule: evaluation.matchedRule?.matcher.summary,
                    reason: "Path policy allows this path, but no active workspace grant allows capability '\(input.capability.rawValue)' for tool '\(requestedToolName)'.",
                    policyChecks: [
                        "root_resolved",
                        "path_sandboxed",
                        "path_policy_allowed",
                        "grant_denied"
                    ],
                    suggestedGrant: suggestion(
                        rootID: rootID,
                        capability: input.capability,
                        toolName: requestedToolName
                    )
                )
                
            }

            return ExplainPathAccessToolOutput(
                allowed: true,
                rootID: rootID.rawValue,
                path: input.path,
                capability: input.capability,
                toolName: requestedToolName,
                resolvedPath: resolvedPath,
                decision: evaluation.decision.rawValue,
                matchedRule: evaluation.matchedRule?.matcher.summary,
                reason: "Allowed by path policy and active grant '\(grant.id)'.",
                policyChecks: [
                    "root_resolved",
                    "path_sandboxed",
                    "path_policy_allowed",
                    "grant_allowed",
                    "capability_allowed",
                    "tool_allowed"
                ]
            )
            
        } catch {
            return ExplainPathAccessToolOutput(
                allowed: false,
                rootID: rootID.rawValue,
                path: input.path,
                capability: input.capability,
                toolName: requestedToolName,
                resolvedPath: nil,
                decision: nil,
                matchedRule: nil,
                reason: error.localizedDescription,
                policyChecks: [
                    "access_resolution_failed"
                ],
                suggestedGrant: suggestion(
                    rootID: rootID,
                    capability: input.capability,
                    toolName: requestedToolName
                )
            )
            
        }
    }
}

internal extension ExplainPathAccessTool {
    func normalizedToolName(
        _ value: String?
    ) -> String {
        let trimmed = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let trimmed,
              !trimmed.isEmpty else {
            return "unspecified"
        }

        return trimmed
    }

    func suggestion(
        rootID: PathAccessRootIdentifier,
        capability: PathCapability,
        toolName: String
    ) -> PathGrantSuggestion {
        let mode: PathGrantMode = switch capability {
        case .list, .scan:
            .path_only

        case .read:
            .read_only

        case .write, .edit, .create_directory:
            .read_write
        }

        return .init(
            rootID: rootID.rawValue,
            mode: mode,
            capabilities: WorkspaceToolSupport.defaultCapabilities(
                for: mode
            ),
            allowedTools: WorkspaceToolSupport.defaultAllowedTools(
                for: mode,
                including: toolName
            ),
            reason: "Request a named grant for root '\(rootID.rawValue)' before retrying this tool."
        )
    }
}