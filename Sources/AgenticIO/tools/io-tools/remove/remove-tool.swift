import Agentic
import Workspace
import Foundation
import IO
import Path
import Primitives
import Schema
import Macros

public enum RemoveToolError:
    Error,
    Sendable,
    LocalizedError
{
    case emptyInput
    case missing(String)
    case notDirectory(String)
    case symbolicLink(String)
    case notEmpty(String, entryCount: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "remove requires at least one path."
        case .missing(let path):
            return "Directory does not exist: \(path)"
        case .notDirectory(let path):
            return "Path is not a directory: \(path). Delete files with mutate (kind delete), which keeps a backup for rollback."
        case .symbolicLink(let path):
            return "Refusing to remove a symbolic-link directory path: \(path)"
        case .notEmpty(let path, let entryCount):
            return "Directory is not empty: \(path) (\(entryCount) entries). Pass recursive: true to remove it with its contents."
        }
    }
}

public extension SystemIO.Tools {
    @Tool
    struct Remove: Tool {
        /// Remove directories. Without recursive, each must be empty.
        @JSONSchema
        public struct Input: HashableSource
        {
            /// Workspace root identifier. Defaults to project.
            public let rootID: PathAccessRootIdentifier?

            /// Directory paths to remove. Files are deleted with mutate instead.
            public let paths: [String]

            /// Whether directories are removed with their contents. Defaults to false: each must be empty. Not reversible.
            @Schema(required: false)
            public let recursive: Bool

            public init(
                rootID: PathAccessRootIdentifier? = nil,
                paths: [String],
                recursive: Bool = false
            ) {
                self.rootID = rootID
                self.paths = paths
                self.recursive = recursive
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let removed: [String]

            public init(
                removed: [String]
            ) {
                self.removed = removed
            }
        }

        public static let purpose =
            """
            Remove workspace directories: empty ones by default, with their contents when recursive. Files are deleted with mutate, which can roll back.
            """

        public static let risk:
            ActionRisk = .boundedmutate


        public init() {}

        public func preflight(
            _ input: Input,
            in context: ToolContext
        ) async throws -> ToolPreflight {
            let workspace = try FileToolSupport.requireWorkspace(
                context.workspace,
                toolName: Self.identifier.rawValue
            )
            let authorized = try authorizedPaths(
                input,
                workspace: workspace
            )

            try requireDirectories(
                authorized,
                empty: !input.recursive
            )

            let noun = authorized.count == 1 ? "directory" : "directories"

            return .init(
                tool: Self.definition.identifier,
                // Recursive removal cannot be rolled back, so it asks first.
                risk: input.recursive ? .privileged : risk,
                summary: input.recursive
                    ? "Remove \(authorized.count) \(noun) with their contents."
                    : "Remove \(authorized.count) empty \(noun).",
                access: .init(
                    targets: authorized.map(
                        \.presentationPath
                    ),
                    roots: Array(
                        Set(
                            authorized.map {
                                $0.rootIdentifier.rawValue
                            }
                        )
                    ).sorted(),
                    capabilities: [
                        .write,
                    ]
                ),
                estimates: .init(
                    write: .init(
                        count: authorized.count
                    )
                ),
                sideEffects: input.recursive
                    ? [
                        "Removes the named directories and everything below them.",
                        "Not recorded as a file mutation; cannot be rolled back.",
                    ]
                    : [
                        "Removes only the named directories.",
                        "Does not recurse and never removes directory contents.",
                    ],
                policyChecks: [
                    "workspace_required",
                    "workspace_paths_authorized",
                    "directory_required",
                    "symlink_rejected",
                    input.recursive
                        ? "recursive_removal"
                        : "literal_empty_directory_required",
                ]
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let workspace = try FileToolSupport.requireWorkspace(
                context.workspace,
                toolName: Self.identifier.rawValue
            )
            let authorized = try authorizedPaths(
                input,
                workspace: workspace
            )

            try requireDirectories(
                authorized,
                empty: !input.recursive
            )

            for path in authorized {
                try FileSystem.default.remove(
                    path.absoluteURL
                )
            }

            return Output(
                removed: authorized.map(
                    \.presentationPath
                )
            )
        }

        public func process(
            _ output: Output,
            input _: Input
        ) -> ToolExecution.Projection? {
            let result = output

            return .init(
                status: "passed",
                summary: "Removed \(result.removed.count) director\(result.removed.count == 1 ? "y" : "ies").",
                facts: result.removed.map {
                    .init(
                        label: $0,
                        value: "removed"
                    )
                }
            )
        }
    }
}

private extension SystemIO.Tools.Remove {
    func authorizedPaths(
        _ input: SystemIO.Tools.Remove.Input,
        workspace: WorkspaceContext
    ) throws -> [AuthorizedPath] {
        guard !input.paths.isEmpty else {
            throw RemoveToolError.emptyInput
        }

        let rootID = input.rootID ?? .project

        return try input.paths.map { path in
            try FileToolAccess.authorize(
                workspace: workspace,
                rootID: rootID,
                path: path,
                capability: .write,
                toolName: Self.identifier.rawValue,
                type: .directory
            )
        }
    }

    func requireDirectories(
        _ paths: [AuthorizedPath],
        empty: Bool
    ) throws {
        for path in paths {
            let snapshot = try FileInspector(
                path.absoluteURL
            ).inspect()

            guard snapshot.existed else {
                throw RemoveToolError.missing(
                    path.presentationPath
                )
            }

            if snapshot.kind == .symlink {
                throw RemoveToolError.symbolicLink(
                    path.presentationPath
                )
            }

            guard snapshot.kind == .directory else {
                throw RemoveToolError.notDirectory(
                    path.presentationPath
                )
            }

            guard empty else {
                continue
            }

            let contents = try FileSystem.default.directory.contents(
                path.absoluteURL
            )

            guard contents.isEmpty else {
                throw RemoveToolError.notEmpty(
                    path.presentationPath,
                    entryCount: contents.count
                )
            }
        }
    }
}
