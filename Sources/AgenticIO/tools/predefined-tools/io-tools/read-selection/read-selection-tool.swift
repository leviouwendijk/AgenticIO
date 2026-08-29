import Agentic
import AgenticExecution
import AgenticWorkspace
import Position
import Primitives

public struct ReadSelectionTool: TypedInstanceAgentTool {
    public typealias Input = ReadSelectionToolInput

    public static let identifier: AgentToolIdentifier = "read_selection"
    public static let description = "Read one or more content selections from a file in the workspace."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }

    public var risk: ActionRisk {
        Self.risk
    }

    public init() {}

    public func preflight(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            ReadSelectionToolInput.self,
            from: input
        )
        _ = try decoded.contentSelections()

        let targetPath: String
        if let workspace {
            targetPath = try workspace.resolve(
                decoded.path
            ).presentingRelative(
                filetype: true
            )
        } else {
            targetPath = decoded.path
        }

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            targetPaths: [targetPath],
            summary: summary(
                for: decoded,
                renderedPath: targetPath
            )
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )

        let decoded = try JSONToolBridge.decode(
            ReadSelectionToolInput.self,
            from: input
        )

        let path = try workspace.resolve(
            decoded.path
        )

        let read = try workspace.readSelections(
            path,
            try decoded.contentSelections()
        )

        let slices = read.slices.map { slice in
            ReadSelectionToolOutputSlice(
                lineRange: lineRange(for: slice),
                lineCount: slice.lines.count,
                content: render(
                    slice: slice,
                    includeLineNumbers: decoded.includeLineNumbers
                )
            )
        }

        return try JSONToolBridge.encode(
            ReadSelectionToolOutput(
                path: read.relativePath,
                slices: slices,
                selectedLineRanges: read.selectedLineRanges,
                selectedLineCount: read.selectedLineCount,
                totalLineCount: read.totalLineCount,
                byteCount: read.byteCount,
                encoding: read.encodingUsed?.name
            )
        )
    }
}

private extension ReadSelectionTool {
    func summary(
        for input: ReadSelectionToolInput,
        renderedPath: String
    ) -> String {
        let selectionCount = input.selections.count

        if selectionCount == 0 {
            return input.includeLineNumbers
                ? "Read full file selection from \(renderedPath) with line numbers"
                : "Read full file selection from \(renderedPath)"
        }

        return input.includeLineNumbers
            ? "Read \(selectionCount) selection(s) from \(renderedPath) with line numbers"
            : "Read \(selectionCount) selection(s) from \(renderedPath)"
    }

    func lineRange(
        for slice: FileLineSlice
    ) -> LineRange? {
        guard !slice.lines.isEmpty else {
            return nil
        }

        return try? LineRange(
            start: slice.startLine,
            end: slice.endLine
        )
    }

    func render(
        slice: FileLineSlice,
        includeLineNumbers: Bool
    ) -> String {
        guard includeLineNumbers else {
            return joinedLines(
                slice.lines
            )
        }

        let endLine = max(
            slice.startLine,
            slice.endLine
        )
        let width = String(endLine).count

        return slice.lines.enumerated().map { offset, line in
            let lineNumber = slice.startLine + offset
            let label = String(
                format: "%\(width)d",
                lineNumber
            )

            return "\(label) | \(line)"
        }.joined(separator: "\n")
    }

    func joinedLines(
        _ lines: [String]
    ) -> String {
        guard !lines.isEmpty else {
            return ""
        }

        return lines.joined(separator: "\n")
    }
}
