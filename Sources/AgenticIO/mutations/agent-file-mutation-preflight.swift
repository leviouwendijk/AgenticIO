import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Path
import Writers

public enum FileMutationIntentAction: String, Sendable, Codable, Hashable, CaseIterable {
    case write
    case edit
    case rollback
}

public extension FileMutationIntentAction {
    var authorizationToolName: String {
        switch self {
        case .write,
             .edit:
            return MutateFilesTool.identifier.rawValue

        case .rollback:
            return "rollback_file_mutation"
        }
    }

    var title: String {
        switch self {
        case .write:
            return "Write file"

        case .edit:
            return "Edit file"

        case .rollback:
            return "Rollback file mutation"
        }
    }
}

public struct AgentFileMutationPreflight: Sendable, Codable, Hashable {
    public let action: FileMutationIntentAction
    public let rootID: PathAccessRootIdentifier
    public let path: String
    public let targetPath: String
    public let risk: ActionRisk
    public let backupPolicy: AgentFileBackupPolicy
    public let payloadPolicy: WriteMutationPayloadPolicy
    public let willRecordSessionMutation: Bool
    public let willStoreBackupPayload: Bool
    public let willEmitDiffArtifact: Bool
    public let diffPreview: ToolPreflightDiffPreview?
    public let estimatedByteCount: Int?
    public let estimatedWriteCount: Int
    public let estimatedChangedLineCount: Int?
    public let sideEffects: [String]
    public let policyChecks: [String]
    public let warnings: [String]
    public let operation: PreparedOperation.Envelope
    public let toolPreflight: ToolPreflight

    public init(
        action: FileMutationIntentAction,
        rootID: PathAccessRootIdentifier,
        path: String,
        targetPath: String,
        risk: ActionRisk,
        backupPolicy: AgentFileBackupPolicy,
        payloadPolicy: WriteMutationPayloadPolicy,
        willRecordSessionMutation: Bool,
        willStoreBackupPayload: Bool,
        willEmitDiffArtifact: Bool,
        diffPreview: ToolPreflightDiffPreview?,
        estimatedByteCount: Int?,
        estimatedWriteCount: Int,
        estimatedChangedLineCount: Int?,
        sideEffects: [String],
        policyChecks: [String],
        warnings: [String],
        operation: PreparedOperation.Envelope,
        toolPreflight: ToolPreflight
    ) {
        self.action = action
        self.rootID = rootID
        self.path = path
        self.targetPath = targetPath
        self.risk = risk
        self.backupPolicy = backupPolicy
        self.payloadPolicy = payloadPolicy
        self.willRecordSessionMutation = willRecordSessionMutation
        self.willStoreBackupPayload = willStoreBackupPayload
        self.willEmitDiffArtifact = willEmitDiffArtifact
        self.diffPreview = diffPreview
        self.estimatedByteCount = estimatedByteCount
        self.estimatedWriteCount = max(
            0,
            estimatedWriteCount
        )
        self.estimatedChangedLineCount = estimatedChangedLineCount.map {
            max(
                0,
                $0
            )
        }
        self.sideEffects = sideEffects
        self.policyChecks = policyChecks
        self.warnings = warnings
        self.operation = operation
        self.toolPreflight = toolPreflight
    }
}

public extension AgentFileMutationPreflight {
    /// Typed request used to prepare one whole-file replacement.
    ///
    /// The durable prepared operation stores the resulting Writers plan, not this request.
    struct WriteRequest: Sendable, Codable, Hashable {
        public let rootID: PathAccessRootIdentifier
        public let path: String
        public let content: String

        public init(
            rootID: PathAccessRootIdentifier = .project,
            path: String,
            content: String
        ) {
            self.rootID = rootID
            self.path = path
            self.content = content
        }
    }
}

public extension AgentFileMutationPreflight {
    static func write(
        _ input: WriteRequest,
        workspace: AgentWorkspace?,
        recorder: AgentFileMutationRecorder? = nil
    ) async throws -> Self {
        let mutationInput = MutateFilesToolInput(
            reason: "Prepare one whole-file replacement.",
            rootID: input.rootID,
            entries: [
                .init(
                    kind: .replace_text,
                    path: input.path,
                    content: input.content
                ),
            ]
        )
        let preparation = try await MutateFilesTool().prepare(
            mutationInput,
            context: .init(
                workspace: workspace
            )
        )
        let targetPath = preparation.preflight.targetPaths.first
            ?? input.path
        let operation = try PreparedFileMutationOperation.envelope(
            .init(
                action: .write,
                work: .mutation(
                    plan: preparation.plan,
                    failurePolicy: mutationInput.failurePolicy
                ),
                authorizations: [
                    .init(
                        rootID: input.rootID,
                        path: input.path,
                        targetPath: targetPath
                    ),
                ]
            )
        )

        return Self(
            action: .write,
            rootID: input.rootID,
            path: input.path,
            operation: operation,
            toolPreflight: preparation.preflight,
            recorder: recorder
        )
    }

