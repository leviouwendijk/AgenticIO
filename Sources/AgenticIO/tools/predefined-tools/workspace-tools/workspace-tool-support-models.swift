import Schema
import Macros
import Agentic
import AgenticWorkspace
import Foundation

public struct WorkspaceRootToolSummary: Sendable, Codable, Hashable {
    public let rootID: String
    /// Optional human-readable root label.
    public let label: String
    public let details: String?
    public let rootPath: String
    public let isDefault: Bool
    public let ruleCount: Int
    public let defaultDecision: String
    public let diagnostics: [String]

    public init(
        rootID: String,
        label: String,
        details: String?,
        rootPath: String,
        isDefault: Bool,
        ruleCount: Int,
        defaultDecision: String,
        diagnostics: [String]
    ) {
        self.rootID = rootID
        self.label = label
        self.details = details
        self.rootPath = rootPath
        self.isDefault = isDefault
        self.ruleCount = ruleCount
        self.defaultDecision = defaultDecision
        self.diagnostics = diagnostics
    }
}

public struct WorkspaceGrantToolSummary: Sendable, Codable, Hashable {
    public let id: String
    public let rootID: String
    /// Optional requested grant mode.
    public let mode: PathGrantMode
    /// Optional explicit path capabilities.
    public let capabilities: [PathCapability]
    /// Optional tool allowlist for the grant.
    public let allowedTools: [String]
    /// Reason the additional path grant is needed.
    public let reason: String?
    public let expiresAt: Date?
    public let isExpired: Bool
    public let sourcePreparedIntentID: PreparedIntentIdentifier?
    public let metadata: [String: String]

    public init(
        grant: PathGrant,
        now: Date = Date()
    ) {
        self.id = grant.id
        self.rootID = grant.rootID.rawValue
        self.mode = grant.mode
        self.capabilities = grant.capabilities
        self.allowedTools = grant.allowedTools
        self.reason = grant.reason
        self.expiresAt = grant.expiresAt
        self.isExpired = grant.isExpired(
            at: now
        )
        self.sourcePreparedIntentID = grant.sourcePreparedIntentID
        self.metadata = grant.metadata
    }
}

public struct PathGrantSuggestion: Sendable, Codable, Hashable {
    public let rootID: String
    public let mode: PathGrantMode
    public let capabilities: [PathCapability]
    public let allowedTools: [String]
    public let reason: String

    public init(
        rootID: String,
        mode: PathGrantMode,
        capabilities: [PathCapability],
        allowedTools: [String],
        reason: String
    ) {
        self.rootID = rootID
        self.mode = mode
        self.capabilities = capabilities
        self.allowedTools = allowedTools
        self.reason = reason
    }
}

/// Model-facing input for Request pathGrant.
@JSONSchema
public struct RequestPathGrantToolInput: Sendable, Codable, Hashable {
    /// Optional session identifier associated with the request.
    public let sessionID: String?
    /// Absolute directory path proposed as a temporary named root.
    public let requestedRootPath: String
    /// Optional preferred identifier for the proposed root.
    public let suggestedRootID: String?
    public let label: String?
    public let mode: PathGrantMode?
    public let capabilities: [PathCapability]?
    public let allowedTools: [String]?
    public let reason: String
    /// Optional policy profile for the requested root.
    public let policyProfile: String?
    /// Requested temporary authority lifetime. Defaults to this turn.
    public let lifetime: PathGrantLifetime?
    /// Optional maximum wall-clock duration once the grant becomes active.
    public let expiresInSeconds: TimeInterval?

    public init(
        sessionID: String? = nil,
        requestedRootPath: String,
        suggestedRootID: String? = nil,
        label: String? = nil,
        mode: PathGrantMode? = nil,
        capabilities: [PathCapability]? = nil,
        allowedTools: [String]? = nil,
        reason: String,
        policyProfile: String? = nil,
        lifetime: PathGrantLifetime? = nil,
        expiresInSeconds: TimeInterval? = nil
    ) {
        self.sessionID = sessionID
        self.requestedRootPath = requestedRootPath
        self.suggestedRootID = suggestedRootID
        self.label = label
        self.mode = mode
        self.capabilities = capabilities
        self.allowedTools = allowedTools
        self.reason = reason
        self.policyProfile = policyProfile
        self.lifetime = lifetime
        self.expiresInSeconds = expiresInSeconds
    }
}
