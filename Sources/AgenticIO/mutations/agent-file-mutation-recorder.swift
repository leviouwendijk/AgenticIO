import Agentic
import AgenticWorkspace
import Difference
import Foundation
import Path
import Writers

public struct AgentFileMutationRecorder: Sendable {
    public let sessionID: String
    public let store: any AgentFileMutationStore
    public let artifacts: (any AgentArtifactStore)?
    public let backups: (any WriteBackupStore)?
    public let policy: AgentFileMutationPolicy

    public init(
        sessionID: String,
        store: any AgentFileMutationStore,
        artifacts: (any AgentArtifactStore)? = nil,
        backups: (any WriteBackupStore)? = nil,
        policy: AgentFileMutationPolicy = .normal
    ) {
        self.sessionID = sessionID
        self.store = store
        self.artifacts = artifacts
        self.backups = backups
        self.policy = policy
    }

    public func writeOptions() throws -> SafeWriteOptions {
        try policy.writeOptions(
            backupStore: backups
        )
    }

    public func record(
        editResult: StandardEditResult,
        operationKind: WriteMutationOperationKind,
        rootID: PathAccessRootIdentifier? = nil,
        scopedPath: ScopedPath? = nil,
        context: AgentFileMutationContext = .empty
    ) async throws -> AgentFileMutationResult {
        let writerRecord = editResult.mutationRecord(
            operationKind: operationKind,
            storeContent: true,
            metadata: context.metadata
        )

        return try await record(
            writerRecord: writerRecord,
            editResult: editResult,
            writeResult: editResult.writeResult,
            rootID: rootID ?? context.rootID,
            scopedPath: scopedPath,
            context: context
        )
    }

    public func record(
        writerRecord: WriteMutationRecord,
        editResult: StandardEditResult? = nil,
        writeResult: SafeWriteResult? = nil,
        rootID: PathAccessRootIdentifier? = nil,
        scopedPath: ScopedPath? = nil,
        context: AgentFileMutationContext = .empty
    ) async throws -> AgentFileMutationResult {
        let emitted = try await emitDiffArtifact(
            for: writerRecord,
            rootID: rootID ?? context.rootID,
            scopedPath: scopedPath,
            metadata: context.metadata
        )

        let draft = AgentFileMutationDraft(
            sessionID: sessionID,
            toolCallID: context.toolCallID,
            preparedIntentID: context.preparedIntentID,
            rootID: rootID ?? context.rootID,
            scopedPath: scopedPath,
            writerRecord: writerRecord,
            artifactIDs: emitted.map(\.id),
            metadata: context.metadata
        )

        let saved = try await store.save(
            draft,
            payloadPolicy: policy.payloadPolicy
        )

        return .init(
            mutation: saved,
            writerRecord: writerRecord,
            writeResult: writeResult,
            editResult: editResult,
            artifacts: emitted
        )
    }
}

private extension AgentFileMutationRecorder {
    func emitDiffArtifact(
        for record: WriteMutationRecord,
        rootID: PathAccessRootIdentifier?,
        scopedPath: ScopedPath?,
        metadata: [String: String]
    ) async throws -> [AgentArtifact] {
        guard policy.emitDiffArtifact,
              let artifacts,
              let before = record.before?.content,
              let after = record.after?.content
        else {
            return []
        }

        let oldName = "a/\(displayPath(record: record, scopedPath: scopedPath))"
        let newName = "b/\(displayPath(record: record, scopedPath: scopedPath))"

        let difference = TextDiffer.diff(
            old: before,
            new: after,
            oldName: oldName,
            newName: newName
        )

        guard difference.hasChanges else {
            return []
        }

        let rendered = DifferenceRenderer.plain(
            difference,
            options: .unified
        )

        guard !rendered.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return []
        }

        let artifact = try await artifacts.emit(
            .init(
                kind: .diff,
                title: "File mutation diff",
                filename: diffFilename(
                    record: record
                ),
                contentType: AgentArtifactKind.diff.defaultContentType,
                content: rendered,
                metadata: artifactMetadata(
                    record: record,
                    rootID: rootID,
                    scopedPath: scopedPath,
                    metadata: metadata
                )
            )
        )

        return [
            artifact.artifact
        ]
    }

    func artifactMetadata(
        record: WriteMutationRecord,
        rootID: PathAccessRootIdentifier?,
        scopedPath: ScopedPath?,
        metadata: [String: String]
    ) -> [String: String] {
        var out = metadata

        out["session_id"] = sessionID
        out["writer_record_id"] = record.id.uuidString.lowercased()
        out["target"] = record.target.path
        out["operation_kind"] = record.operationKind.rawValue
        out["resource"] = record.surface.resource.rawValue
        out["delta"] = record.surface.delta.rawValue

        if let rootID {
            out["root_id"] = rootID.rawValue
        }

        if let scopedPath {
            out["scoped_path"] = scopedPath.presentingRelative(
                filetype: true
            )
        }

        return out
    }

    func diffFilename(
        record: WriteMutationRecord
    ) -> String {
        "\(safeFileComponent(record.target.lastPathComponent)).\(record.id.uuidString.lowercased()).diff"
    }

    func displayPath(
        record: WriteMutationRecord,
        scopedPath: ScopedPath?
    ) -> String {
        scopedPath?.presentingRelative(
            filetype: true
        ) ?? record.target.lastPathComponent
    }

    func safeFileComponent(
        _ value: String
    ) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let mapped = trimmed.map { character -> Character in
            if character.isLetter
                || character.isNumber
                || character == "-"
                || character == "_"
                || character == "." {
                return character
            }

            return "-"
        }

        let out = String(
            mapped
        )

        return out.isEmpty ? "mutation" : out
    }
}
