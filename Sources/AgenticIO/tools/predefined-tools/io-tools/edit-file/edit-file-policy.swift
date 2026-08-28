import AgenticWorkspace
import Foundation
import Path
import Position
import Writers

public enum EditFileRequiredOperation: String, Sendable, Codable, Hashable, CaseIterable {
    case insert_lines
    case replace_lines
    case delete_lines
    case replace_line
}

public enum EditFilePolicyError: Error, Sendable, LocalizedError, Hashable {
    case grant_required(
        rootID: String,
        path: String
    )
    case required_operation_missing(
        operation: EditFileRequiredOperation
    )
    case insertion_position_outside_grant(
        position: Int,
        allowed: [Int]
    )
    case replacement_range_outside_grant(
        range: LineRange,
        allowed: [LineRange]
    )

    public var errorDescription: String? {
        switch self {
        case .grant_required(let rootID, let path):
            return "No edit grant matched root '\(rootID)' and path '\(path)'."

        case .required_operation_missing(let operation):
            return "Required edit operation '\(operation.rawValue)' is missing."

        case .insertion_position_outside_grant(let position, let allowed):
            return "Insertion position \(position) is outside the edit grant. Allowed positions: \(allowed.map(String.init).joined(separator: ", "))."

        case .replacement_range_outside_grant(let range, let allowed):
            return "Replacement range \(range.start)...\(range.end) is outside the edit grant. Allowed ranges: \(allowed.renderedLineRanges)."
        }
    }
}

public struct EditFileGrant: Sendable, Codable, Hashable {
    public var rootID: PathAccessRootIdentifier?
    public var path: String?
    public var constraint: StandardEditConstraint
    public var requiredOperations: [EditFileRequiredOperation]
    public var allowedInsertionPositions: [Int]
    public var allowedReplacementRanges: [LineRange]

    public init(
        rootID: PathAccessRootIdentifier? = nil,
        path: String? = nil,
        constraint: StandardEditConstraint,
        requiredOperations: [EditFileRequiredOperation] = [],
        allowedInsertionPositions: [Int] = [],
        allowedReplacementRanges: [LineRange] = []
    ) {
        self.rootID = rootID
        self.path = path
        self.constraint = constraint
        self.requiredOperations = requiredOperations
        self.allowedInsertionPositions = allowedInsertionPositions
        self.allowedReplacementRanges = allowedReplacementRanges
    }

    public func matches(
        input: EditFileToolInput,
        authorized: AgenticAuthorizedPath
    ) -> Bool {
        if let rootID,
           rootID != authorized.rootID {
            return false
        }

        if let path {
            return path == input.path
                || path == authorized.presentationPath
                || path == authorized.qualifiedPresentationPath
        }

        return true
    }

    public func validate(
        operations: [StandardEditOperation]
    ) throws {
        try validateRequiredOperations(
            operations
        )
        try validateInsertionPositions(
            operations
        )
        try validateReplacementRanges(
            operations
        )
    }
}

public struct EditFilePolicy: Sendable, Codable, Hashable {
    public var defaultConstraint: StandardEditConstraint
    public var grants: [EditFileGrant]
    public var requiresGrant: Bool

    public init(
        defaultConstraint: StandardEditConstraint = .unrestricted,
        grants: [EditFileGrant] = [],
        requiresGrant: Bool = false
    ) {
        self.defaultConstraint = defaultConstraint
        self.grants = grants
        self.requiresGrant = requiresGrant
    }

    public static let unrestricted = Self()

    public static func bounded(
        rootID: PathAccessRootIdentifier = .project,
        path: String,
        budget: StandardEditBudget = .small,
        requiredOperations: [EditFileRequiredOperation] = [],
        insertionPositions: [Int] = [],
        replacementRanges: [(Int, Int)] = []
    ) -> Self {
        let allowedRanges = replacementRanges.map { start, end in
            LineRange(
                uncheckedStart: start,
                uncheckedEnd: end
            )
        }

        let operations = StandardEditOperationSet(
            [
                .insert_lines,
                .insert_lines_guarded,
                .replace_lines,
                .replace_lines_guarded,
                .delete_lines,
                .delete_lines_guarded,
            ]
        )

        let constraint = StandardEditConstraint(
            scope: .file,
            budget: budget,
            operations: operations,
            guards: .existingLines
        )

        return .init(
            defaultConstraint: .unrestricted,
            grants: [
                .init(
                    rootID: rootID,
                    path: path,
                    constraint: constraint,
                    requiredOperations: requiredOperations,
                    allowedInsertionPositions: insertionPositions,
                    allowedReplacementRanges: allowedRanges
                )
            ],
            requiresGrant: true
        )
    }

