import AgenticExecution

public struct CoreFileToolSet: AgentToolSet {
    public init() {}

    public func register(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            ReadFileTool()
            MutateFilesTool()
            RemoveEmptyDirectoriesTool()
            ScanPathsTool()
            SearchSourcesTool()
            LoadSearchContextTool()
            ProveSearchResultsTool()
        }
    }
}
