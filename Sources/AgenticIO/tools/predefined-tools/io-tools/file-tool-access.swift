import AgenticWorkspace
import FileTypes
import Path

public enum FileToolAccess {
    public static func authorize(
        workspace: AgentWorkspace?,
        rootID: PathAccessRootIdentifier = .project,
        path rawPath: String,
        capability: PathCapability,
        toolName: String,
        filetype: AnyFileType? = nil,
        type: PathSegmentType? = nil
    ) throws -> AgenticAuthorizedPath {
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
        workspace: AgentWorkspace,
        rootID: PathAccessRootIdentifier = .project,
        path rawPath: String,
        capability: PathCapability,
        toolName: String,
        filetype: AnyFileType? = nil,
        type: PathSegmentType? = nil
    ) throws -> AgenticAuthorizedPath {
        try workspace.accessController.authorize(
            rootID: rootID,
            path: rawPath,
            capability: capability,
            toolName: toolName,
            filetype: filetype,
            type: type
        )
    }

    public static func authorize(
        workspace: AgentWorkspace,
        rootID: PathAccessRootIdentifier = .project,
        path: DescendantPath,
        capability: PathCapability,
        toolName: String,
        type: PathSegmentType? = nil
    ) throws -> AgenticAuthorizedPath {
        try workspace.accessController.authorize(
            rootID: rootID,
            path: path,
            capability: capability,
            toolName: toolName,
            type: type
        )
    }

    public static func presentationPath(
        workspace: AgentWorkspace?,
        rootID: PathAccessRootIdentifier = .project,
        path rawPath: String,
        filetype: AnyFileType? = nil,
        type: PathSegmentType? = nil
    ) throws -> String {
        guard let workspace else {
            return rawPath
        }

        let authorized = try workspace.accessController.paths.authorize(
            rawPath,
            rootIdentifier: rootID,
            filetype: filetype,
            type: type
        )

        return authorized.presentationPath
    }
}
