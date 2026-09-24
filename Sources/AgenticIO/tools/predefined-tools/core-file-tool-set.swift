import AgenticExecution

public struct CoreFileToolSet: AgentToolProvider {
    public init() {}

    public func registerTools(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            SystemIO.Tools.ReadFile()
            AgentToolRegistration.tool(
                SystemIO.Tools.MutateFiles(),
                execution: .targetable
            )
            SystemIO.Tools.RemoveEmptyDirectories()
            SystemIO.Tools.ScanPaths()
            SystemIO.Tools.SearchSources()
            SystemIO.Tools.LoadSearchContext()
            SystemIO.Tools.ProveSearchResults()
        }
    }
}