    static func edit(
        _ input: FileEditRequest,
        workspace: AgentWorkspace?,
        recorder: AgentFileMutationRecorder? = nil
    ) async throws -> Self {
        let mutationInput = MutateFilesToolInput(
            reason: "Prepare one structured file edit.",
            rootID: input.rootID,
            entries: [
                .init(
                    kind: .edit_text,
                    path: input.path,
                    operations: input.operations
                ),
            ]
        )
        let preparation = try await MutateFilesTool().prepare(
            mutationInput,
            context: .init(
                workspace: workspace
            )
        )
        let targetPath = preparation.preflight.targetPaths.first
            ?? input.path
        let operation = try PreparedFileMutationOperation.envelope(
            .init(
                action: .edit,
                work: .mutation(
                    plan: preparation.plan,
                    failurePolicy: mutationInput.failurePolicy
                ),
                authorizations: [
                    .init(
                        rootID: input.rootID,
                        path: input.path,
                        targetPath: targetPath
                    ),
                ]
            )
        )

        return Self(
            action: .edit,
            rootID: input.rootID,
            path: input.path,
            operation: operation,
            toolPreflight: preparation.preflight,
            recorder: recorder
        )
    }
}

private extension AgentFileMutationPreflight {
    init(
        action: FileMutationIntentAction,
        rootID: PathAccessRootIdentifier,
        path: String,
        operation: PreparedOperation.Envelope,
        toolPreflight: ToolPreflight,
        recorder: AgentFileMutationRecorder?
    ) {
        let policy = recorder?.policy
        let backupPolicy = policy?.backupPolicy ?? .none
        let payloadPolicy = policy?.payloadPolicy ?? .metadata_only
        let willRecordSessionMutation = recorder != nil
        let willStoreBackupPayload = backupPolicy == .session_store || backupPolicy == .both
        let willEmitDiffArtifact = policy?.emitDiffArtifact ?? false
        let targetPath = toolPreflight.targetPaths.first ?? path

        let policyChecks = Self.policyChecks(
            from: toolPreflight,
            willRecordSessionMutation: willRecordSessionMutation,
            willStoreBackupPayload: willStoreBackupPayload,
            willEmitDiffArtifact: willEmitDiffArtifact
        )

        self.init(
            action: action,
            rootID: rootID,
            path: path,
            targetPath: targetPath,
            risk: toolPreflight.risk,
            backupPolicy: backupPolicy,
            payloadPolicy: payloadPolicy,
            willRecordSessionMutation: willRecordSessionMutation,
            willStoreBackupPayload: willStoreBackupPayload,
            willEmitDiffArtifact: willEmitDiffArtifact,
            diffPreview: toolPreflight.diffPreview,
            estimatedByteCount: toolPreflight.estimatedByteCount ?? toolPreflight.estimatedWriteBytes,
            estimatedWriteCount: toolPreflight.estimatedWriteCount,
            estimatedChangedLineCount: toolPreflight.estimatedChangedLineCount,
            sideEffects: Self.sideEffects(
                from: toolPreflight,
                willRecordSessionMutation: willRecordSessionMutation,
                willStoreBackupPayload: willStoreBackupPayload,
                willEmitDiffArtifact: willEmitDiffArtifact
            ),
            policyChecks: policyChecks,
            warnings: Self.warnings(
                from: toolPreflight,
                recorder: recorder
            ),
            operation: operation,
            toolPreflight: toolPreflight
        )
    }

    static func sideEffects(
        from preflight: ToolPreflight,
        willRecordSessionMutation: Bool,
        willStoreBackupPayload: Bool,
        willEmitDiffArtifact: Bool
    ) -> [String] {
        var values = preflight.sideEffects

        if willRecordSessionMutation {
            values.append(
                "records AgentFileMutationRecord in the session mutation store"
            )
        } else {
            values.append(
                "does not record a session mutation because no recorder is attached"
            )
        }

        if willStoreBackupPayload {
            values.append(
                "stores backup payload through the session mutation backup store"
            )
        }

        if willEmitDiffArtifact {
            values.append(
                "may emit a diff artifact for review"
            )
        }

        return uniqued(
            values
        )
    }

    static func policyChecks(
        from preflight: ToolPreflight,
        willRecordSessionMutation: Bool,
        willStoreBackupPayload: Bool,
        willEmitDiffArtifact: Bool
    ) -> [String] {
        var values = preflight.policyChecks

        values.append(
            "file_mutation_preflight_only"
        )
        values.append(
            "prepared_operation_plan_captured"
        )

        if preflight.diffPreview != nil {
            values.append(
                "diff_preview_generated"
            )
        }

        if willRecordSessionMutation {
            values.append(
                "session_mutation_recording_configured"
            )
        }

        if willStoreBackupPayload {
            values.append(
                "session_backup_payload_configured"
            )
        }

        if willEmitDiffArtifact {
            values.append(
                "diff_artifact_emission_configured"
            )
        }

        return uniqued(
            values
        )
    }

    static func warnings(
        from preflight: ToolPreflight,
        recorder: AgentFileMutationRecorder?
    ) -> [String] {
        var values = preflight.warnings

        if recorder == nil {
            values.append(
                "No AgentFileMutationRecorder is attached; execution would mutate the file without durable Agentic mutation storage."
            )
        }

        if preflight.diffPreview == nil {
            values.append(
                "No diff preview was generated for this file mutation preflight."
            )
        }

        return uniqued(
            values
        )
    }

    static func uniqued(
        _ values: [String]
    ) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []

        for value in values {
            guard !seen.contains(value) else {
                continue
            }

            seen.insert(
                value
            )
            out.append(
                value
            )
        }

        return out
    }
}
