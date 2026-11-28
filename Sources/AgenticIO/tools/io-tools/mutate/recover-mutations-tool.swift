import Agentic
import Foundation
import Schema
import Macros
import Workspace
import Writers

public enum RecoverMutationsToolError: Error, Sendable, LocalizedError {
    case not_coordinated
    case not_granted
    case nothing_to_recover

    public var errorDescription: String? {
        switch self {
        case .not_coordinated:
            return "File changes in this workspace are applied directly; there is nothing to recover."
        case .not_granted:
            return "This session cannot request mutation recovery; ask the operator."
        case .nothing_to_recover:
            return "File changes are not blocked; nothing to recover."
        }
    }
}

public extension SystemIO.Tools {
    @Tool("recover_mutations")
    struct RecoverMutations: Tool {
        /// Ask the operator to unblock file changes after a failed publication.
        @JSONSchema
        public struct Input: HashableSource {
            /// What you checked on disk and why it is safe to continue.
            public let reason: String

            public init(
                reason: String
            ) {
                self.reason = reason
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let recovered: Bool
            public let publicationID: UUID?

            public init(
                recovered: Bool,
                publicationID: UUID?
            ) {
                self.recovered = recovered
                self.publicationID = publicationID
            }
        }

        public static let purpose = """
        After mutate refuses with "needs recovery", inspect the failed target on disk, then ask the operator to unblock file changes. Always reviewed.
        """

        /// Unblocking trusts the disk as it is now, so the operator always reviews it.
        public static let risk: ActionRisk = .privileged

        public init() {}

        public func preflight(
            _ input: Input,
            in context: CapabilityContext
        ) async throws -> ToolPreflight {
            let (_, cause) = try await blocked(in: context)
            let target = cause.target.map { relative($0, in: context) }

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "Unblock file changes after a failed \(cause.kind.rawValue) (\(cause.status))"
                    + (target.map { " at \($0)" } ?? "")
                    + ". Reason: \(input.reason)",
                access: .init(
                    targets: target.map { [$0] } ?? [],
                    roots: [],
                    capabilities: [.write]
                ),
                sideEffects: [
                    "Accepts the disk as it is now; nothing is rolled back or repaired.",
                    "Later file changes publish again.",
                ],
                policyChecks: [
                    "workspace_required",
                    "coordinated_mutations",
                    "recovery_granted",
                    "coordinator_blocked",
                ],
                warnings: cause.message.map { ["failure: \($0)"] } ?? []
            )
        }

        public func call(
            _ input: Input,
            in context: CapabilityContext
        ) async throws -> Output {
            let (submission, cause) = try await blocked(in: context)
            let recovered = try await submission.recover()
            return .init(
                recovered: recovered,
                publicationID: cause.publication_id
            )
        }

        public func process(
            _ output: Output,
            input _: Input
        ) -> ToolExecution.Projection? {
            .init(
                status: output.recovered ? "recovered" : "not blocked",
                summary: output.recovered
                    ? "File changes are unblocked."
                    : "File changes were not blocked.",
                facts: []
            )
        }

        private func blocked(
            in context: CapabilityContext
        ) async throws -> (WorkspaceCoordinatedSubmission, StandardMutationRecoveryCause) {
            let workspace = try FileToolSupport.requireWorkspace(
                context.workspace,
                toolName: Self.identifier.rawValue
            )
            guard case .coordinated(let submission) = workspace.execution.mutations else {
                throw RecoverMutationsToolError.not_coordinated
            }
            guard submission.canRequestRecovery else {
                throw RecoverMutationsToolError.not_granted
            }
            guard let cause = await submission.recoveryCause() else {
                throw RecoverMutationsToolError.nothing_to_recover
            }
            return (submission, cause)
        }

        private func relative(
            _ url: URL,
            in context: CapabilityContext
        ) -> String {
            guard let root = context.workspace?.rootURL.standardizedFileURL.path else {
                return url.path
            }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root + "/") else {
                return path
            }
            return String(path.dropFirst(root.count + 1))
        }
    }
}
