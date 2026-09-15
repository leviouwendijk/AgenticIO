import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Primitives
import Path

public struct RequestPathGrantToolOutput: Sendable, Codable, Hashable {
    public let intentID: PreparedIntentIdentifier
    public let status: PreparedIntentStatus
    public let operationIdentifier: String
    public let title: String
    public let summary: String
    public let target: String?

    public init(
        intent: PreparedIntent
    ) {
        self.intentID = intent.id
        self.status = intent.status
        self.operationIdentifier = intent.operation.schema.identifier.rawValue
        self.title = intent.reviewPayload.title
        self.summary = intent.reviewPayload.summary
        self.target = intent.reviewPayload.target
    }
}

public struct RequestPathGrantTool: AgentTool {
    public typealias Input = RequestPathGrantToolInput
    public typealias Output = RequestPathGrantToolOutput

    public static let identifier: AgentToolIdentifier = "request_path_grant"
    public static let description = "Create a prepared intent requesting a new named workspace path grant. This does not install access."
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

    public let manager: PreparedIntentManager

    public init(
        manager: PreparedIntentManager
    ) {
        self.manager = manager
    }

    public func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            targetPaths: [
                input.requestedRootPath
            ],
            summary: "Stage a prepared path grant request for \(input.requestedRootPath).",
            estimatedWriteCount: 1,
            sideEffects: [
                "creates prepared path grant intent",
                "does not install workspace access"
            ],
            capabilitiesRequired: [
                .list
            ],
            isPreview: true,
            policyChecks: [
                "prepared_intent_required",
                "grant_not_installed_by_tool",
                "human_review_required_before_install"
            ]
        )
    }

    public func call(
        _ input: Input,
        context _: AgentToolExecutionContext
    ) async throws -> Output {
        let rootURL = try normalizedExistingDirectoryURL(
            input.requestedRootPath
        )
        let mode = input.mode ?? .read_only
        let capabilities = input.capabilities.flatMap { values in
            values.isEmpty ? nil : values
        } ?? WorkspaceToolSupport.defaultCapabilities(
            for: mode
        )
        let allowedTools = input.allowedTools.flatMap { values in
            values.isEmpty ? nil : values
        } ?? WorkspaceToolSupport.defaultAllowedTools(
            for: mode
        )
        let rootID = normalizedRootID(
            input.suggestedRootID,
            fallback: rootURL.lastPathComponent
        )
        let label = normalizedLabel(
            input.label,
            fallback: rootURL.lastPathComponent
        )
        let reason = try normalizedRequired(
            input.reason,
            field: "reason"
        )
        let policyProfile = normalizedPolicyProfile(
            input.policyProfile
        )
        let accessPolicy = try resolvedAccessPolicy(
            profile: policyProfile
        )
        let lifetime = input.lifetime ?? .turn
        let durationSeconds = try resolvedDurationSeconds(
            input.expiresInSeconds
        )
        let grant = PathGrant(
            id: UUID().uuidString,
            rootID: rootID,
            mode: mode,
            capabilities: capabilities,
            allowedTools: allowedTools,
            reason: reason,
            expiresAt: nil,
            metadata: [
                "policy_profile": policyProfile,
                "requested_lifetime": lifetime.rawValue
            ]
        )
        let overlay = try WorkspaceAccessOverlay(
            roots: [
                .init(
                    root: .init(
                        id: rootID,
                        label: label,
                        scope: try PathAccessScope(
                            root: rootURL,
                            policy: accessPolicy
                        ),
                        details: "Temporary workspace access requested through Agentic.",
                        isDefault: false
                    ),
                    grant: grant
                )
            ]
        )
        let operation = try PreparedPathGrantOperation.envelope(
            .init(
                overlay: overlay,
                lifetime: lifetime,
                durationSeconds: durationSeconds
            )
        )
        let risk = reviewRisk(
            mode: mode
        )
        let payload = PreparedIntentReviewPayload(
            title: "Request workspace path grant: \(label)",
            summary: """
            Request a \(mode.rawValue) temporary path grant for '\(rootURL.path)' as rootID '\(rootID.rawValue)'.

            Requested lifetime: \(lifetime.rawValue). The prepared operation captures the exact workspace-access overlay but does not alter the base workspace.
            """,
            risk: risk,
            target: rootURL.path,
            expectedSideEffects: [
                "If approved, makes rootID '\(rootID.rawValue)' available through a temporary \(lifetime.rawValue) overlay.",
                "Allows future tool calls to use the exact captured capabilities while that overlay is active.",
                "Does not persist this root into the declared base workspace."
            ],
            policyChecks: [
                "requested_root_exists",
                "requested_root_is_directory",
                "exact_workspace_access_overlay_captured",
                "temporary_grant_lifetime_explicit",
                "base_workspace_unchanged_by_request"
            ],
            warnings: warnings(
                rootURL: rootURL,
                mode: mode
            ),
            metadata: [
                "rootID": rootID.rawValue,
                "mode": mode.rawValue,
                "policyProfile": policyProfile,
                "lifetime": lifetime.rawValue
            ]
        )

        let intent = try await manager.create(
            PreparedIntentDraft(
                sessionID: input.sessionID,
                operation: operation,
                reviewPayload: payload,
                expiresAt: nil,
                idempotencyKey: "path-grant:\(rootID.rawValue):\(rootURL.path):\(mode.rawValue):\(lifetime.rawValue)",
                metadata: [
                    "rootID": rootID.rawValue,
                    "requestedRootPath": rootURL.path,
                    "mode": mode.rawValue,
                    "policyProfile": policyProfile,
                    "lifetime": lifetime.rawValue
                ]
            )
        )

        return RequestPathGrantToolOutput(
            intent: intent
        )
        
    }
}

