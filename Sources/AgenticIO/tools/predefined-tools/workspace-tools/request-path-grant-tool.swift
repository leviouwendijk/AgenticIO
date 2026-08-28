import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Primitives
import Path

public struct RequestPathGrantToolOutput: Sendable, Codable, Hashable {
    public let intentID: PreparedIntentIdentifier
    public let status: PreparedIntentStatus
    public let actionType: String
    public let title: String
    public let summary: String
    public let target: String?

    public init(
        intent: PreparedIntent
    ) {
        self.intentID = intent.id
        self.status = intent.status
        self.actionType = intent.actionType
        self.title = intent.reviewPayload.title
        self.summary = intent.reviewPayload.summary
        self.target = intent.reviewPayload.target
    }
}

public struct RequestPathGrantTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "request_path_grant"
    public static let description = "Create a prepared intent requesting a new named workspace path grant. This does not install access."
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

    public let manager: PreparedIntentManager

    public init(
        manager: PreparedIntentManager
    ) {
        self.manager = manager
    }

    public func preflight(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            RequestPathGrantToolInput.self,
            from: input
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            targetPaths: [
                decoded.requestedRootPath
            ],
            summary: "Stage a prepared path grant request for \(decoded.requestedRootPath).",
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
        input: JSONValue,
        workspace _: AgentWorkspace?
    ) async throws -> JSONValue {
        let decoded = try JSONToolBridge.decode(
            RequestPathGrantToolInput.self,
            from: input
        )
        let rootURL = try normalizedExistingDirectoryURL(
            decoded.requestedRootPath
        )
        let mode = decoded.mode ?? .read_only
        let capabilities = decoded.capabilities?.isEmpty == false
            ? decoded.capabilities!
            : WorkspaceToolSupport.defaultCapabilities(
                for: mode
            )
        let allowedTools = decoded.allowedTools?.isEmpty == false
            ? decoded.allowedTools!
            : WorkspaceToolSupport.defaultAllowedTools(
                for: mode
            )
        let rootID = normalizedRootID(
            decoded.suggestedRootID,
            fallback: rootURL.lastPathComponent
        )
        let label = normalizedLabel(
            decoded.label,
            fallback: rootURL.lastPathComponent
        )
        let reason = try normalizedRequired(
            decoded.reason,
            field: "reason"
        )
        let policyProfile = normalizedPolicyProfile(
            decoded.policyProfile
        )
        let expiresAt = decoded.expiresInSeconds.map {
            Date().addingTimeInterval(
                max(0, $0)
            )
        }

        let exactInputs = PathGrantReviewExactInputs(
            rootID: rootID.rawValue,
            label: label,
            requestedRootPath: rootURL.path,
            mode: mode,
            capabilities: capabilities,
            allowedTools: allowedTools,
            reason: reason,
            policyProfile: policyProfile,
            expiresAt: expiresAt
        )

        let risk = reviewRisk(
            mode: mode
        )
        let payload = PreparedIntentReviewPayload(
            title: "Request workspace path grant: \(label)",
            summary: """
            Request a \(mode.rawValue) workspace path grant for '\(rootURL.path)' as rootID '\(rootID.rawValue)'.

            This prepared intent only stages the request. It does not install access.
            """,
            actionType: "path_grant.request",
            risk: risk,
            target: rootURL.path,
            exactInputs: try JSONToolBridge.encode(
                exactInputs
            ),
            expectedSideEffects: [
                "If approved and installed by the host, adds named workspace root '\(rootID.rawValue)'.",
                "Allows future tool calls using rootID '\(rootID.rawValue)' and the listed capabilities.",
                "This request tool itself does not install access."
            ],
            policyChecks: [
                "requested_root_exists",
                "requested_root_is_directory",
                "grant_install_requires_host_or_approval_flow",
                "no_direct_access_installation"
            ],
            warnings: warnings(
                rootURL: rootURL,
                mode: mode
            ),
            expiresAt: expiresAt,
            metadata: [
                "rootID": rootID.rawValue,
                "mode": mode.rawValue,
                "policyProfile": policyProfile
            ]
        )

        let intent = try await manager.create(
            PreparedIntentDraft(
                sessionID: decoded.sessionID,
                actionType: "path_grant.request",
                reviewPayload: payload,
                executionToolName: nil,
                idempotencyKey: "path-grant:\(rootID.rawValue):\(rootURL.path):\(mode.rawValue)",
                metadata: [
                    "rootID": rootID.rawValue,
                    "requestedRootPath": rootURL.path,
                    "mode": mode.rawValue,
                    "policyProfile": policyProfile
                ]
            )
        )

        return try JSONToolBridge.encode(
            RequestPathGrantToolOutput(
                intent: intent
            )
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
