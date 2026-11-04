import Foundation
import Writers

public enum FileMutationOperationPolicyError: Error, Sendable, LocalizedError {
    case operation_not_allowed(MutateFilesToolEntryKind)
    case plan_entry_mismatch

    public var errorDescription: String? {
        switch self {
        case .operation_not_allowed(let kind):
            return "File mutation operation '\(kind.rawValue)' is not permitted by this tool."
        case .plan_entry_mismatch:
            return "Prepared mutation operations do not match the requested operations."
        }
    }
}

/// Restricts the top-level operations accepted by one configured MutateFiles tool.
///
/// The policy is immutable and currently belongs to the concrete tool instance.
/// Its default is unrestricted; defining an agent's capability identifier alone
/// does not select a restricted configuration.
///
/// Future capability configuration integration:
/// - Preserve the existing installed -> available -> visible capability hierarchy.
/// - Treat configuration as an orthogonal dimension, not another visibility state.
/// - Associate typed tool configuration with an agent's realized capability,
///   allowing different agents to configure the same tool independently.
/// - Support mutable effective configuration without requiring mutable tool values.
/// - Expose configuration beneath each capability in the UI as an inspectable,
///   editable subtree, alongside availability and visibility controls.
/// - Derive UI controls from typed configuration contracts where practical,
///   rather than hardcoding individual controls for every tool.
/// - Distinguish tool defaults, agent overrides, and effective configuration.
/// - Consider versioned configuration snapshots for persistence and inspection.
/// - Require authorized Host-controlled changes for security-sensitive settings;
///   agents must not be able to broaden their own operation permissions.
///
/// These integration points are design intentions, not implemented behavior.
/// Do not introduce generalized configuration storage or UI infrastructure here
/// until the agent realization and capability-state boundaries are established.
public struct FileMutationOperationPolicy: Sendable, Codable, Hashable {
    public let allowed: Set<MutateFilesToolEntryKind>

    public init(allowed: Set<MutateFilesToolEntryKind>) {
        self.allowed = allowed
    }

    public static let unrestricted = Self(
        allowed: Set(MutateFilesToolEntryKind.allCases)
    )

    public static func only(_ kinds: Set<MutateFilesToolEntryKind>) -> Self {
        .init(allowed: kinds)
    }

    public func authorize(_ entries: [MutateFilesToolEntry]) throws {
        for entry in entries {
            try authorize(entry.kind)
        }
    }

    /// Checks both the permitted operation kinds and the prepared plan's
    /// correspondence with the requested batch.
    ///
    /// Future mutable configurations must be checked against the effective
    /// policy at execution time, including after suspension and resumption.
    /// A previously prepared or approved operation must not silently retain
    /// permissions that have since been revoked.
    public func authorize(
        _ plan: StandardMutationPlan,
        matching entries: [MutateFilesToolEntry]
    ) throws {
        guard plan.entries.count == entries.count else {
            throw FileMutationOperationPolicyError.plan_entry_mismatch
        }

        for (requested, planned) in zip(entries, plan.entries) {
            let plannedKind = Self.kind(of: planned.entry)
            guard requested.kind == plannedKind else {
                throw FileMutationOperationPolicyError.plan_entry_mismatch
            }
            try authorize(plannedKind)
        }
    }

    private func authorize(_ kind: MutateFilesToolEntryKind) throws {
        guard allowed.contains(kind) else {
            throw FileMutationOperationPolicyError.operation_not_allowed(kind)
        }
    }

    private static func kind(of entry: StandardMutationEntry) -> MutateFilesToolEntryKind {
        switch entry {
        case .create_text: .create_text
        case .replace_text: .replace_text
        case .edit_text: .edit_text
        case .copy: .copy
        case .move: .move
        case .delete: .delete
        }
    }
}
