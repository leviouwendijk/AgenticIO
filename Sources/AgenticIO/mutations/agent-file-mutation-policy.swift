import Foundation
import Writers

public enum AgentFileBackupPolicy: String, Sendable, Codable, Hashable, CaseIterable {
    case none
    case session_store
    case local_backupdir
    case both
}

public struct AgentFileMutationPolicy: Sendable, Codable, Hashable {
    public var backupPolicy: AgentFileBackupPolicy
    public var payloadPolicy: WriteMutationPayloadPolicy
    public var emitDiffArtifact: Bool
    public var stalePlanPolicy: WriteExecutionStalePlanPolicy

    public init(
        backupPolicy: AgentFileBackupPolicy,
        payloadPolicy: WriteMutationPayloadPolicy,
        emitDiffArtifact: Bool,
        stalePlanPolicy: WriteExecutionStalePlanPolicy = .require_current_matches_plan
    ) {
        self.backupPolicy = backupPolicy
        self.payloadPolicy = payloadPolicy
        self.emitDiffArtifact = emitDiffArtifact
        self.stalePlanPolicy = stalePlanPolicy
    }

    public static let normal = Self(
        backupPolicy: .session_store,
        payloadPolicy: .external_content,
        emitDiffArtifact: true
    )

    public static let scratch = Self(
        backupPolicy: .none,
        payloadPolicy: .metadata_only,
        emitDiffArtifact: false
    )

    public static let paranoid = Self(
        backupPolicy: .both,
        payloadPolicy: .external_content,
        emitDiffArtifact: true
    )
}

public extension AgentFileMutationPolicy {
    func writeOptions() -> SafeWriteOptions {
        var options: SafeWriteOptions

        switch backupPolicy {
        case .none:
            options = .overwriteWithoutBackup

        case .session_store:
            options = .overwriting(
                backupPolicy: .external_store,
                maxBackupSets: nil
            )

        case .local_backupdir:
            options = .overwriting(
                backupPolicy: .backup_directory,
                maxBackupSets: 10
            )

        case .both:
            options = .overwriting(
                backupPolicy: .external_store,
                maxBackupSets: nil
            )
        }

        options.stalePlanPolicy = stalePlanPolicy

        return options
    }
}
