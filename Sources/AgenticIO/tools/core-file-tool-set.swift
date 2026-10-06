import Agentic

// should probably be deprecated in favor of new domain-based derivation?
public struct CoreFileToolSet: AgentToolProvider {
    public init() {}

    public func registerTools(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            SystemIO.Tools.ReadFile()
            SystemIO.Tools.MutateFiles()
            SystemIO.Tools.RemoveEmptyDirectories()
            SystemIO.Tools.ScanPaths()
            SystemIO.Tools.SearchSources()
            SystemIO.Tools.LoadSearchContext()
            SystemIO.Tools.ProveSearchResults()
        }
    }
}
