import AgenticExecution

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
