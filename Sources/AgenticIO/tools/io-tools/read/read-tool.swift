import Agentic
import Foundation
import Workspace
import Path
import Primitives
import Schema
import Readers
import Selection
import Macros
import Position

/// One model-facing content selection inside a read.
///
/// The enum deliberately owns a stable AgenticIO wire representation instead
/// of exposing Selection.ContentSelection's compiler-generated Codable shape.
@JSONSchema
public enum ReadFileSelection:
    Sendable,
    Codable,
    Hashable
{
    /// Select an inclusive 1-based line range.
    case lines(
        start: Int,
        end: Int
    )

    /// Select one 1-based source position.
    case point(
        line: Int,
        column: Int
    )

    /// Select an inclusive source span using 1-based positions.
    case span(
        startLine: Int,
        startColumn: Int,
        endLine: Int,
        endColumn: Int
    )

    /// Select content relative to exact anchor text. Offset defaults to 0 and count defaults to 1 when omitted.
    case anchor(
        text: String,
        offset: Int?,
        count: Int?
    )
}

public enum ReadFileSelectionError:
    Error,
    Sendable,
    LocalizedError
{
    case invalidLineRange(
        start: Int,
        end: Int
    )
    case invalidPosition(
        line: Int,
        column: Int
    )
    case invalidSpan
    case emptyAnchor
    case invalidAnchorCount(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLineRange(let start, let end):
            return "read selections require a positive line range with end >= start; received \(start)...\(end)."

        case .invalidPosition(let line, let column):
            return "read selections require positive 1-based line and column values; received \(line):\(column)."

        case .invalidSpan:
            return "read selection spans require the end position to be at or after the start position."

        case .emptyAnchor:
            return "read selection anchor text must not be empty."

        case .invalidAnchorCount(let count):
            return "read selection anchor count must be positive; received \(count)."
        }
    }
}

public extension ReadFileSelection {
    func contentSelection() throws -> ContentSelection {
        switch self {
        case .lines(let start, let end):
            guard start > 0,
                  end >= start
            else {
                throw ReadFileSelectionError.invalidLineRange(
                    start: start,
                    end: end
                )
            }

            return .lines(
                LineRange(
                    uncheckedStart: start,
                    uncheckedEnd: end
                )
            )

        case .point(let line, let column):
            return .point(
                try position(
                    line: line,
                    column: column
                )
            )

        case .span(
            let startLine,
            let startColumn,
            let endLine,
            let endColumn
        ):
            let start = try position(
                line: startLine,
                column: startColumn
            )
            let end = try position(
                line: endLine,
                column: endColumn
            )

            guard endLine > startLine
                    || (
                        endLine == startLine
                        && endColumn >= startColumn
                    )
            else {
                throw ReadFileSelectionError.invalidSpan
            }

            return .span(
                PositionSpan(
                    uncheckedStart: start,
                    uncheckedEnd: end
                )
            )

        case .anchor(
            let text,
            let offset,
            let count
        ):
            guard !text.isEmpty else {
                throw ReadFileSelectionError.emptyAnchor
            }

            let count = count ?? 1
            guard count > 0 else {
                throw ReadFileSelectionError.invalidAnchorCount(
                    count
                )
            }

            return .anchor(
                ContentAnchorSelection(
                    text: text,
                    offset: offset ?? 0,
                    count: count
                )
            )
        }
    }

    private func position(
        line: Int,
        column: Int
    ) throws -> Position {
        guard line > 0,
              column > 0
        else {
            throw ReadFileSelectionError.invalidPosition(
                line: line,
                column: column
            )
        }

        return Position(
            uncheckedFile: nil,
            line: line,
            column: column,
            invocation: nil
        )
    }
}

private extension SystemIO.Tools.Read.Input {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case startLine
        case endLine
        case maxLines
        case selections
        case reads
        case includeLineNumbers
    }
}

public extension SystemIO.Tools.Read.Input {
    /// One read (`path` with its window) or several (`reads`), never both.
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let path = try container.decodeIfPresent(String.self, forKey: .path)
        let reads = try container.decodeIfPresent(
            [SystemIO.Tools.Read.Window].self,
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
            selections: try container.decodeIfPresent(
                [ReadFileSelection].self,
                forKey: .selections
            ) ?? [],
            reads: reads,
            includeLineNumbers: try container.decodeIfPresent(
                Bool.self,
                forKey: .includeLineNumbers
            ) ?? false
        )
    }
}

