import Agentic
import Foundation
import Workspace
import Path
import Primitives
import Schema
import Readers
import Macros
import Position

private extension SystemIO.Tools.ReadFiles.Input {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case startLine
        case endLine
        case maxLines
        case reads
        case includeLineNumbers
    }
}

public extension SystemIO.Tools.ReadFiles.Input {
    /// One read (`path` with its window) or several (`reads`), never both.
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let path = try container.decodeIfPresent(String.self, forKey: .path)
        let reads = try container.decodeIfPresent(
            [SystemIO.Tools.ReadFiles.Window].self,
            forKey: .reads
        ) ?? []

        guard (path == nil) != reads.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .path,
                in: container,
                debugDescription: "Give either path (one read) or reads (several), not both."
            )
        }

        self.init(
            rootID: try container.decodeIfPresent(
                PathAccessRootIdentifier.self,
                forKey: .rootID
            ) ?? .project,
            path: path,
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
            reads: reads,
            includeLineNumbers: try container.decodeIfPresent(
                Bool.self,
                forKey: .includeLineNumbers
            ) ?? false
        )
    }
}

private extension SystemIO.Tools.ReadFiles.Window {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case startLine
        case endLine
        case maxLines
    }
}

public extension SystemIO.Tools.ReadFiles.Window {
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
            )
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
    struct ReadFiles: Tool {
        /// One file, or one line window of it.
        @JSONSchema
        public struct Window: HashableSource {
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

            public init(
                rootID: PathAccessRootIdentifier = .project,
                path: String,
                startLine: Int? = nil,
                endLine: Int? = nil,
                maxLines: Int? = nil
            ) {
                self.rootID = rootID
                self.path = path
                self.startLine = startLine
                self.endLine = endLine
                self.maxLines = maxLines
            }
        }

        /// Read one file with `path` (and optionally a line window), or several files or windows at once with `reads`.
        @JSONSchema
        public struct Input: HashableSource {
            /// Workspace root identifier for path. Usually use 'project'.
            @Schema(required: false)
            public let rootID: PathAccessRootIdentifier

            /// Path to the file relative to the workspace root. For one read; use reads for several.
            public let path: String?

            /// Optional 1-based first line to read from path.
            public let startLine: Int?

            /// Optional 1-based final line to read from path.
            public let endLine: Int?

            /// Optional maximum number of lines to read from path.
            public let maxLines: Int?

            /// Several reads in one call, each a path with an optional line window; instead of path. At most 20.
            @Schema(required: false)
            public let reads: [Window]

            /// Whether to include numbered display text in the returned display field. The content field always remains raw source text.
            @Schema(required: false)
            public let includeLineNumbers: Bool

            public init(
                rootID: PathAccessRootIdentifier = .project,
                path: String? = nil,
                startLine: Int? = nil,
                endLine: Int? = nil,
                maxLines: Int? = nil,
                reads: [Window] = [],
                includeLineNumbers: Bool = false
            ) {
                self.rootID = rootID
                self.path = path
                self.startLine = startLine
                self.endLine = endLine
                self.maxLines = maxLines
                self.reads = reads
                self.includeLineNumbers = includeLineNumbers
            }

            /// The reads this input asks for, in order.
            public var windows: [Window] {
                guard let path else { return reads }
                return [
                    .init(
                        rootID: rootID,
                        path: path,
                        startLine: startLine,
                        endLine: endLine,
                        maxLines: maxLines
                    ),
                ]
            }
        }

        /// One read's result.
        public struct File: Sendable, Codable, Hashable {
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

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            /// One per read, in the order asked.
            public let files: [File]

            public init(
                files: [File]
            ) {
                self.files = files
            }
        }

        public static let purpose = "Read files from the workspace: one with path (optionally a line window), or several files or windows at once with reads."
        public static let risk: ActionRisk = .observe
        public static let maximumReads = 20

        public init() {}

        public func preflight(
            _ input: Input,
            in context: ToolContext
        ) async throws -> ToolPreflight {
            let workspace = try FileToolSupport.requireWorkspace(
                context.workspace,
                toolName: Self.identifier.rawValue
            )
            let windows = try validatedWindows(input)

            var risk = Self.risk
            var targets: [String] = []
            var roots: [String] = []
            var lines: Int? = 0
            var summaries: [String] = []
            var policyChecks: [String] = []
            var warnings: [String] = []

            for window in windows {
                let authorized = try FileToolAccess.authorize(
                    workspace: workspace,
                    rootID: window.rootID,
                    path: window.path,
                    capability: .read,
                    toolName: Self.identifier.rawValue,
                    type: .file
                )
                let sensitivity = FileReadSensitivity.assess(authorized)
                // The most consequential read decides the call's risk.
                if let rank = ActionRisk.allCases.firstIndex(of: sensitivity.risk),
                   let current = ActionRisk.allCases.firstIndex(of: risk),
                   rank > current {
                    risk = sensitivity.risk
                }
                targets.append(authorized.presentationPath)
                if !roots.contains(window.rootID.rawValue) {
                    roots.append(window.rootID.rawValue)
                }
                if let total = lines, let estimate = estimatedLineCount(for: window) {
                    lines = total + estimate
                } else {
                    lines = nil
                }
                summaries.append(summary(
                    for: window,
                    includeLineNumbers: input.includeLineNumbers,
                    renderedPath: authorized.presentationPath,
                    sensitivityReason: sensitivity.summaryReason
                ))
                for check in sensitivity.policyChecks where !policyChecks.contains(check) {
                    policyChecks.append(check)
                }
                warnings.append(contentsOf: sensitivity.warnings)
            }

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: summaries.joined(separator: "; "),
                access: .init(
                    targets: targets,
                    roots: roots,
                    capabilities: [
                        .read
                    ]
                ),
                estimates: .init(
                    read: .init(
                        lines: lines,
                        files: Set(targets).count
                    )
                ),
                policyChecks: [
                    "workspace_required",
                    "root_path_authorized",
                    "read_capability_authorized",
                    "read_window_validated",
                    "path_sensitivity_profile:\(PathSensitivityProfile.agenticConservative.id)"
                ] + policyChecks,
                warnings: warnings
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
            var files: [File] = []
            for window in try validatedWindows(input) {
                files.append(try await read(
                    window,
                    includeLineNumbers: input.includeLineNumbers,
                    workspace: workspace
                ))
            }
            return .init(files: files)
        }
    }
}

