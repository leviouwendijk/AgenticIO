import Agentic
import AgenticExecution
import Workspace
import Foundation
import Primitives
import Schema
import Path
import PathParsing
import Macros

private extension SystemIO.Tools.ScanPaths.Input {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case excludes
        case includeFiles
        case includeDirectories
        case directoryState
        case recursive
        case maxdepth
        case includeHidden
        case followSymlinks
        case maxEntries
    }
}

public extension SystemIO.Tools.ScanPaths.Input {
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
            maxdepth: try container.decodeIfPresent(
                Int.self,
                forKey: .maxdepth
            ),
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

public extension SystemIO.Tools {
    @Tool
    struct ScanPaths: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            /// Workspace root identifier. Defaults to project.
            @Schema(required: false)
            public let rootID: PathAccessRootIdentifier

            /// Optional directory path relative to the selected workspace root. Defaults to the root.
            public let path: String?

            /// Optional PathScan exclude patterns.
            @Schema(required: false)
            public let excludes: [String]

            /// Whether file matches are returned. Defaults to true.
            @Schema(required: false)
            public let includeFiles: Bool

            /// Whether directory matches are returned. Defaults to true.
            @Schema(required: false)
            public let includeDirectories: Bool

            /// Optional literal directory-state filter for emitted directories: 'empty' or 'nonempty'. Hidden entries still make a directory nonempty. File matches are unaffected.
            public let directoryState: PathDirectoryState?

            /// Whether to scan recursively when maxdepth is omitted. Defaults to false.
            @Schema(required: false)
            public let recursive: Bool

            /// Optional maximum traversal depth. When provided, this overrides recursive.
            public let maxdepth: Int?

            /// Whether hidden paths are included in traversal output. This does not change literal directory emptiness.
            @Schema(required: false)
            public let includeHidden: Bool

            /// Whether directory symlinks are followed. Defaults to false.
            @Schema(required: false)
            public let followSymlinks: Bool

            /// Optional maximum number of returned entries.
            public let maxEntries: Int?

            public init(
                rootID: PathAccessRootIdentifier = .project,
                path: String? = nil,
                excludes: [String] = [],
                includeFiles: Bool = true,
                includeDirectories: Bool = true,
                directoryState: PathDirectoryState? = nil,
                recursive: Bool = false,
                maxdepth: Int? = nil,
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
                self.maxdepth = maxdepth
                self.includeHidden = includeHidden
                self.followSymlinks = followSymlinks
                self.maxEntries = maxEntries
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

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


        public static let purpose = "Scan path topology inside the targeted workspace context using PathScan, with optional bounded traversal depth and literal directory-state filtering."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            let targetPath: String

            if let workspace {
                try requireTargetedRoot(
                    input.rootID,
                    workspace: workspace
                )
                let authorized = try workspace.authorize(
                    normalizedDirectoryPath(input.path) ?? ".",
                    capability: .scan
                ).authorizedPath
                try requireDirectory(
                    authorized,
                    field: "path"
                )
                targetPath = authorized.presentationPath
            } else {
                targetPath = normalizedDirectoryPath(input.path) ?? "."
            }

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: input.recursive
                    ? "Recursively scan \(targetPath)"
                    : "Scan direct entries in \(targetPath)",
                access: .init(
                    targets: [
                        targetPath
                    ],
                    roots: workspace.map {
                        [
                            $0.rootIdentifier.rawValue
                        ]
                    } ?? [
                        input.rootID.rawValue
                    ],
                    capabilities: [
                        .scan
                    ],
                    includesHidden: input.includeHidden,
                    followsSymlinks: input.followSymlinks
                ),
                estimates: .init(
                    scan: .init(
                        entries: input.maxEntries,
                        depth: resolvedMaxDepth(
                            for: input
                        )
                    )
                ),
                policyChecks: [
                    "workspace_required",
                    "workspace_context_already_targeted",
                    "scan_path_authorized",
                    "scan_configuration_estimated"
                ]
            )
        }

