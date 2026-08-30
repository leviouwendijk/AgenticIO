import AgenticExecution

public struct CoreFileToolSet: AgentToolSet {
    // public let fileMutationRecorder: AgentFileMutationRecorder?

    // public init(
    //     fileMutationRecorder: AgentFileMutationRecorder? = nil
    // ) {
    //     self.fileMutationRecorder = fileMutationRecorder
    // }

    public init() {}

    public func register(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            ReadFileTool()
            // WriteFileTool(
            //     recorder: fileMutationRecorder
            // )
            // EditFileTool(
            //     recorder: fileMutationRecorder
            // )
            MutateFilesTool()
            RemoveEmptyDirectoriesTool()
            ScanPathsTool()
            SearchSourcesTool()
            LoadSearchContextTool()
        }
    }
}
