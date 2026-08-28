import Foundation

enum PredefinedFileToolError: Error, Sendable, LocalizedError {
    case workspaceRequired(String)
    case missingField(tool: String, field: String)
    case invalidValue(tool: String, field: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .workspaceRequired(let tool):
            return "Tool '\(tool)' requires an attached AgentWorkspace."

        case .missingField(let tool, let field):
            return "Tool '\(tool)' is missing required field '\(field)'."

        case .invalidValue(let tool, let field, let reason):
            return "Tool '\(tool)' has invalid value for '\(field)': \(reason)"
        }
    }
}
