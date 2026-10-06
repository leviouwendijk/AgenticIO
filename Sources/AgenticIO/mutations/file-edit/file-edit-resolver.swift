import Workspace
import Foundation
import Position
import Writers

struct FileEditResolver: Sendable {
    let toolName: String

    init(
        toolName: String
    ) {
        self.toolName = toolName
    }

    func resolve(
        _ input: FileEditRequest,
        workspace: WorkspaceContext
    ) throws -> FileEditResolution {
        let authorized = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: input.rootID,
            path: input.path,
            capability: .write,
            toolName: toolName,
            type: .file
        )

        let content = try FileEditResolution.readContent(
            at: authorized.absoluteURL
        )
        let snapshot = StandardEditSnapshot(
            content: content
        )
        let lines = WriteTextLines(
            content
        ).lines
        let lineTable = LineTable(
            text: content
        )

        let hasPositionRangeOperation = input.operations.contains {
            $0.kind == .replace_range
        }

        if hasPositionRangeOperation,
           input.operations.contains(where: {
               $0.kind != .replace_range
           }) {
            throw FileEditError.mixedPositionRangeOperations
        }

        let operations = try input.operations.enumerated().map { offset, operation in
            try resolve(
                operation,
                operationIndex: offset + 1,
                currentContent: content,
                currentLines: lines,
                lineTable: lineTable
            )
        }

        return .init(
            input: input,
            authorized: authorized,
            snapshot: snapshot,
            operations: operations,
            editMode: input.resolvedEditMode
        )
    }
}

private extension FileEditResolver {
    func resolve(
        _ operation: FileEditOperation,
        operationIndex: Int,
        currentContent: String,
        currentLines: [String],
        lineTable: LineTable
    ) throws -> StandardEditOperation {
        switch operation {
        case .replace_entire_file(let operation):
            return .replaceEntireFile(
                with: operation.content
            )

        case .append(let operation):
            return .append(
                operation.content,
                separator: operation.separator
            )

        case .prepend(let operation):
            return .prepend(
                operation.content,
                separator: operation.separator
            )

        case .replace_first(let operation):
            return .replaceFirst(
                of: operation.target,
                with: operation.replacement
            )

        case .replace_all(let operation):
            return .replaceAll(
                of: operation.target,
                with: operation.replacement
            )

        case .replace_unique(let operation):
            return .replaceUnique(
                of: operation.target,
                with: operation.replacement
            )

        case .replace_line(let operation):
            try validateLogicalLine(
                operation.content,
                operationIndex: operationIndex,
                field: "content"
            )

            return StandardEditOperation.line.replace(
                operation.line,
                expected: try existingLine(
                    operation.line,
                    operationIndex: operationIndex,
                    currentLines: currentLines
                ),
                with: operation.content
            )

        case .replace_range(let operation):
            let range = try positionRange(
                operation.range,
                operationIndex: operationIndex,
                lineTable: lineTable
            )

            return StandardEditOperation.text.replace(
                range,
                expected: existingText(
                    range,
                    in: currentContent
                ),
                with: operation.replacement
            )

        case .insert_lines(let operation):
            try validateLogicalLines(
                operation.lines,
                operationIndex: operationIndex,
                field: "lines"
            )
            try validateInsertionPosition(
                operation.position,
                operationIndex: operationIndex,
                currentLines: currentLines
            )

            return StandardEditOperation.lines.insert(
                operation.lines,
                at: operation.position
            )

        case .insert_before(let operation):
            try validateLogicalLines(
                operation.lines,
                operationIndex: operationIndex,
                field: "lines"
            )
            _ = try existingLine(
                operation.line,
                operationIndex: operationIndex,
                currentLines: currentLines
            )

            return StandardEditOperation.lines.insert(
                operation.lines,
                at: operation.line
            )

        case .insert_after(let operation):
            try validateLogicalLines(
                operation.lines,
                operationIndex: operationIndex,
                field: "lines"
            )
            _ = try existingLine(
                operation.line,
                operationIndex: operationIndex,
                currentLines: currentLines
            )

            return StandardEditOperation.lines.insert(
                operation.lines,
                at: operation.line + 1
            )

        case .replace_lines(let operation):
            let range = try operation.range.lineRange()

            try validateLogicalLines(
                operation.lines,
                operationIndex: operationIndex,
                field: "lines"
            )

            return StandardEditOperation.lines.replace(
                range,
                expected: try existingLines(
                    range,
                    operationIndex: operationIndex,
                    currentLines: currentLines
                ),
                with: operation.lines
            )

        case .delete_lines(let operation):
            let range = try operation.range.lineRange()

            return StandardEditOperation.lines.delete(
                range,
                expected: try existingLines(
                    range,
                    operationIndex: operationIndex,
                    currentLines: currentLines
                )
            )
        }
    }

