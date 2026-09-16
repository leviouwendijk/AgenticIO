import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Path
import PathParsing
import Primitives

public struct CoreWorkspaceToolSet: AgentToolSet {
    public init() {}

    public func register(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            InspectWorkspaceTool()
            ListPathRootsTool()
            ListPathGrantsTool()
            ExplainPathAccessTool()
            FindPathsTool()
            RequestPathGrantTool()
        }
    }
}