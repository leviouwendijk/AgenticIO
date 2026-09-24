import Agentic
import AgenticExecution
import Foundation

public struct FileMutationIntentBuilder: Sendable {
    public var sessionID: String?
    public var expiresAt: Date?

    public init(
        sessionID: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.expiresAt = expiresAt
    }

    public func draft(
        for preflight: AgentFileMutationPreflight
    ) throws -> PreparedIntentDraft {
        let payload = PreparedIntentReviewPayload(
            title: "\(preflight.action.title): \(preflight.targetPath)",
            summary: summary(
                for: preflight
            ),
            risk: preflight.risk,
            target: preflight.targetPath,
            expectedSideEffects: preflight.sideEffects,
            policyChecks: preflight.policyChecks,
            warnings: preflight.warnings,
            metadata: reviewMetadata(
                for: preflight
            )
        )

        return PreparedIntentDraft(
            sessionID: sessionID,
            operation: preflight.operation,
            reviewPayload: payload,
            expiresAt: expiresAt,
            idempotencyKey: nil,
            metadata: draftMetadata(
                for: preflight
            )
        )
    }

    public func create(
        _ preflight: AgentFileMutationPreflight,
        using manager: PreparedIntentManager
    ) async throws -> PreparedIntent {
        try await manager.create(
            draft(
                for: preflight
            )
        )
    }
}

private extension FileMutationIntentBuilder {
    func summary(
        for preflight: AgentFileMutationPreflight
    ) -> String {
        var lines: [String] = [
            "Stage a file mutation \(preflight.action.rawValue) intent for '\(preflight.targetPath)'.",
            "",
            "This prepared intent is review-only. It does not execute the file mutation."
        ]

        lines.append(
            "Root: \(preflight.rootID.rawValue)"
        )
        lines.append(
            "Backup policy: \(preflight.backupPolicy.rawValue)"
        )
        lines.append(
            "Payload policy: \(preflight.payloadPolicy.rawValue)"
        )

        if let diffPreview = preflight.diffPreview {
            lines.append(
                "Diff preview: \(diffPreview.layout.changes.insertions.count) insertion(s), \(diffPreview.layout.changes.deletions.count) deletion(s)."
            )
        } else {
            lines.append(
                "Diff preview: unavailable."
            )
        }

        if preflight.willRecordSessionMutation {
            lines.append(
                "Execution is expected to record an AgentFileMutationRecord."
            )
        } else {
            lines.append(
                "Execution is not expected to record an Agentic mutation record unless an executor attaches a recorder."
            )
        }

        if preflight.willStoreBackupPayload {
            lines.append(
                "Execution is expected to store backup payloads in session mutation storage."
            )
        }

        if preflight.willEmitDiffArtifact {
            lines.append(
                "Execution may emit a diff artifact."
            )
        }

        return lines.joined(
            separator: "\n"
        )
    }

    func reviewMetadata(
        for preflight: AgentFileMutationPreflight
    ) -> [String: String] {
        let metadata = [
            "kind": "file_mutation_prepared_intent",
            "root_id": preflight.rootID.rawValue,
            "path": preflight.path,
            "target_path": preflight.targetPath,
            "backup_policy": preflight.backupPolicy.rawValue,
            "payload_policy": preflight.payloadPolicy.rawValue,
            "will_record_session_mutation": String(
                preflight.willRecordSessionMutation
            ),
            "will_store_backup_payload": String(
                preflight.willStoreBackupPayload
            ),
            "will_emit_diff_artifact": String(
                preflight.willEmitDiffArtifact
            )
        ]

        return metadata
    }

    func draftMetadata(
        for preflight: AgentFileMutationPreflight
    ) -> [String: String] {
        let metadata = [
            "kind": "file_mutation_prepared_intent",
            "root_id": preflight.rootID.rawValue,
            "path": preflight.path,
            "target_path": preflight.targetPath,
            "action": preflight.action.rawValue
        ]

        return metadata
    }
}
