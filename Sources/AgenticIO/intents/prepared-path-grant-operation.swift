import AgenticExecution
import AgenticWorkspace
import Foundation
import Primitives
import Version

public enum PreparedPathGrantOperation {
    public static let schema = PreparedOperation.Schema(
        identifier: "path_grant",
        version: ObjectVersion(
            major: 0,
            minor: 2,
            patch: 0
        )
    )

    public struct Plan: Sendable, Codable, Hashable {
        public let overlay: WorkspaceAccessOverlay
        public let lifetime: PathGrantLifetime
        public let durationSeconds: TimeInterval?

        public init(
            overlay: WorkspaceAccessOverlay,
            lifetime: PathGrantLifetime,
            durationSeconds: TimeInterval? = nil
        ) {
            self.overlay = overlay
            self.lifetime = lifetime
            self.durationSeconds = durationSeconds
        }
    }

    public static func envelope(
        _ plan: Plan
    ) throws -> PreparedOperation.Envelope {
        .init(
            schema: schema,
            plan: try JSONValueCodec.encodeValue(
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

        return try envelope.plan.as(
            Plan.self
        )
    }
}
