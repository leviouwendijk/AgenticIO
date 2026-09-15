import AgenticExecution
import AgenticWorkspace
import Foundation
import Path
import Primitives
import Version

public enum PreparedPathGrantOperation {
    public static let schema = PreparedOperation.Schema(
        identifier: "path_grant",
        version: ObjectVersion(
            major: 0,
            minor: 1,
            patch: 0
        )
    )

    public struct Plan: Sendable, Codable, Hashable {
        public let rootID: PathAccessRootIdentifier
        public let label: String
        public let requestedRootPath: String
        public let mode: PathGrantMode
        public let capabilities: [PathCapability]
        public let allowedTools: [String]
        public let reason: String
        public let policyProfile: String
        public let lifetimeSeconds: TimeInterval?

        public init(
            rootID: PathAccessRootIdentifier,
            label: String,
            requestedRootPath: String,
            mode: PathGrantMode,
            capabilities: [PathCapability],
            allowedTools: [String],
            reason: String,
            policyProfile: String,
            lifetimeSeconds: TimeInterval? = nil
        ) {
            self.rootID = rootID
            self.label = label
            self.requestedRootPath = requestedRootPath
            self.mode = mode
            self.capabilities = capabilities
            self.allowedTools = allowedTools
            self.reason = reason
            self.policyProfile = policyProfile
            self.lifetimeSeconds = lifetimeSeconds
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
