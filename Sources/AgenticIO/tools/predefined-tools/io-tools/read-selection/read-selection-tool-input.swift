import Foundation
import Position
import Schema
import SchemaMacros
import Selection

/// One model-facing content selection for read_selection.
///
/// The enum deliberately owns a stable AgenticIO wire representation instead
/// of exposing Selection.ContentSelection's compiler-generated Codable shape.
@JSONSchema
public enum ReadSelectionSelection:
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

/// Read one or more bounded selections from a workspace file.
@JSONSchema
public struct ReadSelectionToolInput:
    Sendable,
    Codable,
    Hashable
{
    /// Path to the file relative to the workspace root.
    public let path: String

    /// Content selections to materialize. An empty array reads the full file.
    @Schema(required: false)
    public let selections: [ReadSelectionSelection]

    /// Whether returned slice content includes line-number prefixes.
    @Schema(required: false)
    public let includeLineNumbers: Bool

    public init(
        path: String,
        selections: [ReadSelectionSelection] = [],
        includeLineNumbers: Bool = false
    ) {
        self.path = path
        self.selections = selections
        self.includeLineNumbers = includeLineNumbers
    }
}

private extension ReadSelectionToolInput {
    enum CodingKeys:
        String,
        CodingKey
    {
        case path
        case selections
        case includeLineNumbers
    }
}

public extension ReadSelectionToolInput {
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self.init(
            path: try container.decode(
                String.self,
                forKey: .path
            ),
            selections: try container.decodeIfPresent(
                [ReadSelectionSelection].self,
                forKey: .selections
            ) ?? [],
            includeLineNumbers: try container.decodeIfPresent(
                Bool.self,
                forKey: .includeLineNumbers
            ) ?? false
        )
    }

    func contentSelections() throws -> [ContentSelection] {
        try selections.map {
            try $0.contentSelection()
        }
    }
}

public enum ReadSelectionInputError:
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
            return "read_selection requires a positive line range with end >= start; received \(start)...\(end)."

        case .invalidPosition(let line, let column):
            return "read_selection requires positive 1-based line and column values; received \(line):\(column)."

        case .invalidSpan:
            return "read_selection requires the span end position to be at or after its start position."

        case .emptyAnchor:
            return "read_selection anchor text must not be empty."

        case .invalidAnchorCount(let count):
            return "read_selection anchor count must be positive; received \(count)."
        }
    }
}

public extension ReadSelectionSelection {
    func contentSelection() throws -> ContentSelection {
        switch self {
        case .lines(let start, let end):
            guard start > 0,
                  end >= start
            else {
                throw ReadSelectionInputError.invalidLineRange(
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
                throw ReadSelectionInputError.invalidSpan
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
                throw ReadSelectionInputError.emptyAnchor
            }

            let count = count ?? 1
            guard count > 0 else {
                throw ReadSelectionInputError.invalidAnchorCount(
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
            throw ReadSelectionInputError.invalidPosition(
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
