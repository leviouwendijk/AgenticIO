import Foundation
import Workspace
import Path
import FileTypes

public enum FileToolAccess {
    public static func authorize(
        workspace: WorkspaceContext?,
        rootID: PathAccessRootIdentifier = .project,
        path rawPath: String,
        capability: WorkspaceCapability,
        toolName: String,
        filetype: AnyFileType? = nil,
        type: PathSegmentType? = nil
    ) throws -> AuthorizedPath {
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: toolName
        )

        return try authorize(
            workspace: workspace,
            rootID: rootID,
            path: rawPath,
            capability: capability,
            toolName: toolName,
            filetype: filetype,
            type: type
        )
    }

    public static func authorize(
        workspace: WorkspaceContext,
        rootID: PathAccessRootIdentifier = .project,
        path rawPath: String,
        capability: WorkspaceCapability,
        toolName: String,
        filetype _: AnyFileType? = nil,
        type _: PathSegmentType? = nil
    ) throws -> AuthorizedPath {
        try requireTargetedRoot(
            rootID,
            workspace: workspace,
            toolName: toolName
        )

        return try workspace.authorize(
            rawPath,
            capability: capability
        ).authorizedPath
    }

    public static func authorize(
        workspace: WorkspaceContext,
        rootID: PathAccessRootIdentifier = .project,
        path: DescendantPath,
        capability: WorkspaceCapability,
        toolName: String,
        type _: PathSegmentType? = nil
    ) throws -> AuthorizedPath {
        try requireTargetedRoot(
            rootID,
            workspace: workspace,
            toolName: toolName
        )

        let absolute = path.relative.url(
            base: workspace.absoluteURL
        )

        return try workspace.authorize(
            absolute.path,
            capability: capability
        ).authorizedPath
    }

    public static func presentationPath(
        workspace: WorkspaceContext?,
        rootID: PathAccessRootIdentifier = .project,
        path rawPath: String,
        filetype _: AnyFileType? = nil,
        type _: PathSegmentType? = nil
    ) throws -> String {
        guard let workspace else {
            return rawPath
        }

        try requireTargetedRoot(
            rootID,
            workspace: workspace,
            toolName: "presentation_path"
        )

        let baseURL = URL(
            fileURLWithPath: workspace.absoluteURL.path,
            isDirectory: true
        )
        let targetURL = URL(
            fileURLWithPath: rawPath,
            relativeTo: baseURL
        )
        .standardizedFileURL

        let relative = targetURL.path
            .dropFirst(
                workspace.absoluteURL.standardizedFileURL.path.count
            )
            .trimmingCharacters(
                in: CharacterSet(
                    charactersIn: "/"
                )
            )

        return relative.isEmpty
            ? "."
            : relative
    }

    private static func requireTargetedRoot(
        _ requested: PathAccessRootIdentifier,
        workspace: WorkspaceContext,
        toolName: String
    ) throws {
        guard requested == workspace.rootIdentifier else {
            throw PredefinedFileToolError.invalidValue(
                tool: toolName,
                field: "rootID",
                reason: "rootID '\(requested.rawValue)' does not match the already-targeted workspace root '\(workspace.rootIdentifier.rawValue)'"
            )
        }
    }
}
