import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema

public struct ReadFileTool: TypedInstanceAgentTool {
    public typealias Input = ReadFileToolInput

    public static let identifier: AgentToolIdentifier = "read_file"
    public static let description = "Read a file from the workspace, optionally constrained to a line window."
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
            ReadFileToolInput.self,
            from: input
        )

        try FileToolSupport.validateReadWindow(
            startLine: decoded.startLine,
            endLine: decoded.endLine,
            maxLines: decoded.maxLines
        )

        let targetPath = try FileToolAccess.presentationPath(
            workspace: workspace,
            rootID: decoded.rootID,
            path: decoded.path,
            type: .file
        )

        let estimatedReadLines = estimatedLineCount(
            for: decoded
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            targetPaths: [
                targetPath
            ],
            summary: summary(
                for: decoded,
                renderedPath: targetPath
            ),
            rootIDs: [
                decoded.rootID.rawValue
            ],
            capabilitiesRequired: [
                .read
            ],
            estimatedReadLines: estimatedReadLines,
            estimatedFileReadCount: 1,
            policyChecks: [
                "workspace_required",
                "root_path_resolved",
                "read_window_validated"
            ]
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
            ReadFileToolInput.self,
            from: input
        )

        try FileToolSupport.validateReadWindow(
            startLine: decoded.startLine,
            endLine: decoded.endLine,
            maxLines: decoded.maxLines
        )

        let authorized = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: decoded.rootID,
            path: decoded.path,
            capability: .read,
            toolName: name,
            type: .file
        )

        let read = try workspace.readSlice(
            authorized.path,
            startLine: decoded.startLine,
            endLine: decoded.endLine,
            maxLines: decoded.maxLines
        )

        let rawContent: String
        let displayContent: String?
        let structuredLines: [ReadFileLine]

        if let range = read.selectedLineRange {
            rawContent = FileToolSupport.renderLines(
                read.selectedLines,
                startingAt: range.start,
                includeLineNumbers: false
            )
            displayContent = decoded.includeLineNumbers
                ? FileToolSupport.renderLines(
                    read.selectedLines,
                    startingAt: range.start,
                    includeLineNumbers: true
                )
                : nil
            structuredLines = read.selectedLines.enumerated().map { offset, text in
                ReadFileLine(
                    number: range.start + offset,
                    text: text
                )
            }
        } else {
            rawContent = ""
            displayContent = nil
            structuredLines = []
        }

        return try JSONToolBridge.encode(
            ReadFileToolOutput(
                rootID: authorized.rootID.rawValue,
                path: authorized.presentationPath,
                content: rawContent,
                display: displayContent,
                lines: structuredLines,
                lineRange: read.selectedLineRange,
                lineCount: read.lineCount,
                totalLineCount: read.totalLineCount,
                byteCount: read.byteCount,
                truncated: read.truncated,
                encoding: read.encodingUsed?.name
            )
        )
    }
}

private extension ReadFileTool {
    func summary(
        for input: ReadFileToolInput,
        renderedPath: String
    ) -> String {
        var parts: [String] = []

        if let startLine = input.startLine,
           let endLine = input.endLine {
            parts.append(
                "lines \(startLine)-\(endLine)"
            )
        } else if let startLine = input.startLine {
            parts.append(
                "starting at line \(startLine)"
            )
        } else if let endLine = input.endLine {
            parts.append(
                "through line \(endLine)"
            )
        }

        if let maxLines = input.maxLines {
            parts.append(
                "max \(maxLines) line(s)"
            )
        }

        if input.includeLineNumbers {
            parts.append(
                "with line-number display"
            )
        }

        guard !parts.isEmpty else {
            return "Read file \(renderedPath)"
        }

        return "Read file \(renderedPath) (\(parts.joined(separator: ", ")))"
    }

    func estimatedLineCount(
        for input: ReadFileToolInput
    ) -> Int? {
        if let maxLines = input.maxLines {
            return maxLines
        }

        if let startLine = input.startLine,
           let endLine = input.endLine {
            return max(
                0,
                endLine - startLine + 1
            )
        }

        return nil
    }
}
