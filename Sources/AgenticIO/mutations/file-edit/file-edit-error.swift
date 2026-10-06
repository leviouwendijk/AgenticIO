import Foundation
import Position
import Writers

enum FileEditError: Error, Sendable, LocalizedError {
    case invalidLinePayload(
        operation: Int,
        field: String,
        line: String
    )

    case lineOutOfBounds(
        operation: Int,
        line: Int,
        valid: String
    )

    case rangeOutOfBounds(
        operation: Int,
        range: LineRange,
        valid: String
    )

    case positionOutOfBounds(
        operation: Int,
        position: Int,
        valid: String
    )

    case coordinateOutOfBounds(
        operation: Int,
        endpoint: String,
        position: FileEditPosition
    )

    case invalidPositionRange(
        operation: Int,
        range: FileEditPositionRange
    )

    case mixedPositionRangeOperations

    case snapshotChanged(
        path: String,
        expected: StandardContentFingerprint,
        actual: StandardContentFingerprint
    )

    var errorDescription: String? {
        switch self {
        case .invalidLinePayload(let operation, let field, let line):
            return "Edit operation \(operation) has invalid \(field). Expected one logical line without newline characters, got \(String(reflecting: line))."

        case .lineOutOfBounds(let operation, let line, let valid):
            return "Edit operation \(operation) references line \(line), but valid existing lines are \(valid)."

        case .rangeOutOfBounds(let operation, let range, let valid):
            return "Edit operation \(operation) references range \(range.start)..\(range.end), but valid existing lines are \(valid)."

        case .positionOutOfBounds(let operation, let position, let valid):
            return "Edit operation \(operation) references insertion position \(position), but valid insertion positions are \(valid)."

        case .coordinateOutOfBounds(let operation, let endpoint, let position):
            return "Edit operation \(operation) has an invalid \(endpoint) coordinate at line \(position.line), column \(position.column)."

        case .invalidPositionRange(let operation, let range):
            return "Edit operation \(operation) requires a non-empty forward position range, got \(range.start.line):\(range.start.column)..<\(range.end.line):\(range.end.column)."

        case .mixedPositionRangeOperations:
            return "Position-range edits may only be batched with other position-range edits so all ranges retain original-snapshot coordinates."

        case .snapshotChanged(let path, let expected, let actual):
            return "Edit for \(path) was blocked because the file changed after the edit plan was resolved. Expected fingerprint \(expected), found \(actual)."
        }
    }
}
