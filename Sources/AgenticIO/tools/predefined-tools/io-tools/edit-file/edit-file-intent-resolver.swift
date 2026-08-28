import AgenticWorkspace
import Foundation
import Position
import Writers

struct EditFileIntentResolver: Sendable {
    let toolName: String

    init(
        toolName: String
    ) {
        self.toolName = toolName
    }

    func resolve(
        _ input: EditFileToolInput,
        workspace: AgentWorkspace
    ) throws -> ResolvedEditPlan {
        let authorized = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: input.rootID,
            path: input.path,
            capability: .write,
            toolName: toolName,
            type: .file
        )

        let content = try ResolvedEditPlan.readContent(
            at: authorized.absoluteURL
        )
        let snapshot = StandardEditSnapshot(
            content: content
        )
        let lines = WriteTextLines(
            content
        ).lines

        let operations = try input.operations.enumerated().map { offset, operation in
            try resolve(
                operation,
                operationIndex: offset + 1,
                currentLines: lines
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

private extension EditFileIntentResolver {
    func resolve(
        _ operation: EditFileToolOperation,
        operationIndex: Int,
        currentLines: [String]
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

    func existingLine(
        _ line: Int,
        operationIndex: Int,
        currentLines: [String]
    ) throws -> String {
        guard currentLines.indices.contains(line - 1) else {
            throw EditFileToolError.lineOutOfBounds(
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
            throw EditFileToolError.rangeOutOfBounds(
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
            throw EditFileToolError.positionOutOfBounds(
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
            throw EditFileToolError.invalidLinePayload(
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
