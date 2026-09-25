import Workspace
import Concatenation
import Foundation
import Path
import PathParsing
import Selection
import SelectionParsing

public struct ContextComposer: Sendable {
    public let workspace: WorkspaceContext?

    public init(
        workspace: WorkspaceContext? = nil
    ) {
        self.workspace = workspace
    }

    func validate(
        _ plan: ContextCompositionPlan,
        workspace: WorkspaceContext? = nil
    ) throws {
        var fileSources: [ContextFileSource] = []

        for source in plan.sources {
            if case .files(let fileSource) = source {
                fileSources.append(fileSource)
            }
        }

        guard !fileSources.isEmpty else {
            return
        }

        guard let workspace = workspace ?? self.workspace else {
            throw ContextComposerError.workspaceRequired
        }

        for source in fileSources {
            guard source.rootID == workspace.rootIdentifier else {
                throw ContextComposerError.rootMismatch(
                    requested: source.rootID,
                    targeted: workspace.rootIdentifier
                )
            }
        }
    }

    public func compose(
        _ plan: ContextCompositionPlan,
        workspace: WorkspaceContext? = nil
    ) throws -> ComposedContext {
        let workspace = workspace ?? self.workspace

        try validate(
            plan,
            workspace: workspace
        )

        var sections: [String] = []
        var appendedFileContext = false

        for source in plan.sources {
            switch source {
            case .text(let value):
                let trimmed = value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if !trimmed.isEmpty {
                    sections.append(trimmed)
                }

            case .message(let message):
                let text = message.content.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if !text.isEmpty {
                    sections.append(text)
                }

            case .transcriptEvent(let event):
                let text = event.summaryText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if !text.isEmpty {
                    sections.append(text)
                }

            case .files(let fileSource):
                let rendered = try composeFileSource(
                    fileSource,
                    metadata: plan.metadata,
                    workspace: workspace
                )

                if !rendered.isEmpty {
                    sections.append(rendered)
                    appendedFileContext = true
                }

            case .skill(let skill):
                let text = skill.contextText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if !text.isEmpty {
                    sections.append(text)
                }
            }
        }

        if appendedFileContext,
           let concatenationContext = concatenationContext(
                from: plan.metadata
           ) {
            let syntheticOutputURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "agentic-context-\(UUID().uuidString).txt"
                )

            sections.insert(
                concatenationContext.header(
                    outputURL: syntheticOutputURL
                ),
                at: 0
            )
        }

        return ComposedContext(
            metadata: plan.metadata,
            text: sections.joined(separator: "\n\n")
        )
    }
}

private extension ContextComposer {
    enum ContextComposerError: Error, LocalizedError {
        case workspaceRequired
        case rootMismatch(
            requested: PathAccessRootIdentifier,
            targeted: PathAccessRootIdentifier
        )

        var errorDescription: String? {
            switch self {
            case .workspaceRequired:
                return "ContextComposer requires a WorkspaceContext for file-backed context sources."

            case .rootMismatch(let requested, let targeted):
                return "Context source root '\(requested.rawValue)' does not match the targeted workspace root '\(targeted.rawValue)'."
            }
        }
    }

    func composeFileSource(
        _ source: ContextFileSource,
        metadata: ContextMetadata,
        workspace: WorkspaceContext?
    ) throws -> String {
        guard let workspace else {
            throw ContextComposerError.workspaceRequired
        }

        guard source.rootID == workspace.rootIdentifier else {
            throw ContextComposerError.rootMismatch(
                requested: source.rootID,
                targeted: workspace.rootIdentifier
            )
        }

        _ = try workspace.authorize(
            ".",
            capability: .scan
        )

        let includes = try normalizedExpressions(
            source.includes
        ).map {
            try PathParse.expression($0)
        }

        let excludes = try normalizedExpressions(
            source.excludes
        ).map {
            try PathParse.expression($0)
        }

        let selections = try normalizedExpressions(
            source.selections
        ).map {
            try PathSelectionExpressionParser.parse($0)
        }

        guard !includes.isEmpty || !selections.isEmpty else {
            return ""
        }

        let specification = SelectionScanSpecification(
            includes: includes,
            excludes: excludes,
            selections: selections
        )

        let result = try SelectionScan.scan(
            specification,
            relativeTo: .directoryURL(
                workspace.rootURL
            ),
            configuration: .init(
                maxDepth: source.recursive ? nil : 1,
                includeHidden: source.includeHidden,
                followSymlinks: source.followSymlinks,
                emitDirectories: false,
                emitFiles: true
            )
        )

        let allowedMatches: [
            (
                url: URL,
                contentSelections: [ContentSelection]
            )
        ] = result.matches.compactMap { match in
            guard let authorized = try? workspace.authorize(
                match.url.path,
                capability: .read
            ).authorizedPath else {
                return nil
            }

            return (
                url: authorized.absoluteURL,
                contentSelections: match.contentSelections
            )
        }

        guard !allowedMatches.isEmpty else {
            return ""
        }

        let syntheticOutputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "agentic-context-\(UUID().uuidString).txt"
            )

        let concatenator = FileConcatenator(
            inputFiles: allowedMatches.map(\.url),
            outputURL: syntheticOutputURL,
            context: nil,
            selectedContentByFile: selectedContentByFile(
                from: allowedMatches
            ),
            delimiterStyle: source.delimiterStyle,
            delimiterClosure: false,
            maxLinesPerFile: source.maxLinesPerFile,
            trimBlankLines: true,
            relativePaths: true,
            rawOutput: false,
            includeSourceLineNumbers: source.includeSourceLineNumbers,
            includeSourceModifiedAt: false,
            obscureMap: [:],
            copyToClipboard: false,
            verbose: false,
            location: metadata.title,
            protectSecrets: true,
            allowSecrets: false,
            failOnBlockedFiles: false,
            deepSecretInspection: false
        )

        return try concatenator.render().text.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
        )
    }

    func concatenationContext(
        from metadata: ContextMetadata
    ) -> ConcatenationContext? {
        let dependencies = metadata.attributes.isEmpty
            ? nil
            : metadata.attributes
                .map { key, value in
                    "\(key)=\(value)"
                }
                .sorted()

        guard metadata.title != nil
            || metadata.details != nil
            || dependencies != nil
        else {
            return nil
        }

        return .init(
            title: metadata.title,
            details: metadata.details,
            dependencies: dependencies,
            concatenatedFile: nil
        )
    }

    func normalizedExpressions(
        _ values: [String]
    ) -> [String] {
        values.map {
            $0.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }.filter {
            !$0.isEmpty
        }
    }

    func selectedContentByFile(
        from matches: [
            (
                url: URL,
                contentSelections: [ContentSelection]
            )
        ]
    ) -> [URL: [ContentSelection]] {
        matches.reduce(
            into: [URL: [ContentSelection]]()
        ) { partial, match in
            guard !match.contentSelections.isEmpty else {
                return
            }

            partial[match.url.standardizedFileURL] = match.contentSelections
        }
    }
}
