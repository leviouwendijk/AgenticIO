import Agentic
import AgenticExecution
import Workspace
import Difference
import Foundation
import Path
import Primitives
import Schema
import Macros
import Writers

public enum AgentFileMutationRollbackError: Error, Sendable, LocalizedError {
    case invalidMutationID(String)
    case mutationNotFound(String)
    case mutationNotRollbackable(String)
    case missingWriterRecord(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMutationID(let id):
            return "Invalid file mutation rollback id '\(id)'."

        case .mutationNotFound(let id):
            return "No recorded file mutation exists for rollback id '\(id)'."

        case .mutationNotRollbackable(let id):
            return "Recorded file mutation '\(id)' is not rollbackable."

        case .missingWriterRecord(let id):
            return "Recorded file mutation '\(id)' is missing its canonical writer record."
        }
    }
}

/// Roll back one previously recorded file mutation.
@JSONSchema
public struct AgentFileMutationRollbackInput: Sendable, Codable, Hashable {
    /// Recorded mutation identifier to roll back.
    public let mutationID: String

    /// Verify that the current target still matches the recorded rollback guard. Defaults to true.
    @Schema(required: false)
    public let checkTarget: Bool

    public init(
        mutationID: String,
        checkTarget: Bool = true
    ) {
        self.mutationID = mutationID
        self.checkTarget = checkTarget
    }
}

private extension AgentFileMutationRollbackInput {
    enum CodingKeys: String, CodingKey {
        case mutationID
        case checkTarget
    }
}

public extension AgentFileMutationRollbackInput {
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self.init(
            mutationID: try container.decode(
                String.self,
                forKey: .mutationID
            ),
            checkTarget: try container.decodeIfPresent(
                Bool.self,
                forKey: .checkTarget
            ) ?? true
        )
    }
}

public struct AgentFileMutationRollbackOutput: Result, Hashable {
    public static var jsonschema: JSONSchema {
        .object()
    }

    public let sourceMutationID: UUID
    public let rollbackMutationID: UUID
    public let writerRecordID: UUID
    public let targetPath: String
    public let rollbackStrategy: WriteMutationRollbackStrategy
    public let artifactIDs: [String]

    public init(
        sourceMutationID: UUID,
        rollbackMutationID: UUID,
        writerRecordID: UUID,
        targetPath: String,
        rollbackStrategy: WriteMutationRollbackStrategy,
        artifactIDs: [String]
    ) {
        self.sourceMutationID = sourceMutationID
        self.rollbackMutationID = rollbackMutationID
        self.writerRecordID = writerRecordID
        self.targetPath = targetPath
        self.rollbackStrategy = rollbackStrategy
        self.artifactIDs = artifactIDs
    }
}

public extension AgentFileMutationPreflight {
    static func rollback(
        _ input: AgentFileMutationRollbackInput,
        store: any AgentFileMutationStore,
        workspace: WorkspaceContext?,
        recorder: AgentFileMutationRecorder? = nil
    ) async throws -> Self {
        let sourceID = try input.normalizedMutationUUID()
        let sourceIDString = sourceID.uuidString.lowercased()

        guard let mutation = try await store.load(
            id: sourceID
        ) else {
            throw AgentFileMutationRollbackError.mutationNotFound(
                sourceIDString
            )
        }

        guard mutation.rollbackable else {
            throw AgentFileMutationRollbackError.mutationNotRollbackable(
                sourceIDString
            )
        }

        guard let writerRecord = try await store.loadWriterRecord(
            for: mutation
        ) else {
            throw AgentFileMutationRollbackError.missingWriterRecord(
                sourceIDString
            )
        }

        let options = recorder?.writeOptions() ?? .overwriteWithoutBackup
        let plan = try StandardWriter(
            mutation.target
        ).rollbackPlan(
            writerRecord,
            options: options,
            checkTarget: input.checkTarget,
            context: recorder?.writeExecutionContext() ?? .init()
        )
        let diffPreview = rollbackDiffPreview(
            plan.preview,
            displayPath: mutation.relativePath ?? mutation.target.lastPathComponent
        )
        let policy = recorder?.policy
        let backupPolicy = policy?.backupPolicy ?? .none
        let payloadPolicy = policy?.payloadPolicy ?? .metadata_only
        let willRecordSessionMutation = recorder != nil
        let willStoreBackupPayload = backupPolicy == .session_store || backupPolicy == .both
        let willEmitDiffArtifact = policy?.emitDiffArtifact ?? false
        let targetPath = mutation.target.standardizedFileURL.path
        let rootID = mutation.rootID ?? .project
        let path = mutation.relativePath ?? mutation.target.lastPathComponent
        let operation = try PreparedFileMutationOperation.envelope(
            .init(
                action: .rollback,
                work: .rollback(
                    plan: plan,
                    sourceMutationID: sourceID
                ),
                authorizations: [
                    .init(
                        rootID: rootID,
                        path: path,
                        targetPath: targetPath
                    ),
                ]
            )
        )

        let sideEffects = rollbackSideEffects(
            willRecordSessionMutation: willRecordSessionMutation,
            willStoreBackupPayload: willStoreBackupPayload,
            willEmitDiffArtifact: willEmitDiffArtifact
        )
        let policyChecks = rollbackPolicyChecks(
            hasDiffPreview: diffPreview != nil,
            willRecordSessionMutation: willRecordSessionMutation,
            willStoreBackupPayload: willStoreBackupPayload,
            willEmitDiffArtifact: willEmitDiffArtifact
        )
        let warnings = rollbackWarnings(
            recorder: recorder,
            hasDiffPreview: diffPreview != nil
        )

        let rollbackBytes = Data(
            plan.preview.rollbackContent.utf8
        ).count
        let changedLineCount = diffPreview.map {
            $0.layout.changes.count
        }
        let toolPreflight = ToolPreflight(
            tool: .init(
                rawValue: FileMutationIntentAction.rollback.authorizationToolName
            ),
            risk: .boundedmutate,
            summary: """
            Roll back recorded file mutation \(sourceIDString).

            Target: \(targetPath)
            Strategy: \(plan.preview.strategy.rawValue)
            """,
            access: .init(
                targets: [
                    targetPath
                ],
                roots: [
                    rootID.rawValue
                ],
                capabilities: [
                    .write
                ]
            ),
            estimates: .init(
                write: .init(
                    count: 1,
                    bytes: rollbackBytes,
                    changedLines: changedLineCount
                ),
                bytes: rollbackBytes
            ),
            preview: .init(
                difference: diffPreview
            ),
            sideEffects: sideEffects,
            policyChecks: policyChecks,
            warnings: warnings
        )

        return .init(
            action: .rollback,
            rootID: rootID,
            path: path,
            targetPath: targetPath,
            risk: .boundedmutate,
            backupPolicy: backupPolicy,
            payloadPolicy: payloadPolicy,
            willRecordSessionMutation: willRecordSessionMutation,
            willStoreBackupPayload: willStoreBackupPayload,
            willEmitDiffArtifact: willEmitDiffArtifact,
            diffPreview: diffPreview,
            estimatedByteCount: rollbackBytes,
            estimatedWriteCount: 1,
            estimatedChangedLineCount: changedLineCount,
            sideEffects: sideEffects,
            policyChecks: policyChecks,
            warnings: warnings,
            operation: operation,
            toolPreflight: toolPreflight
        )
    }
}

