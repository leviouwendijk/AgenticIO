import Agentic
import AgenticExecution
import Workspace
import Position
import Primitives
import Readers
import Selection

public extension SystemIO.Tools {
    @Tool
    struct ReadSelection: Tool {
        public typealias Input = ReadSelectionToolInput
        public typealias Output = ReadSelectionToolOutput

        public static let purpose = "Read one or more content selections from a file in the workspace."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            _ = try input.contentSelections()

            let targetPath: String
            if let workspace {
                targetPath = try workspace.authorize(
                    input.path,
                    capability: .read
                ).authorizedPath.presentationPath
            } else {
                targetPath = input.path
            }

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: summary(
                    for: input,
                    renderedPath: targetPath
                ),
                access: .init(
                    targets: [
                        targetPath
                    ]
                ),
            )
        }

        public func call(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> Output {
            let workspace = try FileToolSupport.requireWorkspace(
                workspace,
                toolName: Self.identifier.rawValue
            )
            let authorized = try workspace.authorize(
                input.path,
                capability: .read
            ).authorizedPath
            let read = try SelectionResolver.resolve(
                file: authorized.absoluteURL,
                selections: try input.contentSelections()
            )

            let slices = read.slices.map { slice in
                ReadSelectionToolOutputSlice(
                    lineRange: lineRange(for: slice),
                    lineCount: slice.lines.count,
                    content: render(
                        slice: slice,
                        includeLineNumbers: input.includeLineNumbers
                    )
                )
            }

            return ReadSelectionToolOutput(
                path: authorized.presentationPath,
                slices: slices,
                selectedLineRanges: read.selectedLineRanges,
                selectedLineCount: read.selectedLineCount,
                totalLineCount: read.totalLineCount,
                byteCount: read.byteCount,
                encoding: read.encodingUsed?.name
            )
            
        }
    }
}

private extension SystemIO.Tools.ReadSelection {
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
