import Agentic
import AgenticExecution
import Workspace
import Primitives
import Schema
import Macros
import Path


public extension SystemIO.Tools {
    @Tool
    struct ExplainPathAccess: Tool {
        /// Model-facing input for Explain pathAccess.
        @JSONSchema
        public struct Input: Sendable, Codable, Hashable {
            /// Optional workspace root identifier.
            public let rootID: PathAccessRootIdentifier?
            /// Root-relative path whose access should be explained.
            public let path: String
            /// Requested path capability to evaluate.
            public let capability: WorkspaceCapability
            /// Optional tool name to evaluate against grant restrictions.
            public let toolName: String?
            /// Optional expected path segment type.
            public let type: PathSegmentType?

            public init(
                rootID: PathAccessRootIdentifier? = nil,
                path: String,
                capability: WorkspaceCapability = .read,
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

        public struct Output: Result, Hashable {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let allowed: Bool
            public let rootID: String
            public let path: String
            public let capability: WorkspaceCapability
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
                capability: WorkspaceCapability,
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


        public static let purpose = "Explain whether a root-relative path is accessible for a requested capability and why."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            let rootID = workspace?.rootIdentifier
                ?? input.rootID
                ?? .project

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "Explain \(input.capability.rawValue) access for \(rootID.rawValue):\(input.path).",
                access: .init(
                    targets: [
                        input.path
                    ],
                    roots: [
                        rootID.rawValue
                    ],
                    capabilities: [
                        .list
                    ]
                ),
                policyChecks: [
                    "no_file_content_access",
                    "access_explanation_only"
                ]
            )
        }

        public func call(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> Output {
            let requestedToolName = normalizedToolName(
                input.toolName
            )

            guard let workspace else {
                let rootID = input.rootID ?? .project
                return Output(
                    allowed: false,
                    rootID: rootID.rawValue,
                    path: input.path,
                    capability: input.capability,
                    toolName: requestedToolName,
                    resolvedPath: nil,
                    decision: nil,
                    matchedRule: nil,
                    reason: "No WorkspaceContext is attached.",
                    policyChecks: [
                        "workspace_missing"
                    ]
                )
            }

            if let requestedRoot = input.rootID,
               requestedRoot != workspace.rootIdentifier {
                return Output(
                    allowed: false,
                    rootID: workspace.rootIdentifier.rawValue,
                    path: input.path,
                    capability: input.capability,
                    toolName: requestedToolName,
                    resolvedPath: nil,
                    decision: nil,
                    matchedRule: nil,
                    reason: "Requested root '\(requestedRoot.rawValue)' does not match the already-targeted workspace root '\(workspace.rootIdentifier.rawValue)'.",
                    policyChecks: [
                        "workspace_context_already_targeted",
                        "root_mismatch"
                    ],
                    suggestedGrant: suggestion(
                        rootID: requestedRoot,
                        capability: input.capability
                    )
                )
            }

            do {
                let authorization = try workspace.authorize(
                    input.path,
                    capability: input.capability
                )
                let authorized = authorization.authorizedPath
                let evaluation = authorized.evaluation

                return Output(
                    allowed: true,
                    rootID: authorized.rootIdentifier.rawValue,
                    path: input.path,
                    capability: input.capability,
                    toolName: requestedToolName,
                    resolvedPath: authorized.presentationPath,
                    decision: evaluation.decision.rawValue,
                    matchedRule: evaluation.matchedRule?.matcher.summary,
                    reason: "Allowed by the targeted workspace context for capability '\(input.capability.rawValue)'.",
                    policyChecks: authorized.policyChecks + [
                        "workspace_context_already_targeted",
                        "workspace_capability_authorized"
                    ]
                )
            } catch {
                return Output(
                    allowed: false,
                    rootID: workspace.rootIdentifier.rawValue,
                    path: input.path,
                    capability: input.capability,
                    toolName: requestedToolName,
                    resolvedPath: nil,
                    decision: nil,
                    matchedRule: nil,
                    reason: error.localizedDescription,
                    policyChecks: [
                        "workspace_context_already_targeted",
                        "workspace_capability_denied"
                    ],
                    suggestedGrant: suggestion(
                        rootID: workspace.rootIdentifier,
                        capability: input.capability
                    )
                )
            }
        }
    }
}

internal extension SystemIO.Tools.ExplainPathAccess {
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
        capability: WorkspaceCapability
    ) -> PathGrantSuggestion {
        .init(
            rootID: rootID.rawValue,
            capabilities: [
                capability
            ],
            reason: "Request capability '\(capability.rawValue)' for root '\(rootID.rawValue)' before retrying this tool."
        )
    }
}