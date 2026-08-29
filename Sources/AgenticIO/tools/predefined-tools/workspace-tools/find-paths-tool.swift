import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import Path
import PathParsing

/// Model-facing input for Find paths.
@JSONSchema
public struct FindPathsToolInput: Sendable, Codable, Hashable {
    /// Optional workspace root identifier.
    public let rootID: PathAccessRootIdentifier?
    /// Optional path-name query.
    public let query: String?
    /// Optional include patterns.
    public let includes: [String]?
    /// Optional exclude patterns.
    public let excludes: [String]?
    /// Whether to scan recursively.
    public let recursive: Bool?
    /// Whether hidden paths are included.
    public let includeHidden: Bool?
    /// Whether directory symlinks are followed.
    public let followSymlinks: Bool?
    /// Whether files are returned.
    public let includeFiles: Bool?
    /// Whether directories are returned.
    public let includeDirectories: Bool?
    /// Optional maximum number of returned paths.
    public let maxEntries: Int?

    public init(
        rootID: PathAccessRootIdentifier? = nil,
        query: String? = nil,
        includes: [String]? = nil,
        excludes: [String]? = nil,
        recursive: Bool? = nil,
        includeHidden: Bool? = nil,
        followSymlinks: Bool? = nil,
        includeFiles: Bool? = nil,
        includeDirectories: Bool? = nil,
        maxEntries: Int? = nil
    ) {
        self.rootID = rootID
        self.query = query
        self.includes = includes
        self.excludes = excludes
        self.recursive = recursive
        self.includeHidden = includeHidden
        self.followSymlinks = followSymlinks
        self.includeFiles = includeFiles
        self.includeDirectories = includeDirectories
        self.maxEntries = maxEntries
    }
}

public struct FindPathsToolEntry: Sendable, Codable, Hashable {
    public let rootID: String
    public let path: String
    public let isDirectory: Bool

    public init(
        rootID: String,
        path: String,
        isDirectory: Bool
    ) {
        self.rootID = rootID
        self.path = path
        self.isDirectory = isDirectory
    }
}

public struct FindPathsToolOutput: Sendable, Codable, Hashable {
    public let rootID: String
    public let entries: [FindPathsToolEntry]
    public let truncated: Bool

    public init(
        rootID: String,
        entries: [FindPathsToolEntry],
        truncated: Bool
    ) {
        self.rootID = rootID
        self.entries = entries
        self.truncated = truncated
    }
}

public struct FindPathsTool: TypedInstanceAgentTool {
    public typealias Input = FindPathsToolInput

    public static let identifier: AgentToolIdentifier = "find_paths"
    public static let description = "Find path names inside an authorized workspace root without reading file contents."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }


    public var risk: ActionRisk {
        Self.risk
    }

    public init() {}

    public func preflight(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            FindPathsToolInput.self,
            from: input
        )
        let rootID = decoded.rootID ?? .project

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: "Find path names in root '\(rootID.rawValue)'.",
            rootIDs: [
                rootID.rawValue
            ],
            capabilitiesRequired: [
                .scan
            ],
            estimatedScanEntries: decoded.maxEntries,
            estimatedScanDepth: decoded.recursive == false ? 1 : nil,
            includesHiddenPaths: decoded.includeHidden ?? false,
            followsSymlinks: decoded.followSymlinks ?? false,
            policyChecks: [
                "workspace_required",
                "path_name_scan_only",
                "no_file_content_access"
            ]
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let workspace = try WorkspaceToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )
        let decoded = try JSONToolBridge.decode(
            FindPathsToolInput.self,
            from: input
        )
        let rootID = decoded.rootID ?? .project
        let recursive = decoded.recursive ?? true
        let maxEntries = max(
            0,
            decoded.maxEntries ?? 100
        )

        let includes = try normalizedIncludes(
            decoded.includes
        ).map {
            try PathParse.expression($0)
        }
        let excludes = try (decoded.excludes ?? []).map {
            try PathParse.expression($0)
        }

        let result = try workspace.scan(
            .init(
                includes: includes,
                excludes: excludes
            ),
            rootID: rootID,
            configuration: .init(
                maxDepth: recursive ? nil : 1,
                includeHidden: decoded.includeHidden ?? false,
                followSymlinks: decoded.followSymlinks ?? false,
                emitDirectories: decoded.includeDirectories ?? true,
                emitFiles: decoded.includeFiles ?? true
            )
        )

        var entries = try workspace.authorizedEntries(
            from: result,
            rootID: rootID,
            capability: .scan,
            toolName: name
        )

        if let query = normalizedQuery(
            decoded.query
        ) {
            entries = entries.filter {
                $0.relativePath.localizedCaseInsensitiveContains(
                    query
                )
            }
        }

        let truncated = entries.count > maxEntries
        if truncated {
            entries = Array(
                entries.prefix(
                    maxEntries
                )
            )
        }

        return try JSONToolBridge.encode(
            FindPathsToolOutput(
                rootID: rootID.rawValue,
                entries: entries.map {
                    .init(
                        rootID: rootID.rawValue,
                        path: $0.relativePath,
                        isDirectory: $0.isDirectory
                    )
                },
                truncated: truncated
            )
        )
    }
}

internal extension FindPathsTool {
    func normalizedIncludes(
        _ values: [String]?
    ) -> [String] {
        let values = values ?? []

        let normalized = values.map {
            $0.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }.filter {
            !$0.isEmpty
        }

        guard !normalized.isEmpty else {
            return [
                "**"
            ]
        }

        return normalized
    }

    func normalizedQuery(
        _ value: String?
    ) -> String? {
        let trimmed = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let trimmed,
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}
