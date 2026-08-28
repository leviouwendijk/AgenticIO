public struct FileDiffSummary: Sendable, Codable, Hashable {
    public let insertedLineCount: Int
    public let deletedLineCount: Int

    public init(
        insertedLineCount: Int = 0,
        deletedLineCount: Int = 0
    ) {
        self.insertedLineCount = insertedLineCount
        self.deletedLineCount = deletedLineCount
    }

    public static let empty = Self()
}