private extension SystemIO.Tools.ReadFiles {
    func validatedWindows(
        _ input: Input
    ) throws -> [Window] {
        let windows = input.windows
        guard !windows.isEmpty, windows.count <= Self.maximumReads else {
            throw PredefinedFileToolError.invalidValue(
                tool: Self.identifier.rawValue,
                field: "reads",
                reason: "give path, or between 1 and \(Self.maximumReads) reads"
            )
        }
        for window in windows {
            try FileToolSupport.validateReadWindow(
                toolName: Self.identifier.rawValue,
                startLine: window.startLine,
                endLine: window.endLine,
                maxLines: window.maxLines
            )
        }
        return windows
    }

    func read(
        _ window: Window,
        includeLineNumbers: Bool,
        workspace: WorkspaceContext
    ) async throws -> File {
        let authorized = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: window.rootID,
            path: window.path,
            capability: .read,
            toolName: Self.identifier.rawValue,
            type: .file
        )

        let read = try await readSlice(
            authorized.absoluteURL,
            window: window,
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
            displayContent = includeLineNumbers
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

        return File(
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

    /// A coordinated participant reads its own staged changes over the disk,
    /// so work staged earlier in the run is visible before publication.
    func readSlice(
        _ url: URL,
        window: Window,
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
                startLine: window.startLine,
                endLine: window.endLine,
                maxLines: window.maxLines
            )
        }
        return try LineReader(url).readSlice(
            startLine: window.startLine,
            endLine: window.endLine,
            maxLines: window.maxLines
        )
    }

    func summary(
        for window: Window,
        includeLineNumbers: Bool,
        renderedPath: String,
        sensitivityReason: String?
    ) -> String {
        var parts: [String] = []

        if let startLine = window.startLine,
           let endLine = window.endLine {
            parts.append(
                "lines \(startLine)-\(endLine)"
            )
        } else if let startLine = window.startLine {
            parts.append(
                "starting at line \(startLine)"
            )
        } else if let endLine = window.endLine {
            parts.append(
                "through line \(endLine)"
            )
        }

        if let maxLines = window.maxLines {
            parts.append(
                "max \(maxLines) line(s)"
            )
        }

        if includeLineNumbers {
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
        for window: Window
    ) -> Int? {
        if let maxLines = window.maxLines {
            return maxLines
        }

        if let startLine = window.startLine,
           let endLine = window.endLine {
            return max(
                0,
                endLine - startLine + 1
            )
        }

        return nil
    }
}
