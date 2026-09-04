import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Path
import Primitives
import Writers

public enum FileMutationIntentAction: String, Sendable, Codable, Hashable, CaseIterable {
    case write
    case edit
    case rollback
}

public extension FileMutationIntentAction {
    var actionType: String {
        "file_mutation.\(rawValue)"
    }

    init?(
        actionType: String
    ) {
        let prefix = "file_mutation."

        guard actionType.hasPrefix(prefix) else {
            return nil
        }

        self.init(
            rawValue: String(
                actionType.dropFirst(prefix.count)
            )
        )
    }

    var toolName: String {
        switch self {
        case .write:
            return WriteFileTool.identifier.rawValue

        case .edit:
            return EditFileTool.identifier.rawValue

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
    public let exactReplayInput: JSONValue
    public let originalFingerprint: StandardContentFingerprint?
    public let editedFingerprint: StandardContentFingerprint?
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
        exactReplayInput: JSONValue,
        originalFingerprint: StandardContentFingerprint? = nil,
        editedFingerprint: StandardContentFingerprint? = nil,
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
        self.exactReplayInput = exactReplayInput
        self.originalFingerprint = originalFingerprint
        self.editedFingerprint = editedFingerprint
        self.toolPreflight = toolPreflight
    }
}

public extension AgentFileMutationPreflight {
    static func write(
        _ input: WriteFileToolInput,
        workspace: AgentWorkspace?,
        recorder: AgentFileMutationRecorder? = nil
    ) async throws -> Self {
        let exactInput = try JSONToolBridge.encode(
            input
        )
        let tool = WriteFileTool(
            recorder: recorder
        )
        let toolPreflight = try await tool.preflight(
            input,
            context: .init(
                workspace: workspace
            )
        )
        let preview = try Self.preview(
            input,
            workspace: workspace
        )

        return Self(
            action: .write,
            rootID: input.rootID,
            path: input.path,
            exactInput: exactInput,
            toolPreflight: toolPreflight,
            recorder: recorder,
            preview: preview
        )
    }

    static func edit(
        _ input: EditFileToolInput,
        workspace: AgentWorkspace?,
        recorder: AgentFileMutationRecorder? = nil
    ) async throws -> Self {
        let exactInput = try JSONToolBridge.encode(
            input
        )
        let tool = EditFileTool(
            recorder: recorder
        )
        let toolPreflight = try await tool.preflight(
            input,
            context: .init(
                workspace: workspace
            )
        )
        let preview = try Self.preview(
            input,
            workspace: workspace
        )

        return Self(
            action: .edit,
            rootID: input.rootID,
            path: input.path,
            exactInput: exactInput,
            toolPreflight: toolPreflight,
            recorder: recorder,
            preview: preview
        )
    }

    var approval: AgentFileMutationApproval? {
        guard let originalFingerprint else {
            return nil
        }

        return AgentFileMutationApproval(
            action: action,
            rootID: rootID,
            path: path,
            targetPath: targetPath,
            originalFingerprint: originalFingerprint,
            editedFingerprint: editedFingerprint
        )
    }
}

private extension AgentFileMutationPreflight {
    init(
        action: FileMutationIntentAction,
        rootID: PathAccessRootIdentifier,
        path: String,
        exactInput: JSONValue,
        toolPreflight: ToolPreflight,
        recorder: AgentFileMutationRecorder?,
        preview: StandardEditResult? = nil
    ) {
        let policy = recorder?.policy
        let backupPolicy = policy?.backupPolicy ?? .none
        let payloadPolicy = policy?.payloadPolicy ?? .metadata_only
        let willRecordSessionMutation = recorder != nil
        let willStoreBackupPayload = backupPolicy == .session_store || backupPolicy == .both
        let willEmitDiffArtifact = policy?.emitDiffArtifact ?? false
        let targetPath = toolPreflight.targetPaths.first ?? path

        var policyChecks = Self.policyChecks(
            from: toolPreflight,
            willRecordSessionMutation: willRecordSessionMutation,
            willStoreBackupPayload: willStoreBackupPayload,
            willEmitDiffArtifact: willEmitDiffArtifact
        )

        if preview?.originalFingerprint != nil {
            policyChecks.append(
                "approval_fingerprint_guard_captured"
            )
        }

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
            exactReplayInput: exactInput,
            originalFingerprint: preview?.originalFingerprint,
            editedFingerprint: preview?.editedFingerprint,
            toolPreflight: toolPreflight
        )
    }

    static func preview(
        _ input: WriteFileToolInput,
        workspace: AgentWorkspace?
    ) throws -> StandardEditResult? {
        guard let workspace else {
            return nil
        }

        let authorized = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: input.rootID,
            path: input.path,
            capability: .write,
            toolName: WriteFileTool.identifier.rawValue,
            type: .file
        )

        return try StandardWriter(
            authorized.absoluteURL
        )
        .editor
        .preview(
            .replaceEntireFile(
                with: input.content
            ),
            encoding: .utf8
        )
    }

    static func preview(
        _ input: EditFileToolInput,
        workspace: AgentWorkspace?
    ) throws -> StandardEditResult? {
        guard let workspace else {
            return nil
        }

        let plan = try EditFileIntentResolver(
            toolName: EditFileTool.identifier.rawValue
        )
        .resolve(
            input,
            workspace: workspace
        )

        return try StandardWriter(
            plan.authorized.absoluteURL
        )
        .editor
        .preview(
            plan.operations,
            mode: plan.editMode,
            encoding: .utf8
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
            "exact_replay_input_captured"
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
