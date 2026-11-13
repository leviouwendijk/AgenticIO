import Agentic
import Foundation
import Workspace
import Path
import Primitives
import Schema
import Readers
import Macros
import Position

private extension SystemIO.Tools.ReadFile.Input {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case startLine
        case endLine
        case maxLines
        case includeLineNumbers
    }
}

public extension SystemIO.Tools.ReadFile.Input {
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self.init(
            rootID: try container.decodeIfPresent(
                PathAccessRootIdentifier.self,
                forKey: .rootID
            ) ?? .project,
            path: try container.decode(
                String.self,
                forKey: .path
            ),
            startLine: try container.decodeIfPresent(
                Int.self,
                forKey: .startLine
            ),
            endLine: try container.decodeIfPresent(
                Int.self,
                forKey: .endLine
            ),
            maxLines: try container.decodeIfPresent(
                Int.self,
                forKey: .maxLines
            ),
            includeLineNumbers: try container.decodeIfPresent(
                Bool.self,
                forKey: .includeLineNumbers
            ) ?? false
        )
    }
}

public struct ReadFileLine: Sendable, Codable, Hashable {
    public let number: Int
    public let text: String

    public init(
        number: Int,
        text: String
    ) {
        self.number = number
        self.text = text
    }
}

public extension SystemIO.Tools {
    @Tool
    struct ReadFile: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            /// Workspace root identifier. Usually use 'project'.
            @Schema(required: false)
            public let rootID: PathAccessRootIdentifier

            /// Path to the file relative to the workspace root.
            public let path: String

            /// Optional 1-based first line to read.
            public let startLine: Int?

            /// Optional 1-based final line to read.
            public let endLine: Int?

            /// Optional maximum number of lines to read.
            public let maxLines: Int?

            /// Whether to include numbered display text in the returned display field. The content field always remains raw source text.
            @Schema(required: false)
            public let includeLineNumbers: Bool

            public init(
                rootID: PathAccessRootIdentifier = .project,
                path: String,
                startLine: Int? = nil,
                endLine: Int? = nil,
                maxLines: Int? = nil,
                includeLineNumbers: Bool = false
            ) {
                self.rootID = rootID
                self.path = path
                self.startLine = startLine
                self.endLine = endLine
                self.maxLines = maxLines
                self.includeLineNumbers = includeLineNumbers
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let rootID: String
            public let path: String
            public let content: String
            public let display: String?
            public let lines: [ReadFileLine]
            public let lineRange: LineRange?
            public let lineCount: Int
            public let totalLineCount: Int
            public let byteCount: Int
            public let truncated: Bool
            public let encoding: String?

            public init(
                rootID: String,
                path: String,
                content: String,
                display: String? = nil,
                lines: [ReadFileLine] = [],
                lineRange: LineRange?,
                lineCount: Int,
                totalLineCount: Int,
                byteCount: Int,
                truncated: Bool,
                encoding: String?
            ) {
                self.rootID = rootID
                self.path = path
                self.content = content
                self.display = display
                self.lines = lines
                self.lineRange = lineRange
                self.lineCount = lineCount
                self.totalLineCount = totalLineCount
                self.byteCount = byteCount
                self.truncated = truncated
                self.encoding = encoding
            }
        }


        public static let purpose = "Read a file from the workspace, optionally constrained to a line window."
        public static let risk: ActionRisk = .observe

        public init() {}


        public func preflight(
            _ input: Input,
            in context: ToolContext
        ) async throws -> ToolPreflight {
            let workspace = try FileToolSupport.requireWorkspace(
                context.workspace,
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
            let sensitivity = FileReadSensitivity.assess(authorized)
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
            in context: ToolContext
        ) async throws -> Output {
            let workspace = try FileToolSupport.requireWorkspace(
                context.workspace,
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

            let read = try await readSlice(
                authorized.absoluteURL,
                input: input,
                workspace: workspace
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

            return Output(
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
    /// A coordinated participant reads its own staged changes over the disk,
    /// so work staged earlier in the run is visible before publication.
    func readSlice(
        _ url: URL,
        input: SystemIO.Tools.ReadFile.Input,
        workspace: WorkspaceContext
    ) async throws -> LineSliceReadResult {
        if case .coordinated(let submission) = workspace.execution.mutations,
           let staged = try await submission.stagedState(at: url) {
            guard let text = staged.textContent else {
                throw PredefinedFileToolError.invalidValue(
                    tool: Self.identifier.rawValue,
                    field: "path",
                    reason: staged.exists
                        ? "staged content is not text"
                        : "staged for deletion in this run"
                )
            }
            return LineReadResult(
                url: url,
                text: text,
                encodingUsed: nil,
                byteCount: text.utf8.count,
                existed: true
            ).slice(
                startLine: input.startLine,
                endLine: input.endLine,
                maxLines: input.maxLines
            )
        }
        return try LineReader(url).readSlice(
            startLine: input.startLine,
            endLine: input.endLine,
            maxLines: input.maxLines
        )
    }

    func summary(
        for input: SystemIO.Tools.ReadFile.Input,
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

    func estimatedLineCount(
        for input: SystemIO.Tools.ReadFile.Input
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
