import Foundation
import Workspace
import Writers

/// Publication of an already reviewed StandardMutationPlan. Callers must
/// reauthorize their inputs and targets against the current WorkspaceContext
/// before invoking this API. No planning, diffing or compiler work happens here.
public enum PreparedWritersPublication: Sendable {
    case applied(StandardMutationResult)
    case staged(UUID)
}

public struct PreparedWritersPublisher: Sendable {
    public init() {}

    public func publish(
        _ plan: StandardMutationPlan,
        in workspace: WorkspaceContext,
        using writer: WorkspaceWriter,
        failure: StandardMutationFailurePolicy = .rollback_applied
    ) async throws -> PreparedWritersPublication {
        switch workspace.execution.mutations {
        case .immediate:
            return .applied(writer.mutations.apply(
                plan,
                options: .init(failure: failure)
            ))
        case .coordinated(let submission):
            do {
                let admitted = try await submission.submit(plan, in: workspace)
                // The owner may grant publication on submit; otherwise the
                // submission stays staged under its claims.
                if let publication = try await submission.publish(admitted) {
                    return .applied(publication.result)
                }
                return .staged(admitted.id)
            } catch StandardMutationCoordinationError.requires_recovery {
                throw PreparedWritersPublicationError.recovery_required(
                    await submission.recoveryCause(),
                    canRequest: submission.canRequestRecovery
                )
            }
        }
    }
}

public enum PreparedWritersPublicationError: Error, Sendable, LocalizedError {
    /// The coordinator refuses changes until a failed publication is recovered.
    case recovery_required(StandardMutationRecoveryCause?, canRequest: Bool)

    public var errorDescription: String? {
        switch self {
        case .recovery_required(let cause, let canRequest):
            var text = "File changes are blocked: an earlier"
            if let cause {
                text += " \(cause.kind.rawValue) failed (\(cause.status))"
                if let target = cause.target {
                    text += " at \(target.path)"
                }
                if let message = cause.message {
                    text += ": \(message)"
                }
            } else {
                text += " publication failed"
            }
            text += ". Its effect on disk is uncertain. "
            text += canRequest
                ? "Inspect that target, then call io_tool_recover_mutations with what you found; the operator reviews it."
                : "Ask the operator to recover before making further changes."
            return text
        }
    }
}