    public func constraint(
        for input: EditFileToolInput,
        authorized: AgenticAuthorizedPath,
        operations: [StandardEditOperation]
    ) throws -> StandardEditConstraint {
        guard let grant = grants.first(where: { grant in
            grant.matches(
                input: input,
                authorized: authorized
            )
        }) else {
            guard !requiresGrant else {
                throw EditFilePolicyError.grant_required(
                    rootID: authorized.rootID.rawValue,
                    path: authorized.presentationPath
                )
            }

            return defaultConstraint
        }

        try grant.validate(
            operations: operations
        )

        return grant.constraint
    }
}

private extension EditFileGrant {
    func validateRequiredOperations(
        _ operations: [StandardEditOperation]
    ) throws {
        for required in requiredOperations {
            guard operations.contains(where: { operation in
                required.isSatisfied(
                    by: operation.kind
                )
            }) else {
                throw EditFilePolicyError.required_operation_missing(
                    operation: required
                )
            }
        }
    }

    func validateInsertionPositions(
        _ operations: [StandardEditOperation]
    ) throws {
        guard !allowedInsertionPositions.isEmpty else {
            return
        }

        for operation in operations {
            guard let position = operation.insertionPosition else {
                continue
            }

            guard allowedInsertionPositions.contains(position) else {
                throw EditFilePolicyError.insertion_position_outside_grant(
                    position: position,
                    allowed: allowedInsertionPositions
                )
            }
        }
    }

    func validateReplacementRanges(
        _ operations: [StandardEditOperation]
    ) throws {
        guard !allowedReplacementRanges.isEmpty else {
            return
        }

        for operation in operations {
            guard let range = operation.replacementRange else {
                continue
            }

            guard allowedReplacementRanges.containsLineRange(range) else {
                throw EditFilePolicyError.replacement_range_outside_grant(
                    range: range,
                    allowed: allowedReplacementRanges
                )
            }
        }
    }
}

private extension EditFileRequiredOperation {
    func isSatisfied(
        by kind: StandardEditOperationKind
    ) -> Bool {
        switch self {
        case .insert_lines:
            return kind == .insert_lines
                || kind == .insert_lines_guarded

        case .replace_lines:
            return kind == .replace_lines
                || kind == .replace_lines_guarded

        case .delete_lines:
            return kind == .delete_lines
                || kind == .delete_lines_guarded

        case .replace_line:
            return kind == .replace_line
                || kind == .replace_line_guarded
        }
    }
}

private extension StandardEditOperation {
    var insertionPosition: Int? {
        switch self {
        case .insertLines(_, let line),
             .insertLinesGuarded(_, let line, _):
            return line

        case .replaceEntireFile,
             .append,
             .prepend,
             .replaceFirst,
             .replaceAll,
             .replaceUnique,
             .replaceLine,
             .replaceLineGuarded,
             .replaceLines,
             .replaceLinesGuarded,
             .deleteLines,
             .deleteLinesGuarded:
            return nil
        }
    }

    var replacementRange: LineRange? {
        switch self {
        case .replaceLines(let range, _),
             .replaceLinesGuarded(let range, _, _),
             .deleteLines(let range),
             .deleteLinesGuarded(let range, _):
            return range

        case .replaceEntireFile,
             .append,
             .prepend,
             .replaceFirst,
             .replaceAll,
             .replaceUnique,
             .replaceLine,
             .replaceLineGuarded,
             .insertLines,
             .insertLinesGuarded:
            return nil
        }
    }
}

private extension Array where Element == LineRange {
    func containsLineRange(
        _ range: LineRange
    ) -> Bool {
        contains { candidate in
            candidate.start == range.start
                && candidate.end == range.end
        }
    }

    var renderedLineRanges: String {
        guard !isEmpty else {
            return "none"
        }

        return map { range in
            "\(range.start)...\(range.end)"
        }.joined(
            separator: ", "
        )
    }
}
