import Agentic
import AgenticExecution
import Workspace
import Path
import Primitives
import Schema
import Readers

public extension SystemIO.Tools {
    @Tool
    struct ReadFile: Tool {
        public typealias Input = ReadFileToolInput
        public typealias Output = ReadFileToolOutput

        public static let purpose = "Read a file from the workspace, optionally constrained to a line window."
        public static let risk: ActionRisk = .observe

        public init() {}


        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            let workspace = try FileToolSupport.requireWorkspace(
                workspace,
                toolName: Self.identifier.rawValue
            )

            try FileToolSupport.validateReadWindow(
                toolName: Self.identifier.rawValue,
                startLine: input.startLine,
                endLine: input.endLine,
                maxLines: input.maxLines
            )

            let authorized = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: input.rootID,
                path: input.path,
                capability: .read,
                toolName: Self.identifier.rawValue,
                type: .file
            )
            let sensitivity = sensitivityAssessment(
                for: authorized
            )
            let estimatedReadLines = estimatedLineCount(
                for: input
            )

            return .init(
                tool: Self.definition.identifier,
                risk: sensitivity.risk,
                summary: summary(
                    for: input,
                    renderedPath: authorized.presentationPath,
                    sensitivityReason: sensitivity.summaryReason
                ),
                access: .init(
                    targets: [
                        authorized.presentationPath
                    ],
                    roots: [
                        input.rootID.rawValue
                    ],
                    capabilities: [
                        .read
                    ]
                ),
                estimates: .init(
                    read: .init(
                        lines: estimatedReadLines,
                        files: 1
                    )
                ),
                policyChecks: [
                    "workspace_required",
                    "root_path_authorized",
                    "read_capability_authorized",
                    "read_window_validated",
                    "path_sensitivity_profile:\(PathSensitivityProfile.agenticConservative.id)"
                ] + sensitivity.policyChecks,
                warnings: sensitivity.warnings
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


            try FileToolSupport.validateReadWindow(
                toolName: Self.identifier.rawValue,
                startLine: input.startLine,
                endLine: input.endLine,
                maxLines: input.maxLines
            )

            let authorized = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: input.rootID,
                path: input.path,
                capability: .read,
                toolName: Self.identifier.rawValue,
                type: .file
            )

            let read = try LineReader(
                authorized.absoluteURL
            ).readSlice(
                startLine: input.startLine,
                endLine: input.endLine,
                maxLines: input.maxLines
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
                displayContent = input.includeLineNumbers
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

            return ReadFileToolOutput(
                rootID: authorized.rootIdentifier.rawValue,
                path: authorized.presentationPath,
                content: rawContent,
                display: displayContent,
                lines: structuredLines,
                lineRange: read.selectedLineRange,
                lineCount: read.selectedLines.count,
                totalLineCount: read.totalLineCount,
                byteCount: read.byteCount,
                truncated: read.truncated,
                encoding: read.encodingUsed?.name
            )
            
        }
    }
}

private extension SystemIO.Tools.ReadFile {
    struct SensitivityAssessment {
        let risk: ActionRisk
        let policyChecks: [String]
        let warnings: [String]
        let summaryReason: String?
    }

    func summary(
        for input: ReadFileToolInput,
        renderedPath: String,
        sensitivityReason: String?
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

        let base: String

        if parts.isEmpty {
            base = "Read file \(renderedPath)"
        } else {
            base = "Read file \(renderedPath) (\(parts.joined(separator: ", ")))"
        }

        guard let sensitivityReason else {
            return base
        }

        return "\(base). Sensitive path: \(sensitivityReason)"
    }

    func sensitivityAssessment(
        for authorized: AuthorizedPath
    ) -> SensitivityAssessment {
        let rules = PathSensitivityProfile.agenticConservative
            .matchedRules(
                for: authorized.path,
                type: .file
            )
        let strongest = PathSensitivityAction.strongest(
            rules.map(\.action)
        )

        let risk: ActionRisk

        switch strongest {
        case .warn_only:
            risk = .observe

        case .suggest_deny:
            risk = .privileged

        case .require_deny:
            risk = .forbidden
        }

        let primaryRule = rules.max {
            $0.action.priority < $1.action.priority
        }

        return .init(
            risk: risk,
            policyChecks: rules.map {
                "path_sensitivity_rule:\($0.id)"
            },
            warnings: rules.map {
                "Path sensitivity: \($0.reason)"
            },
            summaryReason: strongest == .warn_only
                ? nil
                : primaryRule?.reason
        )
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
