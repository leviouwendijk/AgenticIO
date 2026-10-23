// FROZEN: independent durable prepared-intent queue is not required by the conversation or ToolPlan bridge.
#if AGENTIC_ENABLE_DEFERRED_INTENTS
import Agentic

public struct AgenticIOPreparedOperationSet: Sendable {
    public let fileMutationRecorder: AgentFileMutationRecorder?

    public init(
        fileMutationRecorder: AgentFileMutationRecorder? = nil
    ) {
        self.fileMutationRecorder = fileMutationRecorder
    }

    public func register(
        into registry: inout PreparedOperationRegistry
    ) throws {
        try registry.register(
            PreparedFileMutationExecutor(
                recorder: fileMutationRecorder
            )
        )
    }
}
#endif // AGENTIC_ENABLE_DEFERRED_INTENTS
