import Schema
import Macros
import Agentic
import Workspace
import Foundation

public struct WorkspaceRootToolSummary: Sendable, Codable, Hashable {
    public let rootID: String
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
    public let capabilities: [WorkspaceCapability]
    public let expiresAt: Date?
    public let status: String

    public init(
        grant: WorkspaceGrant,
        status: WorkspaceGrantStatus?
    ) {
        self.id = grant.id.rawValue
        self.rootID = grant.rootIdentifier.rawValue
        self.capabilities = grant.capabilities.sorted {
            $0.rawValue < $1.rawValue
        }
        self.expiresAt = grant.expiresAt
        self.status = Self.statusName(
            status
        )
    }

    private static func statusName(
        _ status: WorkspaceGrantStatus?
    ) -> String {
        switch status {
        case .active:
            return "active"
        case .expired:
            return "expired"
        case .invalidated:
            return "invalidated"
        case nil:
            return "unknown"
        }
    }
}

public struct PathGrantSuggestion: Sendable, Codable, Hashable {
    public let rootID: String
    public let capabilities: [WorkspaceCapability]
    public let reason: String

    public init(
        rootID: String,
        capabilities: [WorkspaceCapability],
        reason: String
    ) {
        self.rootID = rootID
        self.capabilities = capabilities
        self.reason = reason
    }
}

@JSONSchema
public struct RequestPathGrantToolInput: Sendable, Codable, Hashable {
    public let requestedRootPath: String
    public let suggestedRootID: String?
    public let label: String?
    public let capabilities: [WorkspaceCapability]?
    public let reason: String
    public let policyProfile: String?
    public let expiresInSeconds: TimeInterval?

    public init(
        requestedRootPath: String,
        suggestedRootID: String? = nil,
        label: String? = nil,
        capabilities: [WorkspaceCapability]? = nil,
        reason: String,
        policyProfile: String? = nil,
        expiresInSeconds: TimeInterval? = nil
    ) {
        self.requestedRootPath = requestedRootPath
        self.suggestedRootID = suggestedRootID
        self.label = label
        self.capabilities = capabilities
        self.reason = reason
        self.policyProfile = policyProfile
        self.expiresInSeconds = expiresInSeconds
    }
}

@JSONSchema
public struct WorkspaceAccessRequest: Result, Hashable {
    public let rootID: String
    public let rootPath: String
    public let label: String
    public let capabilities: [WorkspaceCapability]
    public let reason: String
    public let policyProfile: String
    public let durationSeconds: Double?

    public init(
        rootID: String,
        rootPath: String,
        label: String,
        capabilities: [WorkspaceCapability],
        reason: String,
        policyProfile: String,
        durationSeconds: Double?
    ) {
        self.rootID = rootID
        self.rootPath = rootPath
        self.label = label
        self.capabilities = capabilities
        self.reason = reason
        self.policyProfile = policyProfile
        self.durationSeconds = durationSeconds
    }
}