        public func call(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> Output {
            let workspace = try FileToolSupport.requireWorkspace(
                workspace,
                toolName: Self.identifier.rawValue
            )
            try requireTargetedRoot(
                input.rootID,
                workspace: workspace
            )

            let directoryInput = normalizedDirectoryPath(
                input.path
            ) ?? "."
            let directory = try workspace.authorize(
                directoryInput,
                capability: .scan
            ).authorizedPath
            try requireDirectory(
                directory,
                field: "path"
            )

            let specification = try ParsedPathScan.specification(
                includes: [
                    usesRecursivePattern(for: input)
                        ? "**"
                        : "*"
                ],
                excludes: input.excludes
            )
            let result = try PathScan.scan(
                specification,
                relativeTo: .directoryURL(
                    directory.absoluteURL
                ),
                configuration: .init(
                    maxDepth: resolvedMaxDepth(
                        for: input
                    ),
                    includeHidden: input.includeHidden,
                    followSymlinks: input.followSymlinks,
                    emitDirectories: input.includeDirectories,
                    emitFiles: input.includeFiles,
                    directoryState: input.directoryState
                )
            )

            var entries = try result.matches.compactMap { match -> ScanPathsAuthorizedEntry? in
                guard match.url.standardizedFileURL != directory.absoluteURL.standardizedFileURL else {
                    return nil
                }

                let authorized = try workspace.authorize(
                    match.url.path,
                    capability: .scan
                ).authorizedPath

                return .init(
                    path: authorized.presentationPath,
                    isDirectory: match.type == .directory
                )
            }

            let truncated: Bool
            if let maxEntries = input.maxEntries,
               maxEntries >= 0,
               entries.count > maxEntries {
                entries = Array(
                    entries.prefix(
                        maxEntries
                    )
                )
                truncated = true
            } else {
                truncated = false
            }

            return Output(
                rootID: workspace.rootIdentifier.rawValue,
                directory: normalizedDirectoryPath(input.path).map { _ in
                    directory.presentationPath
                },
                entries: entries.map {
                    .init(
                        path: $0.path,
                        isDirectory: $0.isDirectory
                    )
                },
                truncated: truncated
            )
        }
    }
}

private struct ScanPathsAuthorizedEntry {
    let path: String
    let isDirectory: Bool
}

private extension SystemIO.Tools.ScanPaths {
    func requireTargetedRoot(
        _ requested: PathAccessRootIdentifier,
        workspace: WorkspaceContext
    ) throws {
        guard requested == workspace.rootIdentifier else {
            throw PredefinedFileToolError.invalidValue(
                tool: Self.identifier.rawValue,
                field: "rootID",
                reason: "rootID '\(requested.rawValue)' does not match the already-targeted workspace root '\(workspace.rootIdentifier.rawValue)'"
            )
        }
    }

    func requireDirectory(
        _ authorized: AuthorizedPath,
        field: String
    ) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: authorized.absoluteURL.path,
            isDirectory: &isDirectory
        ) else {
            return
        }

        guard isDirectory.boolValue else {
            throw PredefinedFileToolError.invalidValue(
                tool: Self.identifier.rawValue,
                field: field,
                reason: "must reference a directory, not a file"
            )
        }
    }

    func normalizedDirectoryPath(
        _ value: String?
    ) -> String? {
        guard let trimmed = value?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
              !trimmed.isEmpty,
              trimmed != "." else {
            return nil
        }

        return trimmed
    }

    func resolvedMaxDepth(
        for input: SystemIO.Tools.ScanPaths.Input
    ) -> Int? {
        if let maxdepth = input.maxdepth {
            return max(
                0,
                maxdepth
            )
        }

        return input.recursive
            ? nil
            : 1
    }

    func usesRecursivePattern(
        for input: SystemIO.Tools.ScanPaths.Input
    ) -> Bool {
        guard let maxDepth = resolvedMaxDepth(
            for: input
        ) else {
            return true
        }

        return maxDepth > 1
    }
}
