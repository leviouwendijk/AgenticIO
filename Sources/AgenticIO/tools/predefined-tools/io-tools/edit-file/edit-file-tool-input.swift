import Path
import Position
import Primitives
import Writers

public struct EditFileLineRange: Sendable, Codable, Hashable {
    public let start: Int
    public let end: Int

    public init(
        start: Int,
        end: Int
    ) {
        self.start = start
        self.end = end
    }

    public func lineRange() throws -> LineRange {
        try LineRange(
            start: start,
            end: end
        )
    }
}

public enum EditFileToolOperationKind: String, Sendable, Codable, Hashable, CaseIterable {
    case replace_entire_file
    case append
    case prepend
    case replace_first
    case replace_all
    case replace_unique
    case replace_line
    case insert_lines
    case replace_lines
    case delete_lines
}

public enum EditFileToolOperation: Sendable, Hashable {
    case replace_entire_file(ReplaceEntireFile)
    case append(Append)
    case prepend(Prepend)
    case replace_first(ReplaceFirst)
    case replace_all(ReplaceAll)
    case replace_unique(ReplaceUnique)
    case replace_line(ReplaceLine)
    case insert_lines(InsertLines)
    case replace_lines(ReplaceLines)
    case delete_lines(DeleteLines)

    public var kind: EditFileToolOperationKind {
        switch self {
        case .replace_entire_file:
            return .replace_entire_file

        case .append:
            return .append

        case .prepend:
            return .prepend

        case .replace_first:
            return .replace_first

        case .replace_all:
            return .replace_all

        case .replace_unique:
            return .replace_unique

        case .replace_line:
            return .replace_line

        case .insert_lines:
            return .insert_lines

        case .replace_lines:
            return .replace_lines

        case .delete_lines:
            return .delete_lines
        }
    }
}

extension EditFileToolOperation {
    var isSnapshotCompatible: Bool {
        switch kind {
        case .replace_line,
             .insert_lines,
             .replace_lines,
             .delete_lines:
            return true

        case .replace_entire_file,
             .append,
             .prepend,
             .replace_first,
             .replace_all,
             .replace_unique:
            return false
        }
    }
}

extension EditFileToolInput {
    var resolvedEditMode: StandardEditMode {
        guard !operations.isEmpty else {
            return .sequential
        }

        return operations.allSatisfy(\.isSnapshotCompatible)
            ? .snapshot
            : .sequential
    }
}

public extension EditFileToolOperation {
    struct ReplaceEntireFile: Sendable, Codable, Hashable {
        public let content: String

        public init(
            content: String
        ) {
            self.content = content
        }
    }

    struct Append: Sendable, Codable, Hashable {
        public let content: String
        public let separator: String?

        public init(
            content: String,
            separator: String? = nil
        ) {
            self.content = content
            self.separator = separator
        }
    }

    struct Prepend: Sendable, Codable, Hashable {
        public let content: String
        public let separator: String?

        public init(
            content: String,
            separator: String? = nil
        ) {
            self.content = content
            self.separator = separator
        }
    }

    struct ReplaceFirst: Sendable, Codable, Hashable {
        public let target: String
        public let replacement: String

        public init(
            target: String,
            replacement: String
        ) {
            self.target = target
            self.replacement = replacement
        }
    }

    struct ReplaceAll: Sendable, Codable, Hashable {
        public let target: String
        public let replacement: String

        public init(
            target: String,
            replacement: String
        ) {
            self.target = target
            self.replacement = replacement
        }
    }

    struct ReplaceUnique: Sendable, Codable, Hashable {
        public let target: String
        public let replacement: String

        public init(
            target: String,
            replacement: String
        ) {
            self.target = target
            self.replacement = replacement
        }
    }

    struct ReplaceLine: Sendable, Codable, Hashable {
        public let line: Int
        public let content: String

        public init(
            line: Int,
            content: String
        ) {
            self.line = line
            self.content = content
        }

