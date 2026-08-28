import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Path

public struct ExplainPathAccessToolInput: Sendable, Codable, Hashable {
    public let rootID: PathAccessRootIdentifier?
    public let path: String
    public let capability: PathCapability
    public let toolName: String?
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
    public static let identifier: AgentToolIdentifier = "explain_path_access"
    public static let description = "Explain whether a root-relative path is accessible for a requested capability and why."
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
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            ExplainPathAccessToolInput.self,
            from: input
        )
        let rootID = decoded.rootID ?? .project

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            targetPaths: [
                decoded.path
            ],
            summary: "Explain \(decoded.capability.rawValue) access for \(rootID.rawValue):\(decoded.path).",
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
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let decoded = try JSONToolBridge.decode(
            ExplainPathAccessToolInput.self,
            from: input
        )
        let rootID = decoded.rootID ?? .project
        let requestedToolName = normalizedToolName(
            decoded.toolName
        )

        guard let workspace else {
            return try JSONToolBridge.encode(
                ExplainPathAccessToolOutput(
                    allowed: false,
                    rootID: rootID.rawValue,
                    path: decoded.path,
                    capability: decoded.capability,
                    toolName: requestedToolName,
                    resolvedPath: nil,
                    decision: nil,
                    matchedRule: nil,
                    reason: "No AgentWorkspace is attached.",
                    policyChecks: [
                        "workspace_missing"
                    ]
                )
            )
        }

        do {
            let scoped = try workspace.accessController.paths.resolve(
                decoded.path,
                rootIdentifier: rootID,
                type: decoded.type
            )
            let evaluation = try workspace.accessController.paths.evaluate(
                scoped,
                rootIdentifier: rootID,
                type: decoded.type
            )
            let resolvedPath = scoped.presentingRelative(
                filetype: true
            )

            guard evaluation.isAllowed else {
                return try JSONToolBridge.encode(
                    ExplainPathAccessToolOutput(
                        allowed: false,
                        rootID: rootID.rawValue,
                        path: decoded.path,
                        capability: decoded.capability,
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
                )
            }

            let grants = workspace.accessController.activeGrants(
                rootID: rootID,
                capability: decoded.capability,
                toolName: requestedToolName
            )

            guard let grant = grants.first else {
                return try JSONToolBridge.encode(
                    ExplainPathAccessToolOutput(
                        allowed: false,
                        rootID: rootID.rawValue,
                        path: decoded.path,
                        capability: decoded.capability,
                        toolName: requestedToolName,
                        resolvedPath: resolvedPath,
                        decision: evaluation.decision.rawValue,
                        matchedRule: evaluation.matchedRule?.matcher.summary,
                        reason: "Path policy allows this path, but no active workspace grant allows capability '\(decoded.capability.rawValue)' for tool '\(requestedToolName)'.",
                        policyChecks: [
                            "root_resolved",
                            "path_sandboxed",
                            "path_policy_allowed",
                            "grant_denied"
                        ],
                        suggestedGrant: suggestion(
                            rootID: rootID,
                            capability: decoded.capability,
                            toolName: requestedToolName
                        )
                    )
                )
            }

            return try JSONToolBridge.encode(
                ExplainPathAccessToolOutput(
                    allowed: true,
                    rootID: rootID.rawValue,
                    path: decoded.path,
                    capability: decoded.capability,
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
            )
        } catch {
            return try JSONToolBridge.encode(
                ExplainPathAccessToolOutput(
                    allowed: false,
                    rootID: rootID.rawValue,
                    path: decoded.path,
                    capability: decoded.capability,
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
                        capability: decoded.capability,
                        toolName: requestedToolName
                    )
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
