import AgenticExecution
import Foundation
import Path
import Primitives
import Version
import Writers

public enum PreparedFileMutationOperation {
    public static let schema = PreparedOperation.Schema(
        identifier: "file_mutation",
        version: ObjectVersion(
            major: 0,
            minor: 1,
            patch: 0
        )
    )

    public struct Authorization: Sendable, Codable, Hashable {
        public let rootID: PathAccessRootIdentifier
        public let path: String
        public let targetPath: String

        public init(
            rootID: PathAccessRootIdentifier,
            path: String,
            targetPath: String
        ) {
            self.rootID = rootID
            self.path = path
            self.targetPath = targetPath
        }
    }

    public enum Work: Sendable, Codable, Hashable {
        case mutation(
            plan: StandardMutationPlan,
            failurePolicy: StandardMutationFailurePolicy
        )
        case rollback(
            plan: WriteMutationRollbackPlan,
            sourceMutationID: UUID
        )
    }

    public struct Plan: Sendable, Codable, Hashable {
        public let action: FileMutationIntentAction
        public let work: Work
        public let authorizations: [Authorization]

        public init(
            action: FileMutationIntentAction,
            work: Work,
            authorizations: [Authorization]
        ) {
            self.action = action
            self.work = work
            self.authorizations = authorizations
        }
    }

    public static func envelope(
        _ plan: Plan
    ) throws -> PreparedOperation.Envelope {
        .init(
            schema: schema,
            plan: try JSONValue.encoding(
                plan
            )
        )
    }

    public static func plan(
        from envelope: PreparedOperation.Envelope
    ) throws -> Plan {
        guard envelope.schema == schema else {
            throw PreparedOperation.EnvelopeError.schema_mismatch(
                expected: schema,
                actual: envelope.schema
            )
        }

        return try envelope.plan.decode(
            Plan.self
        )
    }
}
