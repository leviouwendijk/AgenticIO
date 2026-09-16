import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Primitives
import Path

public struct RequestPathGrantTool: AgentTool {
    public typealias Input = RequestPathGrantToolInput
    public typealias Output = WorkspaceAccessRequest

    public static let identifier: AgentToolIdentifier = "request_path_grant"
    public static let description = "Request temporary workspace access to an existing directory. The runtime suspends so a human can deny it or grant it for the current turn or session."
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
            targetPaths: [
                input.requestedRootPath
            ],
            summary: "Request temporary workspace access to \(input.requestedRootPath).",
            estimatedWriteCount: 0,
            sideEffects: [
                "requests temporary workspace authority",
                "does not install workspace access"
            ],
            capabilitiesRequired: [
                .list
            ],
            isPreview: false,
            policyChecks: [
                "requested_root_exists",
                "requested_root_is_directory",
                "grant_not_installed_by_tool",
                "human_resolution_required"
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
                "policy_profile": policyProfile
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

        return WorkspaceAccessRequest(
            overlay: overlay,
            durationSeconds: durationSeconds
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
        guard value.isFinite,
              value >= 0
        else {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "expiresInSeconds",
                reason: "must be finite and non-negative"
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
}