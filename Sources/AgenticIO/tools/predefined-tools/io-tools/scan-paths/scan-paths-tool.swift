import Agentic
import AgenticExecution
import Workspace
import Foundation
import Primitives
import Schema
import Path
import PathParsing

public extension SystemIO.Tools {
    @Tool
    struct ScanPaths: Tool {
        public typealias Input = ScanPathsToolInput
        public typealias Output = ScanPathsToolOutput

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

            return ScanPathsToolOutput(
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
        for input: ScanPathsToolInput
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
        for input: ScanPathsToolInput
    ) -> Bool {
        guard let maxDepth = resolvedMaxDepth(
            for: input
        ) else {
            return true
        }

        return maxDepth > 1
    }
}
