import Agentic
import AgenticExecution
import Workspace
import Foundation
import IO
import Path
import Primitives
import Schema
import Macros

@JSONSchema
public struct RemoveEmptyDirectoriesToolInput:
    Sendable,
    Codable,
    Hashable
{
    /// Workspace root identifier. Defaults to project.
    public let rootID: PathAccessRootIdentifier?

    /// Directory paths to remove only if each is literally empty.
    public let paths: [String]

    public init(
        rootID: PathAccessRootIdentifier? = nil,
        paths: [String]
    ) {
        self.rootID = rootID
        self.paths = paths
    }

}

public struct RemoveEmptyDirectoriesToolOutput: Result, Hashable {
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

public enum RemoveEmptyDirectoriesToolError:
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
            return "remove_empty_directories requires at least one path."

        case .missing(let path):
            return "Directory does not exist: \(path)"

        case .notDirectory(let path):
            return "Path is not a directory: \(path)"

        case .symbolicLink(let path):
            return "Refusing to remove a symbolic-link directory path: \(path)"

        case .notEmpty(let path, let entryCount):
            return "Directory is not empty: \(path) (\(entryCount) entries)"
        }
    }
}

public extension SystemIO.Tools {
    @Tool
    struct RemoveEmptyDirectories: Tool {
        public typealias Input = RemoveEmptyDirectoriesToolInput
        public typealias Output = RemoveEmptyDirectoriesToolOutput
        public static let purpose =
            """
            Remove explicitly named workspace directories only when they are real, non-symlink directories containing zero entries.
            """

        public static let risk:
            ActionRisk = .boundedmutate


        public init() {}

        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            let workspace = try FileToolSupport.requireWorkspace(
                workspace,
                toolName: Self.identifier.rawValue
            )
            let authorized = try authorizedPaths(
                input,
                workspace: workspace
            )

            try requireEmptyDirectories(
                authorized
            )

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "Remove \(authorized.count) explicitly named empty director\(authorized.count == 1 ? "y" : "ies").",
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
                sideEffects: [
                    "Removes only the named directories.",
                    "Does not recurse and never removes directory contents.",
                ],
                policyChecks: [
                    "workspace_required",
                    "workspace_paths_authorized",
                    "directory_required",
                    "symlink_rejected",
                    "literal_empty_directory_required",
                    "non_recursive_removal",
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
            let authorized = try authorizedPaths(
                input,
                workspace: workspace
            )

            try requireEmptyDirectories(
                authorized
            )

            for path in authorized {
                try FileSystem.default.remove(
                    path.absoluteURL
                )
            }

            return RemoveEmptyDirectoriesToolOutput(
                removed: authorized.map(
                    \.presentationPath
                )
            )
            
        }

        public func process(
            _ output: Output,
            input _: Input
        ) -> ToolCall.ResultProjection? {
            let result = output

            return .init(
                status: "passed",
                summary: "Removed \(result.removed.count) empty director\(result.removed.count == 1 ? "y" : "ies").",
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

private extension SystemIO.Tools.RemoveEmptyDirectories {
    func authorizedPaths(
        _ input: RemoveEmptyDirectoriesToolInput,
        workspace: WorkspaceContext
    ) throws -> [AuthorizedPath] {
        guard !input.paths.isEmpty else {
            throw RemoveEmptyDirectoriesToolError.emptyInput
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

    func requireEmptyDirectories(
        _ paths: [AuthorizedPath]
    ) throws {
        for path in paths {
            let snapshot = try FileInspector(
                path.absoluteURL
            ).inspect()

            guard snapshot.existed else {
                throw RemoveEmptyDirectoriesToolError.missing(
                    path.presentationPath
                )
            }

            if snapshot.kind == .symlink {
                throw RemoveEmptyDirectoriesToolError.symbolicLink(
                    path.presentationPath
                )
            }

            guard snapshot.kind == .directory else {
                throw RemoveEmptyDirectoriesToolError.notDirectory(
                    path.presentationPath
                )
            }

            let contents = try FileSystem.default.directory.contents(
                path.absoluteURL
            )

            guard contents.isEmpty else {
                throw RemoveEmptyDirectoriesToolError.notEmpty(
                    path.presentationPath,
                    entryCount: contents.count
                )
            }
        }
    }
}
