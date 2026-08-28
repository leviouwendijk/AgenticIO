import Foundation
import Position
import Writers

enum EditFileToolError: Error, Sendable, LocalizedError {
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

        case .snapshotChanged(let path, let expected, let actual):
            return "Edit for \(path) was blocked because the file changed after the edit plan was resolved. Expected fingerprint \(expected), found \(actual)."
        }
    }
}