private extension RequestPathGrantTool {
    func normalizedExistingDirectoryURL(
        _ value: String
    ) throws -> URL {
        let trimmed = try normalizedRequired(
            value,
            field: "requestedRootPath"
        )
        let expanded = (trimmed as NSString).expandingTildeInPath

        guard expanded.hasPrefix("/") else {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "requestedRootPath",
                reason: "must be an absolute path or tilde-expanded path"
            )
        }

        let url = URL(
            fileURLWithPath: expanded,
            isDirectory: true
        ).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) else {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "requestedRootPath",
                reason: "path does not exist"
            )
        }

        guard isDirectory.boolValue else {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "requestedRootPath",
                reason: "path is not a directory"
            )
        }

        return url
    }

    func normalizedRequired(
        _ value: String,
        field: String
    ) throws -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            throw PredefinedFileToolError.missingField(
                tool: name,
                field: field
            )
        }

        return trimmed
    }

    func normalizedRootID(
        _ value: String?,
        fallback: String
    ) -> PathAccessRootIdentifier {
        let source = normalizedOptional(
            value
        ) ?? fallback

        let normalized = source.map { character in
            if character.isLetter
                || character.isNumber
                || character == "-"
                || character == "_" {
                return String(character).lowercased()
            }

            return "-"
        }.joined()

        let trimmed = normalized.trimmingCharacters(
            in: CharacterSet(
                charactersIn: "-"
            )
        )

        return .init(
            rawValue: trimmed.isEmpty ? "requested-root" : trimmed
        )
    }

    func normalizedLabel(
        _ value: String?,
        fallback: String
    ) -> String {
        normalizedOptional(value)
            ?? (fallback.isEmpty ? "Requested Root" : fallback)
    }

    func normalizedPolicyProfile(
        _ value: String?
    ) -> String {
        normalizedOptional(value)
            ?? "workspace_default"
    }

    func resolvedAccessPolicy(
        profile: String
    ) throws -> PathAccessPolicy {
        switch profile {
        case "workspace_default":
            return .defaults.workspace

        default:
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "policyProfile",
                reason: "unsupported path grant policy profile '\(profile)'"
            )
        }
    }

    func resolvedDurationSeconds(
        _ value: TimeInterval?
    ) throws -> TimeInterval? {
        guard let value else {
            return nil
        }
        guard value >= 0 else {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "expiresInSeconds",
                reason: "must not be negative"
            )
        }

        return value
    }

    func normalizedOptional(
        _ value: String?
    ) -> String? {
        let trimmed = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let trimmed,
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    func reviewRisk(
        mode: PathGrantMode
    ) -> ActionRisk {
        switch mode {
        case .path_only, .read_only:
            return .observe

        case .read_write:
            return .privileged
        }
    }

    func warnings(
        rootURL: URL,
        mode: PathGrantMode
    ) -> [String] {
        var warnings: [String] = []

        if rootURL.path == NSHomeDirectory() {
            warnings.append(
                "Requested root is the user home directory. Prefer a narrower root or path_only access."
            )
        }

        if mode == .read_write {
            warnings.append(
                "read_write grants expand future mutation authority and should require explicit review."
            )
        }

        return warnings
    }
}