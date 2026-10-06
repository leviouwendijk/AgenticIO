import Foundation
import Workspace

enum FileToolSupport {
    static func requireWorkspace(
        _ workspace: WorkspaceContext?,
        toolName: String
    ) throws -> WorkspaceContext {
        guard let workspace else {
            throw PredefinedFileToolError.workspaceRequired(
                toolName
            )
        }

        return workspace
    }

    static func renderLines(
        _ lines: [String],
        startingAt startLine: Int,
        includeLineNumbers: Bool
    ) -> String {
        guard includeLineNumbers else {
            return lines.joined(separator: "\n")
        }

        let endLine = max(
            startLine,
            startLine + lines.count - 1
        )
        let width = String(endLine).count

        return lines.enumerated().map { offset, line in
            let lineNumber = startLine + offset
            let label = String(
                format: "%\(width)d",
                lineNumber
            )

            return "\(label) | \(line)"
        }.joined(separator: "\n")
    }

    static func validateReadWindow(
        toolName: String,
        startLine: Int?,
        endLine: Int?,
        maxLines: Int?
    ) throws {
        if let startLine,
           startLine < 1 {
            throw PredefinedFileToolError.invalidValue(
                tool: toolName,
                field: "startLine",
                reason: "must be >= 1"
            )
        }

        if let endLine,
           endLine < 1 {
            throw PredefinedFileToolError.invalidValue(
                tool: toolName,
                field: "endLine",
                reason: "must be >= 1"
            )
        }

        if let startLine,
           let endLine,
           endLine < startLine {
            throw PredefinedFileToolError.invalidValue(
                tool: toolName,
                field: "endLine",
                reason: "must be >= startLine"
            )
        }

        if let maxLines,
           maxLines < 1 {
            throw PredefinedFileToolError.invalidValue(
                tool: toolName,
                field: "maxLines",
                reason: "must be >= 1"
            )
        }
    }
}
