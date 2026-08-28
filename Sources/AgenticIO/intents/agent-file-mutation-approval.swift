import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Path
import Readers
import Writers

public enum AgentFileMutationApprovalErrorCode: String, Sendable, Codable, Hashable, CaseIterable {
    case missing_guard
    case action_mismatch
    case stale_file
}

public enum AgentFileMutationApprovalError: Error, Sendable, LocalizedError {
    case missing_guard(
        intentID: PreparedIntentIdentifier,
        key: String
    )
    case action_mismatch(
        expected: String,
        actual: String
    )
    case stale_file(
        path: String,
        expected: StandardContentFingerprint,
        actual: StandardContentFingerprint
    )

    public var code: AgentFileMutationApprovalErrorCode {
        switch self {
        case .missing_guard:
            return .missing_guard

        case .action_mismatch:
            return .action_mismatch

        case .stale_file:
            return .stale_file
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missing_guard(let intentID, let key):
            return "Prepared file mutation intent \(intentID.rawValue) is missing approval guard metadata '\(key)'."

        case .action_mismatch(let expected, let actual):
            return "Prepared file mutation approval guard action mismatch. Expected '\(expected)', found '\(actual)'."

        case .stale_file(let path, let expected, let actual):
            return "Prepared file mutation for '\(path)' is stale. Expected approved original fingerprint \(expected), but current file fingerprint is \(actual)."
        }
    }
}

public struct AgentFileMutationApproval: Sendable, Codable, Hashable {
    public let action: FileMutationIntentAction
    public let rootID: PathAccessRootIdentifier
    public let path: String
    public let targetPath: String
    public let originalFingerprint: StandardContentFingerprint
    public let editedFingerprint: StandardContentFingerprint?

    public init(
        action: FileMutationIntentAction,
        rootID: PathAccessRootIdentifier,
        path: String,
        targetPath: String,
        originalFingerprint: StandardContentFingerprint,
        editedFingerprint: StandardContentFingerprint? = nil
    ) {
        self.action = action
        self.rootID = rootID
        self.path = path
        self.targetPath = targetPath
        self.originalFingerprint = originalFingerprint
        self.editedFingerprint = editedFingerprint
    }

    public var metadata: [String: String] {
        var values = [
            Keys.kind: Keys.kindValue,
            Keys.action: action.rawValue,
            Keys.rootID: rootID.rawValue,
            Keys.path: path,
            Keys.targetPath: targetPath,
            Keys.originalAlgorithm: originalFingerprint.algorithm,
            Keys.originalValue: originalFingerprint.value
        ]

        if let editedFingerprint {
            values[Keys.editedAlgorithm] = editedFingerprint.algorithm
            values[Keys.editedValue] = editedFingerprint.value
        }

        return values
    }

    public static func approval(
        for intent: PreparedIntent,
        action: FileMutationIntentAction
    ) throws -> Self? {
        switch action {
        case .write,
             .edit:
            return try Self(
                intentID: intent.id,
                action: action,
                metadata: metadata(
                    for: intent
                )
            )

        case .rollback:
            return nil
        }
    }

    public func requireCurrentFile(
        in workspace: AgentWorkspace,
        toolName: String
    ) throws {
        let authorized = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: rootID,
            path: path,
            capability: .write,
            toolName: toolName,
            type: .file
        )

        let current = try IntegratedReader.text(
            at: authorized.absoluteURL,
            encoding: .utf8,
            missingFileReturnsEmpty: true,
            normalizeNewlines: false
        )
        let actual = StandardContentFingerprint.fingerprint(
            for: current
        )

        guard actual == originalFingerprint else {
            throw AgentFileMutationApprovalError.stale_file(
                path: authorized.presentationPath,
                expected: originalFingerprint,
                actual: actual
            )
        }
    }
}

private extension AgentFileMutationApproval {
    init(
        intentID: PreparedIntentIdentifier,
        action: FileMutationIntentAction,
        metadata: [String: String]
    ) throws {
        let kind = try Self.required(
            Keys.kind,
            in: metadata,
            intentID: intentID
        )

        guard kind == Keys.kindValue else {
            throw AgentFileMutationApprovalError.missing_guard(
                intentID: intentID,
                key: Keys.kind
            )
        }

        let storedAction = try Self.required(
            Keys.action,
            in: metadata,
            intentID: intentID
        )

        guard storedAction == action.rawValue else {
            throw AgentFileMutationApprovalError.action_mismatch(
                expected: action.rawValue,
                actual: storedAction
            )
        }

        let rootID = PathAccessRootIdentifier(
            rawValue: try Self.required(
                Keys.rootID,
                in: metadata,
                intentID: intentID
            )
        )
        let path = try Self.required(
            Keys.path,
            in: metadata,
            intentID: intentID
        )
        let targetPath = try Self.required(
            Keys.targetPath,
            in: metadata,
            intentID: intentID
        )
        let originalFingerprint = StandardContentFingerprint(
            algorithm: try Self.required(
                Keys.originalAlgorithm,
                in: metadata,
                intentID: intentID
            ),
            value: try Self.required(
                Keys.originalValue,
                in: metadata,
                intentID: intentID
            )
        )
        let editedFingerprint = Self.fingerprint(
            algorithmKey: Keys.editedAlgorithm,
            valueKey: Keys.editedValue,
            metadata: metadata
        )

        self.init(
            action: action,
            rootID: rootID,
            path: path,
            targetPath: targetPath,
            originalFingerprint: originalFingerprint,
            editedFingerprint: editedFingerprint
        )
    }

    static func metadata(
        for intent: PreparedIntent
    ) -> [String: String] {
        intent.metadata.merging(
            intent.reviewPayload.metadata
        ) { _, reviewValue in
            reviewValue
        }
    }

    static func required(
        _ key: String,
        in metadata: [String: String],
        intentID: PreparedIntentIdentifier
    ) throws -> String {
        guard let value = metadata[key],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentFileMutationApprovalError.missing_guard(
                intentID: intentID,
                key: key
            )
        }

        return value
    }

    static func fingerprint(
        algorithmKey: String,
        valueKey: String,
        metadata: [String: String]
    ) -> StandardContentFingerprint? {
        guard let algorithm = metadata[algorithmKey],
              let value = metadata[valueKey],
              !algorithm.isEmpty,
              !value.isEmpty else {
            return nil
        }

        return .init(
            algorithm: algorithm,
            value: value
        )
    }

    enum Keys {
        static let kind = "agent_file_mutation_guard"
        static let kindValue = "approved_preflight"

        static let action = "guard_action"
        static let rootID = "guard_root_id"
        static let path = "guard_path"
        static let targetPath = "guard_target_path"

        static let originalAlgorithm = "guard_original_algorithm"
        static let originalValue = "guard_original_value"

        static let editedAlgorithm = "guard_edited_algorithm"
        static let editedValue = "guard_edited_value"
    }
}
