import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Path
import PathParsing

public struct ScanPathsTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "scan_paths"
    public static let description = "Scan paths inside an authorized workspace root using PathScan."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }

    public var inputSchema: JSONValue? {
        nil
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
            ScanPathsToolInput.self,
            from: input
        )

        let directory = try resolvedDirectoryForPreflight(
            from: decoded,
            workspace: workspace
        )

        let targetPaths: [String]
        if let directory {
            targetPaths = [
                directory.presentingRelative(
                    filetype: true
                )
            ]
        } else {
            targetPaths = [
                "."
            ]
        }

        let summary = summary(
            for: decoded,
            directory: directory
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            targetPaths: targetPaths,
            summary: decoded.excludes.isEmpty
                ? summary
                : "\(summary) with \(decoded.excludes.count) exclude pattern(s)",
            rootIDs: [
                decoded.rootID.rawValue
            ],
            capabilitiesRequired: [
                .scan
            ],
            estimatedScanEntries: decoded.maxEntries,
            estimatedScanDepth: decoded.recursive ? nil : 1,
            includesHiddenPaths: decoded.includeHidden,
            followsSymlinks: decoded.followSymlinks,
            policyChecks: [
                "workspace_required",
                "root_path_resolved",
                "scan_configuration_estimated"
            ]
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )

        let decoded = try JSONToolBridge.decode(
            ScanPathsToolInput.self,
            from: input
        )

        let directory = try authorizedDirectoryForCall(
            from: decoded,
            workspace: workspace
        )

        let specification = try ParsedPathScan.specification(
            includes: [
                includePattern(
                    directory: directory,
                    recursive: decoded.recursive
                )
            ],
            excludes: decoded.excludes
        )

        let result = try workspace.scan(
            specification,
            rootID: decoded.rootID,
            configuration: .init(
                maxDepth: decoded.recursive ? nil : 1,
                includeHidden: decoded.includeHidden,
                followSymlinks: decoded.followSymlinks,
                emitDirectories: decoded.includeDirectories,
                emitFiles: decoded.includeFiles
            )
        )

        var entries = try workspace.authorizedEntries(
            from: result,
            rootID: decoded.rootID,
            capability: .scan,
            toolName: name,
            excluding: directory
        )

        let truncated: Bool
        if let maxEntries = decoded.maxEntries,
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

        return try JSONToolBridge.encode(
            ScanPathsToolOutput(
                rootID: decoded.rootID.rawValue,
                directory: directory?.presentingRelative(
                    filetype: true
                ),
                entries: entries.map { entry in
                    .init(
                        path: entry.relativePath,
                        isDirectory: entry.isDirectory
                    )
                },
                truncated: truncated
            )
        )
    }
}

private extension ScanPathsTool {
    func resolvedDirectoryForPreflight(
        from input: ScanPathsToolInput,
        workspace: AgentWorkspace?
    ) throws -> ScopedPath? {
        guard let trimmedPath = normalizedDirectoryPath(
            input.path
        ) else {
            return nil
        }

        guard let workspace else {
            return nil
        }

        let scoped = try workspace.resolve(
            rootID: input.rootID,
            trimmedPath,
            type: .directory
        )

        if try workspace.existingType(
            of: scoped
        ) == .file {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "path",
                reason: "must reference a directory, not a file"
            )
        }

        return scoped
    }

    func authorizedDirectoryForCall(
        from input: ScanPathsToolInput,
        workspace: AgentWorkspace
    ) throws -> ScopedPath? {
        guard let trimmedPath = normalizedDirectoryPath(
            input.path
        ) else {
            _ = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: input.rootID,
                path: ".",
                capability: .scan,
                toolName: name,
                type: .directory
            )

            return nil
        }

        let authorized = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: input.rootID,
            path: trimmedPath,
            capability: .scan,
            toolName: name,
            type: .directory
        )

        if try workspace.existingType(
            of: authorized.scopedPath
        ) == .file {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "path",
                reason: "must reference a directory, not a file"
            )
        }

        return authorized.scopedPath
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

    func includePattern(
        directory: ScopedPath?,
        recursive: Bool
    ) -> String {
        guard let directory else {
            return recursive ? "**" : "*"
        }

        let rendered = directory.presentingRelative(
            filetype: true
        )

        return recursive
            ? "\(rendered)/**"
            : "\(rendered)/*"
    }

    func summary(
        for input: ScanPathsToolInput,
        directory: ScopedPath?
    ) -> String {
        if let directory {
            return input.recursive
                ? "Recursively scan \(directory.presentingRelative(filetype: true))"
                : "Scan direct entries in \(directory.presentingRelative(filetype: true))"
        }

        return input.recursive
            ? "Recursively scan workspace root"
            : "Scan direct entries in workspace root"
    }
}
