import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Primitives
import Schema

/// Model-facing input for Inspect fileMutation.
@JSONSchema
public struct InspectFileMutationToolInput: Sendable, Codable, Hashable {
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

public struct InspectFileMutationTool: TypedInstanceAgentTool {
    public typealias Input = InspectFileMutationToolInput

    public static let identifier: AgentToolIdentifier = .inspect_file_mutation
    public static let description = "Inspect one recorded file mutation and optionally load its diff artifact."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }


    public var risk: ActionRisk {
        Self.risk
    }

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
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            InspectFileMutationToolInput.self,
            from: input
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: """
            Inspect recorded file mutation \(decoded.id).
            loadDiffArtifact: \(decoded.loadDiffArtifact)
            """,
            estimatedRuntimeSeconds: 1,
            sideEffects: []
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        _ = workspace

        let decoded = try JSONToolBridge.decode(
            InspectFileMutationToolInput.self,
            from: input
        )
        let history = AgentFileMutationHistory(
            store: store,
            artifactStore: artifactStore
        )
        let inspection = try await history.inspect(
            id: decoded.id,
            loadDiffArtifact: decoded.loadDiffArtifact
        )

        return try JSONToolBridge.encode(
            inspection
        )
    }
}
