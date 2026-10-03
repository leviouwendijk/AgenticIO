import Agentic

public struct CoreFileToolSet: AgentToolProvider {
    public init() {}

    public func registerTools(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            SystemIO.Tools.ReadFile()
            AgentToolRegistration.tool(
                SystemIO.Tools.MutateFiles(),
                execution: SystemIO.Tools.MutateFiles.execution
            )
            SystemIO.Tools.RemoveEmptyDirectories()
            SystemIO.Tools.ScanPaths()
            SystemIO.Tools.SearchSources()
            SystemIO.Tools.LoadSearchContext()
            SystemIO.Tools.ProveSearchResults()
        }
    }
}