private extension SystemIO.Tools.Read.Window {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case startLine
        case endLine
        case maxLines
        case selections
    }
}

public extension SystemIO.Tools.Read.Window {
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
            selections: try container.decodeIfPresent(
                [ReadFileSelection].self,
                forKey: .selections
            ) ?? []
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
    struct Read: Tool {
        /// One file: whole, a line window of it, or selections in it.
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

            /// Lines, a position, a span, or text around an anchor, each read as its own slice; instead of a line window.
            @Schema(required: false)
            public let selections: [ReadFileSelection]

            public init(
                rootID: PathAccessRootIdentifier = .project,
                path: String,
                startLine: Int? = nil,
                endLine: Int? = nil,
                maxLines: Int? = nil,
                selections: [ReadFileSelection] = []
            ) {
                self.rootID = rootID
                self.path = path
                self.startLine = startLine
                self.endLine = endLine
                self.maxLines = maxLines
                self.selections = selections
            }
        }

        /// Read one file with `path` (optionally a line window or selections), or several files or windows at once with `reads`.
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

            /// Lines, a position, a span, or text around an anchor in path, each read as its own slice; instead of a line window.
            @Schema(required: false)
            public let selections: [ReadFileSelection]

            /// Several reads in one call, each a path with an optional line window or selections; instead of path. At most 20.
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
                selections: [ReadFileSelection] = [],
                reads: [Window] = [],
                includeLineNumbers: Bool = false
            ) {
                self.rootID = rootID
                self.path = path
                self.startLine = startLine
                self.endLine = endLine
                self.maxLines = maxLines
                self.selections = selections
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
                        maxLines: maxLines,
                        selections: selections
                    ),
                ]
            }
        }

        /// One read's result: a file, a line window of it, or one selected slice.
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

            /// One per read in the order asked; a read with selections gives one per selected slice.
            public let files: [File]

            public init(
                files: [File]
            ) {
                self.files = files
            }
        }

        public static let purpose = "Read files from the workspace: one with path (optionally a line window or selections), or several files or windows at once with reads."
        public static let risk: ActionRisk = .observe
        public static let maximumReads = 20

        public init() {}

        public func preflight(
            _ input: Input,
            in context: CapabilityContext
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
            in context: CapabilityContext
        ) async throws -> Output {
            let workspace = try FileToolSupport.requireWorkspace(
                context.workspace,
                toolName: Self.identifier.rawValue
            )
            var files: [File] = []
            for window in try validatedWindows(input) {
                files.append(contentsOf: try await read(
                    window,
                    includeLineNumbers: input.includeLineNumbers,
                    workspace: workspace
                ))
            }
            return .init(files: files)
        }
    }
}

