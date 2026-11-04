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
