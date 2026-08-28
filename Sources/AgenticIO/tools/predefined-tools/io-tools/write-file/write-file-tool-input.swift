import Path

public struct WriteFileToolInput: Sendable, Codable, Hashable {
    public let rootID: PathAccessRootIdentifier
    public let path: String
    public let content: String

    public init(
        rootID: PathAccessRootIdentifier = .project,
        path: String,
        content: String
    ) {
        self.rootID = rootID
        self.path = path
        self.content = content
    }
}

private extension WriteFileToolInput {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case content
    }
}

public extension WriteFileToolInput {
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
            content: try container.decode(
                String.self,
                forKey: .content
            )
        )
    }
}
