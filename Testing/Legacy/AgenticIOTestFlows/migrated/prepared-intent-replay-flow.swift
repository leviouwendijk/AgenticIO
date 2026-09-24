import Agentic
import AgenticIO
import Primitives
import Testing

internal func preparedIntentReplayRegistry(
    recorder: AgentFileMutationRecorder,
    store: any AgentFileMutationStore
) throws -> ToolRegistry {
    var registry = ToolRegistry()

    try registry.register(
        [
            WriteFileTool(
                recorder: recorder
            ),
            EditFileTool(
                recorder: recorder
            ),
            SystemIO.Tools.RollbackFileMutation(
                store: store,
                recorder: recorder
            )
        ]
    )

    return registry
}

internal func executePreparedIntentThroughRegistry(
    _ intent: PreparedIntent,
    manager: PreparedIntentManager,
    workspace: WorkspaceContext,
    recorder: AgentFileMutationRecorder,
    store: any AgentFileMutationStore,
    sessionID: String
) async throws -> ExecutePreparedIntentToolOutput {
    let executionRegistry = try preparedIntentReplayRegistry(
        recorder: recorder,
        store: store
    )
    var operatorRegistry = ToolRegistry()

    try operatorRegistry.register(
        PreparedIntentOperatorToolSet(
            manager: manager,
            executionRegistry: executionRegistry,
            sessionID: sessionID
        )
    )

    let result = try await operatorRegistry.execute(
        AgentToolCall(
            id: "execute-\(intent.id.rawValue)",
            name: AgentToolIdentifier.execute_prepared_intent.rawValue,
            input: try JSONToolBridge.encode(
                ExecutePreparedIntentToolInput(
                    id: intent.id
                )
            )
        ),
        context: .init(
            workspace: workspace,
            sessionID: sessionID,
            executionMode: .host_call
        )
    )

    return try JSONToolBridge.decode(
        ExecutePreparedIntentToolOutput.self,
        from: result.output
    )
}

internal func assertPreparedReplayResult(
    _ output: ExecutePreparedIntentToolOutput,
    intentID: PreparedIntentIdentifier,
    expectedToolName: String,
    label: String
) throws {
    try Expect.equal(
        output.intent.status,
        .executed,
        "\(label) executed status"
    )

    try Expect.equal(
        output.toolCall.name,
        expectedToolName,
        "\(label) replay tool name"
    )

    try Expect.equal(
        output.toolResult.toolCallID,
        output.toolCall.id,
        "\(label) result links synthetic tool call id"
    )

    try Expect.equal(
        output.toolCall.id,
        "prepared-\(intentID.rawValue)",
        "\(label) synthetic tool call id"
    )

    _ = try Expect.notNil(
        output.intent.executionRecord,
        "\(label) has execution record"
    )

    _ = try Expect.notNil(
        output.intent.executionRecord?.result,
        "\(label) has execution result"
    )
}