public extension AgentFileMutationRollbackInput {
    func normalizedMutationUUID() throws -> UUID {
        let trimmed = mutationID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let id = UUID(
            uuidString: trimmed
        ) else {
            throw AgentFileMutationRollbackError.invalidMutationID(
                mutationID
            )
        }

        return id
    }
}

private func rollbackDiffPreview(
    _ preview: WriteMutationRollbackPreview,
    displayPath: String
) -> ToolPreflight.Preview.Difference? {
    let currentContent = preview.current.content ?? ""
    let rollbackContent = preview.rollbackContent

    let difference = TextDiffer.diff(
        old: currentContent,
        new: rollbackContent,
        oldName: "current/\(displayPath)",
        newName: "rollback/\(displayPath)"
    )

    guard difference.hasChanges else {
        return nil
    }

    let layout = DifferenceRenderer.layout(
        difference,
        options: .unified
    )

    guard !layout.isEmpty else {
        return nil
    }

    return .init(
        title: "Rollback preview for \(displayPath)",
        layout: layout
    )
}

private func rollbackSideEffects(
    willRecordSessionMutation: Bool,
    willStoreBackupPayload: Bool,
    willEmitDiffArtifact: Bool
) -> [String] {
    var values = [
        "writes rollback content to the target file"
    ]

    if willRecordSessionMutation {
        values.append(
            "records rollback as an AgentFileMutationRecord in the session mutation store"
        )
    } else {
        values.append(
            "does not record a session rollback mutation because no recorder is attached"
        )
    }

    if willStoreBackupPayload {
        values.append(
            "stores rollback backup payload through the session mutation backup store"
        )
    }

    if willEmitDiffArtifact {
        values.append(
            "may emit a diff artifact for the rollback"
        )
    }

    return rollbackUniqued(
        values
    )
}

private func rollbackPolicyChecks(
    hasDiffPreview: Bool,
    willRecordSessionMutation: Bool,
    willStoreBackupPayload: Bool,
    willEmitDiffArtifact: Bool
) -> [String] {
    var values = [
        "file_mutation_rollback_preflight_only",
        "rollback_source_mutation_loaded",
        "rollback_writer_record_loaded",
        "rollback_plan_generated",
        "exact_replay_input_captured"
    ]

    if hasDiffPreview {
        values.append(
            "rollback_diff_preview_generated"
        )
    }

    if willRecordSessionMutation {
        values.append(
            "session_rollback_mutation_recording_configured"
        )
    }

    if willStoreBackupPayload {
        values.append(
            "session_backup_payload_configured"
        )
    }

    if willEmitDiffArtifact {
        values.append(
            "rollback_diff_artifact_emission_configured"
        )
    }

    return rollbackUniqued(
        values
    )
}

private func rollbackWarnings(
    recorder: AgentFileMutationRecorder?,
    hasDiffPreview: Bool
) -> [String] {
    var values: [String] = []

    if recorder == nil {
        values.append(
            "No AgentFileMutationRecorder is attached; rollback execution would mutate the file without durable Agentic mutation storage."
        )
    }

    if !hasDiffPreview {
        values.append(
            "No diff preview was generated for this rollback preflight."
        )
    }

    return rollbackUniqued(
        values
    )
}

private func rollbackUniqued(
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