        private enum CodingKeys: String, CodingKey {
            case line
            case content
            case replacement
        }

        public init(
            from decoder: any Decoder
        ) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )

            self.init(
                line: try container.decode(
                    Int.self,
                    forKey: .line
                ),
                content: try container.decodeIfPresent(
                    String.self,
                    forKey: .content
                ) ?? container.decode(
                    String.self,
                    forKey: .replacement
                )
            )
        }

        public func encode(
            to encoder: any Encoder
        ) throws {
            var container = encoder.container(
                keyedBy: CodingKeys.self
            )

            try container.encode(
                line,
                forKey: .line
            )
            try container.encode(
                content,
                forKey: .content
            )
        }
    }

    struct InsertLines: Sendable, Codable, Hashable {
        public let position: Int
        public let lines: [String]

        public init(
            position: Int,
            lines: [String]
        ) {
            self.position = position
            self.lines = lines
        }
    }

    struct ReplaceLines: Sendable, Codable, Hashable {
        public let range: EditFileLineRange
        public let lines: [String]

        public init(
            range: EditFileLineRange,
            lines: [String]
        ) {
            self.range = range
            self.lines = lines
        }
    }

    struct DeleteLines: Sendable, Codable, Hashable {
        public let range: EditFileLineRange

        public init(
            range: EditFileLineRange
        ) {
            self.range = range
        }
    }
}

private extension EditFileToolOperation {
    enum CodingKeys: String, CodingKey {
        case kind
        case content
        case target
        case replacement
        case line
        case lines
        case position
        case range
        case separator
    }
}

extension EditFileToolOperation: Codable {
    public init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let kind = try container.decode(
            EditFileToolOperationKind.self,
            forKey: .kind
        )

        switch kind {
        case .replace_entire_file:
            self = .replace_entire_file(
                try ReplaceEntireFile(
                    from: decoder
                )
            )

        case .append:
            self = .append(
                try Append(
                    from: decoder
                )
            )

        case .prepend:
            self = .prepend(
                try Prepend(
                    from: decoder
                )
            )

        case .replace_first:
            self = .replace_first(
                try ReplaceFirst(
                    from: decoder
                )
            )

        case .replace_all:
            self = .replace_all(
                try ReplaceAll(
                    from: decoder
                )
            )

        case .replace_unique:
            self = .replace_unique(
                try ReplaceUnique(
                    from: decoder
                )
            )

        case .replace_line:
            self = .replace_line(
                try ReplaceLine(
                    from: decoder
                )
            )

        case .insert_lines:
            self = .insert_lines(
                try InsertLines(
                    from: decoder
                )
            )

        case .replace_lines:
            self = .replace_lines(
                try ReplaceLines(
                    from: decoder
                )
            )

        case .delete_lines:
            self = .delete_lines(
                try DeleteLines(
                    from: decoder
                )
            )
        }
    }

    public func encode(
        to encoder: any Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            kind,
            forKey: .kind
        )

        switch self {
        case .replace_entire_file(let operation):
            try container.encode(
                operation.content,
                forKey: .content
            )

        case .append(let operation):
            try container.encode(
                operation.content,
                forKey: .content
            )
            try container.encodeIfPresent(
                operation.separator,
                forKey: .separator
            )

        case .prepend(let operation):
            try container.encode(
                operation.content,
                forKey: .content
            )
            try container.encodeIfPresent(
                operation.separator,
                forKey: .separator
            )

        case .replace_first(let operation):
            try container.encode(
                operation.target,
                forKey: .target
            )
            try container.encode(
                operation.replacement,
                forKey: .replacement
            )

        case .replace_all(let operation):
            try container.encode(
                operation.target,
                forKey: .target
            )
            try container.encode(
                operation.replacement,
                forKey: .replacement
            )

        case .replace_unique(let operation):
            try container.encode(
                operation.target,
                forKey: .target
            )
            try container.encode(
                operation.replacement,
                forKey: .replacement
            )

        case .replace_line(let operation):
            try container.encode(
                operation.line,
                forKey: .line
            )
            try container.encode(
                operation.content,
                forKey: .content
            )

        case .insert_lines(let operation):
            try container.encode(
                operation.position,
                forKey: .position
            )
            try container.encode(
                operation.lines,
                forKey: .lines
            )

        case .replace_lines(let operation):
            try container.encode(
                operation.range,
                forKey: .range
            )
            try container.encode(
                operation.lines,
                forKey: .lines
            )

        case .delete_lines(let operation):
            try container.encode(
                operation.range,
                forKey: .range
            )
        }
    }
}

