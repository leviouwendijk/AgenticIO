import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Path
import PathParsing
import Primitives

public struct CoreWorkspaceToolSet: AgentToolSet {
    public let preparedIntentManager: PreparedIntentManager?

    public init(
        preparedIntentManager: PreparedIntentManager? = nil
    ) {
        self.preparedIntentManager = preparedIntentManager
    }

    public func register(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register(
            [
                InspectWorkspaceTool(),
                ListPathRootsTool(),
                ListPathGrantsTool(),
                ExplainPathAccessTool(),
                FindPathsTool()
            ]
        )

        if let preparedIntentManager {
            try registry.register(
                RequestPathGrantTool(
                    manager: preparedIntentManager
                )
            )
        }
    }
}

