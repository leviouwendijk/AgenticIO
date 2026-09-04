import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import Path
import PathParsing

public struct ScanPathsTool: AgentTool {
    public typealias Input = ScanPathsToolInput
    public typealias Output = ScanPathsToolOutput

    public static let identifier: AgentToolIdentifier = "scan_paths"
    public static let description = "Scan paths inside an authorized workspace root using PathScan, with optional literal directory-state filtering."
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
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {

        let directory = try resolvedDirectoryForPreflight(
            from: input,
            workspace: context.workspace
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
            for: input,
            directory: directory
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            targetPaths: targetPaths,
            summary: input.excludes.isEmpty
                ? summary
                : "\(summary) with \(input.excludes.count) exclude pattern(s)",
            rootIDs: [
                input.rootID.rawValue
            ],
            capabilitiesRequired: [
                .scan
            ],
            estimatedScanEntries: input.maxEntries,
            estimatedScanDepth: input.recursive ? nil : 1,
            includesHiddenPaths: input.includeHidden,
            followsSymlinks: input.followSymlinks,
            policyChecks: [
                "workspace_required",
                "root_path_resolved",
                "scan_configuration_estimated"
            ]
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {
        let workspace = try FileToolSupport.requireWorkspace(
            context.workspace,
            toolName: name
        )


        let directory = try authorizedDirectoryForCall(
            from: input,
            workspace: workspace
        )

        let specification = try ParsedPathScan.specification(
            includes: [
                includePattern(
                    directory: directory,
                    recursive: input.recursive
                )
            ],
            excludes: input.excludes
        )

        let result = try workspace.scan(
            specification,
            rootID: input.rootID,
            configuration: .init(
                maxDepth: input.recursive ? nil : 1,
                includeHidden: input.includeHidden,
                followSymlinks: input.followSymlinks,
                emitDirectories: input.includeDirectories,
                emitFiles: input.includeFiles,
                directoryState: input.directoryState
            )
        )

        var entries = try workspace.authorizedEntries(
            from: result,
            rootID: input.rootID,
            capability: .scan,
            toolName: name,
            excluding: directory
        )

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

        return ScanPathsToolOutput(
            rootID: input.rootID.rawValue,
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
        
    }
}

private extension ScanPathsTool {
    func resolvedDirectoryForPreflight(
        from input: ScanPathsToolInput,
        workspace: AgentWorkspace?
    ) throws -> DescendantPath? {
        guard let trimmedPath = normalizedDirectoryPath(
            input.path
        ) else {
            return nil
        }

        guard let workspace else {
            return nil
        }

        let directory = try workspace.resolve(
            rootID: input.rootID,
            trimmedPath,
            type: .directory
        )

        if try workspace.existingType(
            of: directory
        ) == .file {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "path",
                reason: "must reference a directory, not a file"
            )
        }

        return directory
    }

    func authorizedDirectoryForCall(
        from input: ScanPathsToolInput,
        workspace: AgentWorkspace
    ) throws -> DescendantPath? {
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
            of: authorized.path
        ) == .file {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "path",
                reason: "must reference a directory, not a file"
            )
        }

        return authorized.path
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
        directory: DescendantPath?,
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
        directory: DescendantPath?
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