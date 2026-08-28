import Position

public struct ReadSelectionToolOutputSlice: Sendable, Codable, Hashable {
    public let lineRange: LineRange?
    public let lineCount: Int
    public let content: String

    public init(
        lineRange: LineRange?,
        lineCount: Int,
        content: String
    ) {
        self.lineRange = lineRange
        self.lineCount = lineCount
        self.content = content
    }
}

public struct ReadSelectionToolOutput: Sendable, Codable, Hashable {
    public let path: String
    public let slices: [ReadSelectionToolOutputSlice]
    public let selectedLineRanges: [LineRange]
    public let selectedLineCount: Int
    public let totalLineCount: Int
    public let byteCount: Int
    public let encoding: String?

    public init(
        path: String,
        slices: [ReadSelectionToolOutputSlice],
        selectedLineRanges: [LineRange],
        selectedLineCount: Int,
        totalLineCount: Int,
        byteCount: Int,
        encoding: String?
    ) {
        self.path = path
        self.slices = slices
        self.selectedLineRanges = selectedLineRanges
        self.selectedLineCount = selectedLineCount
        self.totalLineCount = totalLineCount
        self.byteCount = byteCount
        self.encoding = encoding
    }
}
