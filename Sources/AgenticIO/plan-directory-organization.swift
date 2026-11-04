import Agentic
import Macros
import Schema

public extension SystemIO {
    @JSONSchema
    struct DirectoryMove: HashableProduct {
        public let source: String
        public let destination: String
        public let reason: String

        public init(
            source: String,
            destination: String,
            reason: String
        ) {
            self.source = source
            self.destination = destination
            self.reason = reason
        }
    }
}

public extension SystemIO.Inferences {
    @Inference
    struct PlanDirectoryOrganization {
        @JSONSchema
        public struct Input: HashableSource {
            public let objective: String
            public let path: String
            public let observedPaths: [String]
            public let desiredStructure: String?
            public let constraints: [String]

            public init(
                objective: String,
                path: String,
                observedPaths: [String],
                desiredStructure: String? = nil,
                constraints: [String] = []
            ) {
                self.objective = objective
                self.path = path
                self.observedPaths = observedPaths
                self.desiredStructure = desiredStructure
                self.constraints = constraints
            }
        }

        @JSONSchema
        public struct Output: HashableResult {
            public let moves: [SystemIO.DirectoryMove]
            public let assumptions: [String]
            public let conflicts: [String]
            public let verification: [String]

            public init(
                moves: [SystemIO.DirectoryMove],
                assumptions: [String] = [],
                conflicts: [String] = [],
                verification: [String] = []
            ) {
                self.moves = moves
                self.assumptions = assumptions
                self.conflicts = conflicts
                self.verification = verification
            }
        }

        public static let purpose = """
        Propose a bounded, explicit directory relocation plan from observed paths,
        a caller-supplied organization objective, and caller-supplied constraints.
        Identify ambiguities and collisions; do not infer that moves have executed.
        """
    }
}