private extension SystemIO.Tools.Read {
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
            guard window.selections.isEmpty else {
                guard window.startLine == nil,
                      window.endLine == nil,
                      window.maxLines == nil
                else {
                    throw PredefinedFileToolError.invalidValue(
                        tool: Self.identifier.rawValue,
                        field: "selections",
                        reason: "give selections or a line window (startLine, endLine, maxLines), not both"
                    )
                }
                for selection in window.selections {
                    _ = try selection.contentSelection()
                }
                continue
            }
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
    ) async throws -> [File] {
        let authorized = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: window.rootID,
            path: window.path,
            capability: .read,
            toolName: Self.identifier.rawValue,
            type: .file
        )

        guard window.selections.isEmpty else {
            return try await readSelections(
                window,
                authorized: authorized,
                includeLineNumbers: includeLineNumbers,
                workspace: workspace
            )
        }

        let read = try await readSlice(
            authorized.absoluteURL,
            window: window,
            workspace: workspace
        )

        guard let range = read.selectedLineRange else {
            return [
                File(
                    rootID: authorized.rootIdentifier.rawValue,
                    path: authorized.presentationPath,
                    content: "",
                    lineRange: nil,
                    lineCount: 0,
                    totalLineCount: read.totalLineCount,
                    byteCount: read.byteCount,
                    truncated: read.truncated,
                    encoding: read.encodingUsed?.name
                ),
            ]
        }

        return [
            file(
                authorized: authorized,
                lines: read.selectedLines,
                startingAt: range.start,
                lineRange: range,
                includeLineNumbers: includeLineNumbers,
                totalLineCount: read.totalLineCount,
                byteCount: read.byteCount,
                truncated: read.truncated,
                encoding: read.encodingUsed?.name
            ),
        ]
    }

    /// Each selected slice as its own file entry, resolved over the same
    /// text a line window reads (staged changes included).
    func readSelections(
        _ window: Window,
        authorized: AuthorizedPath,
        includeLineNumbers: Bool,
        workspace: WorkspaceContext
    ) async throws -> [File] {
        let text = try await readWhole(
            authorized.absoluteURL,
            workspace: workspace
        )
        let resolved = SelectionResolver.resolve(
            file: authorized.absoluteURL,
            readResult: text,
            selections: try window.selections.map {
                try $0.contentSelection()
            }
        )

        return resolved.slices.map { slice in
            file(
                authorized: authorized,
                lines: slice.lines,
                startingAt: slice.startLine,
                lineRange: slice.lines.isEmpty
                    ? nil
                    : try? LineRange(
                        start: slice.startLine,
                        end: slice.endLine
                    ),
                includeLineNumbers: includeLineNumbers,
                totalLineCount: resolved.totalLineCount,
                byteCount: resolved.byteCount,
                truncated: false,
                encoding: resolved.encodingUsed?.name
            )
        }
    }

    func file(
        authorized: AuthorizedPath,
        lines: [String],
        startingAt start: Int,
        lineRange: LineRange?,
        includeLineNumbers: Bool,
        totalLineCount: Int,
        byteCount: Int,
        truncated: Bool,
        encoding: String?
    ) -> File {
        File(
            rootID: authorized.rootIdentifier.rawValue,
            path: authorized.presentationPath,
            content: FileToolSupport.renderLines(
                lines,
                startingAt: start,
                includeLineNumbers: false
            ),
            display: includeLineNumbers
                ? FileToolSupport.renderLines(
                    lines,
                    startingAt: start,
                    includeLineNumbers: true
                )
                : nil,
            lines: lines.enumerated().map { offset, text in
                ReadFileLine(
                    number: start + offset,
                    text: text
                )
            },
            lineRange: lineRange,
            lineCount: lines.count,
            totalLineCount: totalLineCount,
            byteCount: byteCount,
            truncated: truncated,
            encoding: encoding
        )
    }

    /// A coordinated participant reads its own staged changes over the disk,
    /// so work staged earlier in the run is visible before publication.
    func stagedText(
        _ url: URL,
        workspace: WorkspaceContext
    ) async throws -> String? {
        guard case .coordinated(let submission) = workspace.execution.mutations,
              let staged = try await submission.stagedState(at: url)
        else {
            return nil
        }
        guard let text = staged.textContent else {
            throw PredefinedFileToolError.invalidValue(
                tool: Self.identifier.rawValue,
                field: "path",
                reason: staged.exists
                    ? "staged content is not text"
                    : "staged for deletion in this run"
            )
        }
        return text
    }

    func readSlice(
        _ url: URL,
        window: Window,
        workspace: WorkspaceContext
    ) async throws -> LineSliceReadResult {
        if let text = try await stagedText(url, workspace: workspace) {
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

    func readWhole(
        _ url: URL,
        workspace: WorkspaceContext
    ) async throws -> LineReadResult {
        if let text = try await stagedText(url, workspace: workspace) {
            return LineReadResult(
                url: url,
                text: text,
                encodingUsed: nil,
                byteCount: text.utf8.count,
                existed: true
            )
        }
        return try LineReader(url).read(
            options: .default
        )
    }

    func summary(
        for window: Window,
        includeLineNumbers: Bool,
        renderedPath: String,
        sensitivityReason: String?
    ) -> String {
        var parts: [String] = []

        if !window.selections.isEmpty {
            parts.append(
                "\(window.selections.count) selection(s)"
            )
        } else if let startLine = window.startLine,
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
        guard window.selections.isEmpty else {
            return nil
        }

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
