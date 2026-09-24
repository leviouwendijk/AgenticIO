import Agentic
import AgenticExecution
import Workspace
import Foundation
import Primitives
import Path

public extension SystemIO.Tools {
    @Tool
    struct RequestPathGrant: Tool {
        public typealias Input = RequestPathGrantToolInput
        public typealias Output = WorkspaceAccessRequest

        public static let purpose = "Request temporary workspace access to an existing directory. The runtime may suspend so a human can resolve the request."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            workspace _: WorkspaceContext?
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "Request temporary workspace access to \(input.requestedRootPath).",
                access: .init(
                    targets: [
                        input.requestedRootPath
                    ],
                    capabilities: [
                        .list
                    ]
                ),
                sideEffects: [
                    "requests temporary workspace authority",
                    "does not install workspace access"
                ],
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
            workspace _: WorkspaceContext?
        ) async throws -> Output {
            let rootURL = try normalizedExistingDirectoryURL(
                input.requestedRootPath
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
            let policyProfile = try resolvedPolicyProfile(
                input.policyProfile
            )
            let durationSeconds = try resolvedDurationSeconds(
                input.expiresInSeconds
            )
            let capabilities = resolvedCapabilities(
                input.capabilities
            )

            return WorkspaceAccessRequest(
                rootID: rootID.rawValue,
                rootPath: rootURL.path,
                label: label,
                capabilities: capabilities,
                reason: reason,
                policyProfile: policyProfile,
                durationSeconds: durationSeconds
            )
        }
    }
}

private extension SystemIO.Tools.RequestPathGrant {
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
                tool: Self.identifier.rawValue,
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
                tool: Self.identifier.rawValue,
                field: "requestedRootPath",
                reason: "path does not exist"
            )
        }

        guard isDirectory.boolValue else {
            throw PredefinedFileToolError.invalidValue(
                tool: Self.identifier.rawValue,
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
                tool: Self.identifier.rawValue,
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

    func resolvedPolicyProfile(
        _ value: String?
    ) throws -> String {
        let profile = normalizedOptional(value)
            ?? "workspace_default"

        guard profile == "workspace_default" else {
            throw PredefinedFileToolError.invalidValue(
                tool: Self.identifier.rawValue,
                field: "policyProfile",
                reason: "unsupported path grant policy profile '\(profile)'"
            )
        }

        return profile
    }

    func resolvedCapabilities(
        _ values: [WorkspaceCapability]?
    ) -> [WorkspaceCapability] {
        let values = values ?? [
            .read
        ]

        let unique = Set(
            values.isEmpty
                ? [
                    .read
                ]
                : values
        )

        return unique.sorted {
            $0.rawValue < $1.rawValue
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
                tool: Self.identifier.rawValue,
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
