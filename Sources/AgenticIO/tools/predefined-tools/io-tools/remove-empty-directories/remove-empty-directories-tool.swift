import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import IO
import Path
import Primitives
import Schema
import SchemaMacros

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

public struct RemoveEmptyDirectoriesToolOutput:
    Sendable,
    Codable,
    Hashable
{
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

public struct RemoveEmptyDirectoriesTool:
    TypedInstanceAgentTool
{
    public typealias Input = RemoveEmptyDirectoriesToolInput
    public static let identifier:
        AgentToolIdentifier =
            "remove_empty_directories"

    public static let description =
        """
        Remove explicitly named workspace directories only when they are real, non-symlink directories containing zero entries.
        """

    public static let risk:
        ActionRisk = .boundedmutate


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
            RemoveEmptyDirectoriesToolInput.self,
            from: input
        )
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )
        let authorized = try authorizedPaths(
            decoded,
            workspace: workspace
        )

        try requireEmptyDirectories(
            authorized
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace.rootURL.path,
            targetPaths: authorized.map(
                \.presentationPath
            ),
            summary: "Remove \(authorized.count) explicitly named empty director\(authorized.count == 1 ? "y" : "ies").",
            estimatedWriteCount: authorized.count,
            sideEffects: [
                "Removes only the named directories.",
                "Does not recurse and never removes directory contents.",
            ],
            rootIDs: Array(
                Set(
                    authorized.map {
                        $0.rootID.rawValue
                    }
                )
            ).sorted(),
            capabilitiesRequired: [
                .write,
            ],
            isPreview: true,
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
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let decoded = try JSONToolBridge.decode(
            RemoveEmptyDirectoriesToolInput.self,
            from: input
        )
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )
        let authorized = try authorizedPaths(
            decoded,
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

        return try JSONToolBridge.encode(
            RemoveEmptyDirectoriesToolOutput(
                removed: authorized.map(
                    \.presentationPath
                )
            )
        )
    }

    public func processResult(
        input _: JSONValue,
        output: JSONValue,
        workspace _: AgentWorkspace?
    ) -> AgentToolResultProcessing {
        guard let result = try? JSONToolBridge.decode(
            RemoveEmptyDirectoriesToolOutput.self,
            from: output
        ) else {
            return .none
        }

        return .init(
            projection: .init(
                status: "passed",
                summary: "Removed \(result.removed.count) empty director\(result.removed.count == 1 ? "y" : "ies").",
                facts: result.removed.map {
                    .init(
                        label: $0,
                        value: "removed"
                    )
                }
            )
        )
    }
}

private extension RemoveEmptyDirectoriesTool {
    func authorizedPaths(
        _ input: RemoveEmptyDirectoriesToolInput,
        workspace: AgentWorkspace
    ) throws -> [AgenticAuthorizedPath] {
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
                toolName: name,
                type: .directory
            )
        }
    }

    func requireEmptyDirectories(
        _ paths: [AgenticAuthorizedPath]
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
