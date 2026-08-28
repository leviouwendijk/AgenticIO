import Path

public struct ScanPathsToolInput: Sendable, Codable, Hashable {
    public let rootID: PathAccessRootIdentifier
    public let path: String?
    public let excludes: [String]
    public let includeFiles: Bool
    public let includeDirectories: Bool
    public let recursive: Bool
    public let includeHidden: Bool
    public let followSymlinks: Bool
    public let maxEntries: Int?

    public init(
        rootID: PathAccessRootIdentifier = .project,
        path: String? = nil,
        excludes: [String] = [],
        includeFiles: Bool = true,
        includeDirectories: Bool = true,
        recursive: Bool = false,
        includeHidden: Bool = false,
        followSymlinks: Bool = false,
        maxEntries: Int? = nil
    ) {
        self.rootID = rootID
        self.path = path
        self.excludes = excludes
        self.includeFiles = includeFiles
        self.includeDirectories = includeDirectories
        self.recursive = recursive
        self.includeHidden = includeHidden
        self.followSymlinks = followSymlinks
        self.maxEntries = maxEntries
    }
}

private extension ScanPathsToolInput {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case excludes
        case includeFiles
        case includeDirectories
        case recursive
        case includeHidden
        case followSymlinks
        case maxEntries
    }
}

public extension ScanPathsToolInput {
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
            path: try container.decodeIfPresent(
                String.self,
                forKey: .path
            ),
            excludes: try container.decodeIfPresent(
                [String].self,
                forKey: .excludes
            ) ?? [],
            includeFiles: try container.decodeIfPresent(
                Bool.self,
                forKey: .includeFiles
            ) ?? true,
            includeDirectories: try container.decodeIfPresent(
                Bool.self,
                forKey: .includeDirectories
            ) ?? true,
            recursive: try container.decodeIfPresent(
                Bool.self,
                forKey: .recursive
            ) ?? false,
            includeHidden: try container.decodeIfPresent(
                Bool.self,
                forKey: .includeHidden
            ) ?? false,
            followSymlinks: try container.decodeIfPresent(
                Bool.self,
                forKey: .followSymlinks
            ) ?? false,
            maxEntries: try container.decodeIfPresent(
                Int.self,
                forKey: .maxEntries
            )
        )
    }
}