    func positionRange(
        _ range: FileEditPositionRange,
        operationIndex: Int,
        lineTable: LineTable
    ) throws -> PositionRange {
        let start = try positionIndex(
            range.start,
            endpoint: "start",
            operationIndex: operationIndex,
            lineTable: lineTable
        )
        let end = try positionIndex(
            range.end,
            endpoint: "end",
            operationIndex: operationIndex,
            lineTable: lineTable
        )

        guard start.offset < end.offset else {
            throw FileEditError.invalidPositionRange(
                operation: operationIndex,
                range: range
            )
        }

        return PositionRange(
            uncheckedStart: start,
            uncheckedEnd: end
        )
    }

    func positionIndex(
        _ position: FileEditPosition,
        endpoint: String,
        operationIndex: Int,
        lineTable: LineTable
    ) throws -> PositionIndex {
        guard let index = lineTable.indices.at(
            line: position.line,
            column: position.column
        ) else {
            throw FileEditError.coordinateOutOfBounds(
                operation: operationIndex,
                endpoint: endpoint,
                position: position
            )
        }

        return index
    }

    func existingText(
        _ range: PositionRange,
        in content: String
    ) -> String {
        let lower = content.index(
            content.startIndex,
            offsetBy: range.start.offset
        )
        let upper = content.index(
            content.startIndex,
            offsetBy: range.end.offset
        )

        return String(
            content[lower..<upper]
        )
    }

    func existingLine(
        _ line: Int,
        operationIndex: Int,
        currentLines: [String]
    ) throws -> String {
        guard currentLines.indices.contains(line - 1) else {
            throw FileEditError.lineOutOfBounds(
                operation: operationIndex,
                line: line,
                valid: existingLineDescription(
                    currentLines
                )
            )
        }

        return currentLines[line - 1]
    }

    func existingLines(
        _ range: LineRange,
        operationIndex: Int,
        currentLines: [String]
    ) throws -> [String] {
        guard range.start >= 1,
              range.end <= currentLines.count
        else {
            throw FileEditError.rangeOutOfBounds(
                operation: operationIndex,
                range: range,
                valid: existingLineDescription(
                    currentLines
                )
            )
        }

        return Array(
            currentLines[(range.start - 1)..<range.end]
        )
    }

    func validateInsertionPosition(
        _ position: Int,
        operationIndex: Int,
        currentLines: [String]
    ) throws {
        guard position >= 1,
              position <= currentLines.count + 1
        else {
            throw FileEditError.positionOutOfBounds(
                operation: operationIndex,
                position: position,
                valid: insertionPositionDescription(
                    currentLines
                )
            )
        }
    }

    func validateLogicalLines(
        _ lines: [String],
        operationIndex: Int,
        field: String
    ) throws {
        for line in lines {
            try validateLogicalLine(
                line,
                operationIndex: operationIndex,
                field: field
            )
        }
    }

    func validateLogicalLine(
        _ line: String,
        operationIndex: Int,
        field: String
    ) throws {
        guard !line.contains("\n"),
              !line.contains("\r")
        else {
            throw FileEditError.invalidLinePayload(
                operation: operationIndex,
                field: field,
                line: line
            )
        }
    }

    func existingLineDescription(
        _ lines: [String]
    ) -> String {
        guard !lines.isEmpty else {
            return "none"
        }

        return "1...\(lines.count)"
    }

    func insertionPositionDescription(
        _ lines: [String]
    ) -> String {
        "1...\(lines.count + 1)"
    }
}
