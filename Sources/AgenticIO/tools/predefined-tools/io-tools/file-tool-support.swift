import AgenticWorkspace
import Foundation

enum FileToolSupport {
    static func requireWorkspace(
        _ workspace: AgentWorkspace?,
        toolName: String
    ) throws -> AgentWorkspace {
        guard let workspace else {
            throw PredefinedFileToolError.workspaceRequired(toolName)
        }

        return workspace
    }

    static func validateReadWindow(
        startLine: Int?,
        endLine: Int?,
        maxLines: Int?
    ) throws {
        if let startLine,
           startLine <= 0 {
            throw PredefinedFileToolError.invalidValue(
                tool: "read_file",
                field: "startLine",
                reason: "must be greater than zero"
            )
        }

        if let endLine,
           endLine <= 0 {
            throw PredefinedFileToolError.invalidValue(
                tool: "read_file",
                field: "endLine",
                reason: "must be greater than zero"
            )
        }

        if let maxLines,
           maxLines <= 0 {
            throw PredefinedFileToolError.invalidValue(
                tool: "read_file",
                field: "maxLines",
                reason: "must be greater than zero"
            )
        }

        if let startLine,
           let endLine,
           endLine < startLine {
            throw PredefinedFileToolError.invalidValue(
                tool: "read_file",
                field: "endLine",
                reason: "must be greater than or equal to startLine"
            )
        }
    }

    static func renderLines(
        _ lines: [String],
        startingAt startLine: Int,
        includeLineNumbers: Bool
    ) -> String {
        guard includeLineNumbers else {
            return joinedLines(lines)
        }

        let endLine = startLine + max(0, lines.count - 1)
        let width = String(max(1, endLine)).count

        return lines.enumerated().map { offset, line in
            let number = startLine + offset
            let label = String(
                format: "%\(width)d",
                number
            )

            return "\(label) | \(line)"
        }.joined(separator: "\n")
    }
}

private extension FileToolSupport {
    static func joinedLines(
        _ lines: [String]
    ) -> String {
        guard !lines.isEmpty else {
            return ""
        }

        return lines.joined(separator: "\n")
    }
}