public struct EditFileToolInput: Sendable, Codable, Hashable {
    public let rootID: PathAccessRootIdentifier
    public let path: String
    public let operations: [EditFileToolOperation]

    public init(
        rootID: PathAccessRootIdentifier = .project,
        path: String,
        operations: [EditFileToolOperation]
    ) {
        self.rootID = rootID
        self.path = path
        self.operations = operations
    }
}

private extension EditFileToolInput {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case operations
    }
}

public extension EditFileToolInput {
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
            operations: try container.decode(
                [EditFileToolOperation].self,
                forKey: .operations
            )
        )
    }
}

public extension EditFileLineRange {
    static var schema: JSONValue {
        JSONSchema.object {
            JSONSchema.integer(
                "start",
                required: true,
                description: "1-based first line in the inclusive line range."
            )
            JSONSchema.integer(
                "end",
                required: true,
                description: "1-based final line in the inclusive line range."
            )
        }
    }
}

public extension EditFileToolOperation {
    static var schema: JSONValue {
        JSONSchema.object(
            description: """
            One edit operation. The required fields depend on kind:
            replace_entire_file requires content.
            append requires content and optional separator.
            prepend requires content and optional separator.
            replace_first requires target and replacement.
            replace_all requires target and replacement.
            replace_unique requires target and replacement.
            replace_line requires line and content.
            insert_lines requires position and lines.
            replace_lines requires range and lines.
            delete_lines requires range.
            The runtime derives all exact guard content from the current raw file state.
            """
        ) {
            JSONSchema.string(
                "kind",
                required: true,
                description: "Edit operation kind.",
                cases: EditFileToolOperationKind.allCases.map(\.rawValue)
            )
            JSONSchema.string(
                "content",
                description: "Content for replace_entire_file, append, prepend, or replace_line. For replace_line, this is the replacement line content and must be one logical line."
            )
            JSONSchema.string(
                "target",
                description: "Existing text to replace for replace_first, replace_all, or replace_unique."
            )
            JSONSchema.string(
                "replacement",
                description: "Replacement text for replace_first, replace_all, or replace_unique. replace_line also accepts this as a compatibility alias, but content is preferred."
            )
            JSONSchema.integer(
                "line",
                description: "1-based line number for replace_line."
            )
            JSONSchema.array(
                "lines",
                description: "Lines for insert_lines, or replacement lines for replace_lines. Each entry must be one logical line with no newline characters.",
                items: JSONSchema.Value.string()
            )
            JSONSchema.integer(
                "position",
                description: "1-based insertion position for insert_lines."
            )
            JSONSchema.Property(
                name: "range",
                schema: EditFileLineRange.schema
            )
            JSONSchema.string(
                "separator",
                description: "Optional separator for append/prepend."
            )
        }
    }
}

public extension EditFileToolInput {
    static var schema: JSONValue {
        JSONSchema.object {
            JSONSchema.string(
                "rootID",
                description: "Workspace root identifier. Usually use 'project'."
            )
            JSONSchema.string(
                "path",
                required: true,
                description: "Path to the file relative to the workspace root."
            )
            JSONSchema.array(
                "operations",
                required: true,
                description: "Ordered edit intent operations to apply. Guard material is derived by the runtime, not supplied by the model.",
                items: EditFileToolOperation.schema
            )
        }
    }
}
