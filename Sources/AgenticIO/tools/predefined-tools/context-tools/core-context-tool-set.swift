import AgenticExecution

public struct CoreContextToolSet: AgentToolProvider {
    public let composer: ContextComposer

    public init(
        composer: ContextComposer = .init()
    ) {
        self.composer = composer
    }

    public func registerTools(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            SystemIO.Tools.ComposeContext(
                composer: composer
            )
            SystemIO.Tools.InspectContextSources()
            SystemIO.Tools.EstimateContextSize(
                composer: composer
            )
        }
    }
}
