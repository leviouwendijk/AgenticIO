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
            let admitted = try await submission.submit(plan, in: workspace)
            // The owner may grant publication on submit; otherwise the
            // submission stays staged under its claims.
            if let publication = try await submission.publish(admitted) {
                return .applied(publication.result)
            }
            return .staged(admitted.id)
        }
    }
}
