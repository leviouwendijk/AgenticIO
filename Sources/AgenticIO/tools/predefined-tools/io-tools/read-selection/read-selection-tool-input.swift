import Selection

public struct ReadSelectionToolInput: Sendable, Codable, Hashable {
    public let path: String
    public let selections: [ContentSelection]
    public let includeLineNumbers: Bool

    public init(
        path: String,
        selections: [ContentSelection] = [],
        includeLineNumbers: Bool = false
    ) {
        self.path = path
        self.selections = selections
        self.includeLineNumbers = includeLineNumbers
    }
}
