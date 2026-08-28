public struct ScanPathsToolOutputEntry: Sendable, Codable, Hashable {
    public let path: String
    public let isDirectory: Bool

    public init(
        path: String,
        isDirectory: Bool
    ) {
        self.path = path
        self.isDirectory = isDirectory
    }
}

public struct ScanPathsToolOutput: Sendable, Codable, Hashable {
    public let rootID: String
    public let directory: String?
    public let entries: [ScanPathsToolOutputEntry]
    public let truncated: Bool

    public init(
        rootID: String,
        directory: String?,
        entries: [ScanPathsToolOutputEntry],
        truncated: Bool
    ) {
        self.rootID = rootID
        self.directory = directory
        self.entries = entries
        self.truncated = truncated
    }
}
