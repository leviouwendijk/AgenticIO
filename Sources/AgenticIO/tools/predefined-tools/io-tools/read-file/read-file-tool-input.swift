import Path
import Schema

@JSONSchema
public struct ReadFileToolInput: Sendable, Codable, Hashable {
    /// Workspace root identifier. Usually use 'project'.
    @Schema(required: false)
    public let rootID: PathAccessRootIdentifier

    /// Path to the file relative to the workspace root.
    public let path: String

    /// Optional 1-based first line to read.
    public let startLine: Int?

    /// Optional 1-based final line to read.
    public let endLine: Int?

    /// Optional maximum number of lines to read.
    public let maxLines: Int?

    /// Whether to include numbered display text in the returned display field. The content field always remains raw source text.
    @Schema(required: false)
    public let includeLineNumbers: Bool

    public init(
        rootID: PathAccessRootIdentifier = .project,
        path: String,
        startLine: Int? = nil,
        endLine: Int? = nil,
        maxLines: Int? = nil,
        includeLineNumbers: Bool = false
    ) {
        self.rootID = rootID
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.maxLines = maxLines
        self.includeLineNumbers = includeLineNumbers
    }
}

private extension ReadFileToolInput {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case startLine
        case endLine
        case maxLines
        case includeLineNumbers
    }
}

public extension ReadFileToolInput {
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
            startLine: try container.decodeIfPresent(
                Int.self,
                forKey: .startLine
            ),
            endLine: try container.decodeIfPresent(
                Int.self,
                forKey: .endLine
            ),
            maxLines: try container.decodeIfPresent(
                Int.self,
                forKey: .maxLines
            ),
            includeLineNumbers: try container.decodeIfPresent(
                Bool.self,
                forKey: .includeLineNumbers
            ) ?? false
        )
    }
}
