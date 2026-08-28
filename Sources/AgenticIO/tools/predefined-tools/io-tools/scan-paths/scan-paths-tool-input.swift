import Path
import Primitives

public struct ScanPathsToolInput: Sendable, Codable, Hashable {
    public let rootID: PathAccessRootIdentifier
    public let path: String?
    public let excludes: [String]
    public let includeFiles: Bool
    public let includeDirectories: Bool
    public let directoryState: PathDirectoryState?
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
        directoryState: PathDirectoryState? = nil,
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
        self.directoryState = directoryState
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
        case directoryState
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
            directoryState: try container.decodeIfPresent(
                PathDirectoryState.self,
                forKey: .directoryState
            ),
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

    static var schema: JSONValue {
        JSONSchema.object {
            JSONSchema.string(
                "rootID",
                description: "Workspace root identifier. Defaults to project."
            )
            JSONSchema.string(
                "path",
                description: "Optional directory path relative to the selected workspace root. Defaults to the root."
            )
            JSONSchema.array(
                "excludes",
                description: "Optional PathScan exclude patterns.",
                items: JSONSchema.Value.string()
            )
            JSONSchema.boolean(
                "includeFiles",
                description: "Whether file matches are returned. Defaults to true."
            )
            JSONSchema.boolean(
                "includeDirectories",
                description: "Whether directory matches are returned. Defaults to true."
            )
            JSONSchema.string(
                "directoryState",
                description: "Optional literal directory-state filter for emitted directories: 'empty' or 'nonempty'. Hidden entries still make a directory nonempty. File matches are unaffected."
            )
            JSONSchema.boolean(
                "recursive",
                description: "Whether to scan recursively. Defaults to false."
            )
            JSONSchema.boolean(
                "includeHidden",
                description: "Whether hidden paths are included in traversal output. This does not change literal directory emptiness."
            )
            JSONSchema.boolean(
                "followSymlinks",
                description: "Whether directory symlinks are followed. Defaults to false."
            )
            JSONSchema.integer(
                "maxEntries",
                description: "Optional maximum number of returned entries."
            )
        }
    }
}
