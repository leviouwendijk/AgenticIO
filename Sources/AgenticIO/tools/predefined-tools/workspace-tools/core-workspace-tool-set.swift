import Agentic
import AgenticExecution
import Workspace
import Foundation
import Path
import PathParsing
import Primitives

public struct CoreWorkspaceToolSet: AgentToolProvider {
    public init() {}

    public func registerTools(
        into registry: inout ToolRegistry
    ) throws {
        try registry.register {
            SystemIO.Tools.InspectWorkspace()
            SystemIO.Tools.ListPathRoots()
            SystemIO.Tools.ListPathGrants()
            SystemIO.Tools.ExplainPathAccess()
            SystemIO.Tools.FindPaths()
            SystemIO.Tools.RequestPathGrant()
        }
    }
}
