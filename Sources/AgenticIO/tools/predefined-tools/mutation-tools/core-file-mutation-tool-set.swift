import Agentic
import AgenticExecution

public struct CoreFileMutationHistoryToolSet: AgentToolSet {
    public let store: any AgentFileMutationStore
    public let recorder: AgentFileMutationRecorder
    public let artifactStore: (any AgentArtifactStore)?

    public init(
        store: any AgentFileMutationStore,
        recorder: AgentFileMutationRecorder,
        artifactStore: (any AgentArtifactStore)? = nil
    ) {
        self.store = store
        self.recorder = recorder
        self.artifactStore = artifactStore
    }

    public func register(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            ListFileMutationsTool(
                store: store
            )

            InspectFileMutationTool(
                store: store,
                artifactStore: artifactStore
            )

            RollbackFileMutationTool(
                store: store,
                recorder: recorder
            )
        }
    }
}
