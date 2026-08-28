import Position
import Writers

public struct EditFileToolOutput: Sendable, Codable, Hashable {
    public let rootID: String
    public let path: String
    public let operationCount: Int
    public let changeCount: Int
    public let diffSummary: FileDiffSummary
    public let originalChangedLineRanges: [LineRange]
    public let editedChangedLineRanges: [LineRange]
    public let appliedDiff: String?
    public let appliedDiffTruncated: Bool
    public let appliedDiffArtifactID: String?
    public let originalFingerprint: StandardContentFingerprint?
    public let editedFingerprint: StandardContentFingerprint?
    public let editedChangedSlices: [FileLineSlice]
    public let mutation: AgentFileMutationToolSummary?

    public init(
        rootID: String,
        path: String,
        operationCount: Int,
        changeCount: Int,
        diffSummary: FileDiffSummary,
        originalChangedLineRanges: [LineRange],
        editedChangedLineRanges: [LineRange],
        appliedDiff: String? = nil,
        appliedDiffTruncated: Bool = false,
        appliedDiffArtifactID: String? = nil,
        originalFingerprint: StandardContentFingerprint? = nil,
        editedFingerprint: StandardContentFingerprint? = nil,
        editedChangedSlices: [FileLineSlice] = [],
        mutation: AgentFileMutationToolSummary? = nil
    ) {
        self.rootID = rootID
        self.path = path
        self.operationCount = operationCount
        self.changeCount = changeCount
        self.diffSummary = diffSummary
        self.originalChangedLineRanges = originalChangedLineRanges
        self.editedChangedLineRanges = editedChangedLineRanges
        self.appliedDiff = appliedDiff
        self.appliedDiffTruncated = appliedDiffTruncated
        self.appliedDiffArtifactID = appliedDiffArtifactID
        self.originalFingerprint = originalFingerprint
        self.editedFingerprint = editedFingerprint
        self.editedChangedSlices = editedChangedSlices
        self.mutation = mutation
    }

    public init(
        rootID: String,
        path: String,
        operationCount: Int,
        result: StandardEditResult,
        mutation: AgentFileMutationToolSummary? = nil,
        appliedDiffMaxCharacters: Int = 12_000
    ) {
        let appliedDiff = Self.truncated(
            result.renderedDifference(),
            maxCharacters: appliedDiffMaxCharacters
        )

        self.init(
            rootID: rootID,
            path: path,
            operationCount: operationCount,
            changeCount: result.changeCount,
            diffSummary: .init(
                insertedLineCount: result.insertions,
                deletedLineCount: result.deletions
            ),
            originalChangedLineRanges: result.originalChangedLineRanges,
            editedChangedLineRanges: result.editedChangedLineRanges,
            appliedDiff: appliedDiff.text.isEmpty ? nil : appliedDiff.text,
            appliedDiffTruncated: appliedDiff.truncated,
            appliedDiffArtifactID: mutation?.artifactIDs.first,
            originalFingerprint: result.originalFingerprint,
            editedFingerprint: result.editedFingerprint,
            editedChangedSlices: result.editedChangedSlices(),
            mutation: mutation
        )
    }
}

private extension EditFileToolOutput {
    static func truncated(
        _ text: String,
        maxCharacters: Int
    ) -> (
        text: String,
        truncated: Bool
    ) {
        let maxCharacters = max(
            0,
            maxCharacters
        )

        guard text.count > maxCharacters else {
            return (
                text,
                false
            )
        }

        guard maxCharacters > 0 else {
            return (
                "",
                !text.isEmpty
            )
        }

        return (
            String(
                text.prefix(
                    maxCharacters
                )
            ),
            true
        )
    }
}
