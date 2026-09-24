import Agentic
import AgenticExecution

public struct CoreFileMutationHistoryToolSet: AgentToolProvider {
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

    public func registerTools(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            SystemIO.Tools.ListFileMutations(
                store: store
            )

            SystemIO.Tools.InspectFileMutation(
                store: store,
                artifactStore: artifactStore
            )

            SystemIO.Tools.RollbackFileMutation(
                store: store,
                recorder: recorder
            )
        }
    }
}
