import Position

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

public struct ReadFileToolOutput: Sendable, Codable, Hashable {
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
