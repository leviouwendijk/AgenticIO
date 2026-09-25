import Agentic
import AgenticExecution
import Workspace
import Foundation
import Primitives
import Schema
import Macros


public extension SystemIO.Tools {
    @Tool
    struct InspectFileMutation: Tool {
        /// Model-facing input for Inspect fileMutation.
        @JSONSchema
        public struct Input: HashableSource {
            /// Exact recorded mutation identifier.
            public let id: String
            /// Whether to load the referenced diff artifact when available.
            public let loadDiffArtifact: Bool

            public init(
                id: String,
                loadDiffArtifact: Bool = true
            ) {
                self.id = id
                self.loadDiffArtifact = loadDiffArtifact
            }
        }

        public typealias Output = AgentFileMutationInspection

        public static let purpose = "Inspect one recorded file mutation and optionally load its diff artifact."
        public static let risk: ActionRisk = .observe

        public let store: any AgentFileMutationStore
        public let artifactStore: (any AgentArtifactStore)?

        public init(
            store: any AgentFileMutationStore,
            artifactStore: (any AgentArtifactStore)? = nil
        ) {
            self.store = store
            self.artifactStore = artifactStore
        }

        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: """
                Inspect recorded file mutation \(input.id).
                loadDiffArtifact: \(input.loadDiffArtifact)
                """,
                estimates: .init(
                    runtime: 1
                ),
                sideEffects: []
            )
        }

        public func call(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> Output {
            let history = AgentFileMutationHistory(
                store: store,
                artifactStore: artifactStore
            )
            let inspection = try await history.inspect(
                id: input.id,
                loadDiffArtifact: input.loadDiffArtifact
            )

            return inspection
            
        }
    }
}
