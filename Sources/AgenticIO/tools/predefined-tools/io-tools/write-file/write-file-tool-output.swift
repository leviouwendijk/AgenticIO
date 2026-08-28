import Position

public struct WriteFileToolOutput: Sendable, Codable, Hashable {
    public let rootID: String
    public let path: String
    public let bytesWritten: Int
    public let diffSummary: FileDiffSummary
    public let changeCount: Int
    public let originalChangedLineRanges: [LineRange]
    public let editedChangedLineRanges: [LineRange]
    public let mutation: AgentFileMutationToolSummary?

    public init(
        rootID: String,
        path: String,
        bytesWritten: Int,
        diffSummary: FileDiffSummary,
        changeCount: Int,
        originalChangedLineRanges: [LineRange],
        editedChangedLineRanges: [LineRange],
        mutation: AgentFileMutationToolSummary? = nil
    ) {
        self.rootID = rootID
        self.path = path
        self.bytesWritten = bytesWritten
        self.diffSummary = diffSummary
        self.changeCount = changeCount
        self.originalChangedLineRanges = originalChangedLineRanges
        self.editedChangedLineRanges = editedChangedLineRanges
        self.mutation = mutation
    }
}
