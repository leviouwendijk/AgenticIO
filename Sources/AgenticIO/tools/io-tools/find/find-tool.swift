import Agentic
import Workspace
import Foundation
import IO
import Path
import PathParsing
import Primitives
import Schema
import Macros
import Search

@JSONSchema
public enum FindStrategy:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case exact
    case prefix
    case contains
    case identifier
    case subsequence
    case fuzzy
    /// A regular expression over the path.
    case regex

    var searchStrategy: SearchStrategy {
        switch self {
        case .exact:
            return .exact
        case .prefix:
            return .prefix
        case .contains:
            return .contains
        case .identifier:
            return .identifier
        case .subsequence:
            return .subsequence
        case .fuzzy:
            return .fuzzy
        case .regex:
            return .regex
        }
    }

    init(
        searchStrategy: SearchStrategy
    ) {
        switch searchStrategy {
        case .exact:
            self = .exact
        case .prefix:
            self = .prefix
        case .contains:
            self = .contains
        case .identifier:
            self = .identifier
        case .subsequence:
            self = .subsequence
        case .fuzzy:
            self = .fuzzy
        case .regex:
            self = .regex
        }
    }
}

@JSONSchema
public struct FindQuery: Sendable, Codable, Hashable {
    /// Text to search for in workspace-relative paths.
    public let text: String

    /// Optional stable identifier retained in returned Search evidence.
    public let id: String?

    /// Optional relative probe weight. Defaults to 1.
    public let weight: Int?

    public init(
        text: String,
        id: String? = nil,
        weight: Int? = nil
    ) {
        self.text = text
        self.id = id
        self.weight = weight
    }
}

public struct FindEvidence: Sendable, Codable, Hashable {
    public let queryID: String?
    public let query: String
    public let strategy: FindStrategy
    public let score: Int

    public init(
        queryID: String? = nil,
        query: String,
        strategy: FindStrategy,
        score: Int
    ) {
        self.queryID = queryID
        self.query = query
        self.strategy = strategy
        self.score = score
    }
}

/// Paths the access policy denied, left out of a find result, counted per
/// reason. Their names are not returned; reading them stays denied.
public struct FindWithheld: Sendable, Codable, Hashable {
    public let reason: String
    public let count: Int

    public init(
        reason: String,
        count: Int
    ) {
        self.reason = reason
        self.count = count
    }
}

public struct FindEntry: Sendable, Codable, Hashable {
    public let path: String
    public let isDirectory: Bool
    public let score: Int?
    public let probeCount: Int?
    public let evidence: [FindEvidence]?

    public init(
        path: String,
        isDirectory: Bool,
        score: Int? = nil,
        probeCount: Int? = nil,
        evidence: [FindEvidence]? = nil
    ) {
        self.path = path
        self.isDirectory = isDirectory
        self.score = score
        self.probeCount = probeCount
        self.evidence = evidence
    }
}

private extension SystemIO.Tools.Find.Input {
    enum CodingKeys: String, CodingKey {
        case rootID
        case path
        case query
        case queries
        case includes
        case excludes
        case recursive
        case maxdepth
        case includeHidden
        case followSymlinks
        case includeFiles
        case includeDirectories
        case directoryState
        case strategy
        case caseSensitive
        case minimumScore
        case maxEntries
        case expand
    }
}

public extension SystemIO.Tools.Find.Input {
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
            ),
            path: try container.decodeIfPresent(
                String.self,
                forKey: .path
            ),
            query: try container.decodeIfPresent(
                String.self,
                forKey: .query
            ),
            queries: try container.decodeIfPresent(
                [FindQuery].self,
                forKey: .queries
            ) ?? [],
            includes: try container.decodeIfPresent(
                [String].self,
                forKey: .includes
            ) ?? [],
            excludes: try container.decodeIfPresent(
                [String].self,
                forKey: .excludes
            ) ?? [],
            recursive: try container.decodeIfPresent(
                Bool.self,
                forKey: .recursive
            ),
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
            strategy: try container.decodeIfPresent(
                FindStrategy.self,
                forKey: .strategy
            ) ?? .contains,
            caseSensitive: try container.decodeIfPresent(
                Bool.self,
                forKey: .caseSensitive
            ) ?? false,
            minimumScore: try container.decodeIfPresent(
                Int.self,
                forKey: .minimumScore
            ) ?? 1,
            maxEntries: try container.decodeIfPresent(
                Int.self,
                forKey: .maxEntries
            ),
            expand: try container.decodeIfPresent(
                Bool.self,
                forKey: .expand
            ) ?? false
        )
    }
}

public extension SystemIO.Tools {
    @Tool
    struct Find: Tool {
        /// Find paths, like find or a glob: without query, list a directory; with query, rank the paths that match it. Never reads file contents.
        @JSONSchema
        public struct Input: HashableSource {
            /// Workspace root identifier. Defaults to the targeted root.
            public let rootID: PathAccessRootIdentifier?

            /// Directory to start from, relative to the workspace root. Defaults to the root.
            public let path: String?

            /// Text to match in paths. Without query or queries, find lists paths sorted by path.
            public let query: String?

            /// Several weighted path probes; instead of query.
            @Schema(required: false)
            public let queries: [FindQuery]

            /// Path globs relative to path, such as **/*.swift. Defaults to everything.
            @Schema(required: false)
            public let includes: [String]

            /// Path globs to leave out.
            @Schema(required: false)
            public let excludes: [String]

            /// Whether to descend below path when maxdepth is omitted. Defaults to true with a query or includes, false for a plain listing.
            public let recursive: Bool?

            /// Maximum traversal depth. Overrides recursive.
            public let maxdepth: Int?

            /// Whether hidden paths are included. Defaults to false.
            @Schema(required: false)
            public let includeHidden: Bool

            /// Whether directory symlinks are followed. Defaults to false.
            @Schema(required: false)
            public let followSymlinks: Bool

            /// Whether files are returned. Defaults to true.
            @Schema(required: false)
            public let includeFiles: Bool

            /// Whether directories are returned. Defaults to true.
            @Schema(required: false)
            public let includeDirectories: Bool

            /// Only directories that are 'empty' or 'nonempty'. Hidden entries still make a directory nonempty. Files are unaffected.
            public let directoryState: PathDirectoryState?

            /// How query text matches a path. Defaults to contains.
            @Schema(required: false)
            public let strategy: FindStrategy

            /// Whether matching is case-sensitive. Defaults to false.
            @Schema(required: false)
            public let caseSensitive: Bool

            /// Minimum Search score for a match. Defaults to 1.
            @Schema(required: false)
            public let minimumScore: Int

            /// Maximum paths returned. Defaults to 100 with a query; a listing returns everything.
            public let maxEntries: Int?

            /// Whether a long listing is shown in full instead of summarizing deeper directories as counts. Defaults to false.
            @Schema(required: false)
            public let expand: Bool

            public init(
                rootID: PathAccessRootIdentifier? = nil,
                path: String? = nil,
                query: String? = nil,
                queries: [FindQuery] = [],
                includes: [String] = [],
                excludes: [String] = [],
                recursive: Bool? = nil,
                maxdepth: Int? = nil,
                includeHidden: Bool = false,
                followSymlinks: Bool = false,
                includeFiles: Bool = true,
                includeDirectories: Bool = true,
                directoryState: PathDirectoryState? = nil,
                strategy: FindStrategy = .contains,
                caseSensitive: Bool = false,
                minimumScore: Int = 1,
                maxEntries: Int? = nil,
                expand: Bool = false
            ) {
                self.rootID = rootID
                self.path = path
                self.query = query
                self.queries = queries
                self.includes = includes
                self.excludes = excludes
                self.recursive = recursive
                self.maxdepth = maxdepth
                self.includeHidden = includeHidden
                self.followSymlinks = followSymlinks
                self.includeFiles = includeFiles
                self.includeDirectories = includeDirectories
                self.directoryState = directoryState
                self.strategy = strategy
                self.caseSensitive = caseSensitive
                self.minimumScore = minimumScore
                self.maxEntries = maxEntries
                self.expand = expand
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let rootID: String
            /// The start directory, when one was given.
            public let directory: String?
            /// A listing sorted by path, or matches ranked by score.
            public let entries: [FindEntry]
            public let truncated: Bool
            /// Paths searched, for a query.
            public let searchedPathCount: Int?
            /// Paths that matched before maxEntries, for a query.
            public let candidateCount: Int?
            /// Paths the access policy denied, left out and counted by reason; nil when none.
            public let withheld: [FindWithheld]?

            public init(
                rootID: String,
                directory: String? = nil,
                entries: [FindEntry],
                truncated: Bool,
                searchedPathCount: Int? = nil,
                candidateCount: Int? = nil,
                withheld: [FindWithheld]? = nil
            ) {
                self.rootID = rootID
                self.directory = directory
                self.entries = entries
                self.truncated = truncated
                self.searchedPathCount = searchedPathCount
                self.candidateCount = candidateCount
                self.withheld = withheld
            }

            public var withheldCount: Int {
                (withheld ?? []).reduce(0) {
                    $0 + $1.count
                }
            }

            /// Whether this lists paths rather than ranking matches.
            public var isListing: Bool {
                searchedPathCount == nil
            }
        }

        public static let purpose = "Find paths in the workspace without reading file contents: list a directory, or rank the paths matching a query."
        public static let risk: ActionRisk = .observe

        public let projection: Projection

        public init(
            projection: Projection = .init()
        ) {
            self.projection = projection
        }

        public func preflight(
            _ input: Input,
            in context: ToolContext
        ) async throws -> ToolPreflight {
            let targetPath: String

            if let workspace = context.workspace {
                try requireTargetedRoot(
                    input.rootID,
                    workspace: workspace
                )
                let authorized = try workspace.authorize(
                    normalizedDirectoryPath(input.path) ?? ".",
                    capability: .scan
                ).authorizedPath
                try requireDirectory(
                    authorized
                )
                targetPath = authorized.presentationPath
            } else {
                targetPath = normalizedDirectoryPath(input.path) ?? "."
            }

            let probeCount = normalizedQueries(
                input
            ).count

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: probeCount == 0
                    ? (resolvedMaxDepth(for: input) == 1
                        ? "List direct entries in \(targetPath)"
                        : "List paths under \(targetPath)")
                    : "Search path names under \(targetPath) using \(probeCount) probe(s)",
                access: .init(
                    targets: [
                        targetPath,
                    ],
                    roots: context.workspace.map {
                        [
                            $0.rootIdentifier.rawValue,
                        ]
                    } ?? [
                        (input.rootID ?? .project).rawValue,
                    ],
                    capabilities: [
                        .scan,
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
                    "path_name_scan_only",
                    "no_file_content_access",
                ]
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let workspace = try WorkspaceToolSupport.requireWorkspace(
                context.workspace,
                toolName: Self.identifier.rawValue
            )
            try requireTargetedRoot(
                input.rootID,
                workspace: workspace
            )

            let directoryPath = normalizedDirectoryPath(
                input.path
            )
            let directory = try workspace.authorize(
                directoryPath ?? ".",
                capability: .scan
            ).authorizedPath
            try requireDirectory(
                directory
            )

            let specification = try ParsedPathScan.specification(
                includes: normalizedIncludes(
                    for: input
                ),
                excludes: input.excludes
            )
            let scan = try PathScan.scan(
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
            // A path a deny rule covers (a .key deep in a tree) is withheld and
            // counted, not an error for the whole scan.
            var denials: [PathAccessEvaluation] = []
            let entries = try scan.matches.compactMap { match -> FindScannedEntry? in
                guard match.url.standardizedFileURL != directory.absoluteURL.standardizedFileURL else {
                    return nil
                }

                let authorized: AuthorizedPath
                do {
                    authorized = try workspace.authorize(
                        match.url.path,
                        capability: .scan
                    ).authorizedPath
                } catch PathAccessError.denied(let evaluation) {
                    denials.append(
                        evaluation
                    )
                    return nil
                }

                return FindScannedEntry(
                    path: authorized.presentationPath,
                    isDirectory: match.type == .directory
                )
            }
            let withheld = Self.withheld(
                denials
            )
            let rootID = workspace.rootIdentifier.rawValue
            let directoryName = directoryPath.map { _ in
                directory.presentationPath
            }
            let queries = normalizedQueries(
                input
            )

            guard !queries.isEmpty else {
                let maxEntries = input.maxEntries.map {
                    max(0, $0)
                }
                let truncated = maxEntries.map {
                    entries.count > $0
                } ?? false
                let returned = maxEntries.map {
                    Array(entries.prefix($0))
                } ?? entries

                return Output(
                    rootID: rootID,
                    directory: directoryName,
                    entries: returned.map {
                        .init(
                            path: $0.path,
                            isDirectory: $0.isDirectory
                        )
                    },
                    truncated: truncated,
                    withheld: withheld
                )
            }

            let corpus: SearchCorpus<FindScannedEntry> = SearchCorpus(
                documents: entries.map { entry in
                    SearchDocument(
                        id: entry,
                        text: entry.path
                    )
                }
            )
            let result = TextSearch.search(
                queries,
                in: corpus,
                options: SearchOptions(
                    strategy: input.strategy.searchStrategy,
                    caseSensitive: input.caseSensitive,
                    minimumScore: input.minimumScore,
                    maximumResults: max(
                        0,
                        input.maxEntries ?? 100
                    )
                )
            )

            return Output(
                rootID: rootID,
                directory: directoryName,
                entries: result.hits.map { hit in
                    .init(
                        path: hit.documentID.path,
                        isDirectory: hit.documentID.isDirectory,
                        score: hit.score.value,
                        probeCount: hit.evidence.count,
                        evidence: hit.evidence.map { evidence in
                            FindEvidence(
                                queryID: evidence.queryID,
                                query: evidence.query,
                                strategy: FindStrategy(
                                    searchStrategy: evidence.strategy
                                ),
                                score: evidence.score.value
                            )
                        }
                    )
                },
                truncated: result.candidateCount > result.hits.count,
                searchedPathCount: result.searchedDocumentCount,
                candidateCount: result.candidateCount,
                withheld: withheld
            )
        }

        public func process(
            _ output: Output,
            input _: Input
        ) -> ToolExecution.Projection? {
            .init(
                status: "passed",
                summary: output.isListing
                    ? "\(Self.identifier.rawValue) listed \(output.entries.count) path(s)."
                    : "\(Self.identifier.rawValue) returned \(output.entries.count) path(s) from \(output.searchedPathCount ?? output.entries.count) authorized path(s).",
                facts: [
                    .init(
                        label: "candidates",
                        value: String(
                            output.candidateCount ?? output.entries.count
                        )
                    ),
                    .init(
                        label: "returned",
                        value: String(
                            output.entries.count
                        )
                    ),
                ] + (output.withheldCount > 0
                    ? [
                        .init(
                            label: "withheld",
                            value: String(
                                output.withheldCount
                            )
                        ),
                    ]
                    : [])
            )
        }
    }
}

extension SystemIO.Tools.Find {
    /// Denials grouped by their rule's reason, in first-seen order; nil when none.
    static func withheld(
        _ denials: [PathAccessEvaluation]
    ) -> [FindWithheld]? {
        guard !denials.isEmpty else {
            return nil
        }

        var order: [String] = []
        var counts: [String: Int] = [:]

        for evaluation in denials {
            let reason = evaluation.matchedRule?.reason.flatMap {
                $0.isEmpty ? nil : $0
            } ?? "Denied by the access policy."

            if counts[reason] == nil {
                order.append(
                    reason
                )
            }

            counts[reason, default: 0] += 1
        }

        return order.map {
            .init(
                reason: $0,
                count: counts[$0] ?? 0
            )
        }
    }

    /// One bracketed line naming how many paths the policy withheld and why.
    static func withheldNote(
        _ output: Output
    ) -> String? {
        guard let withheld = output.withheld,
              !withheld.isEmpty
        else {
            return nil
        }

        let reasons = withheld.map {
            "\($0.count) × \($0.reason)"
        }

        return "[\(output.withheldCount) path(s) withheld by the access policy, not listed and not readable: "
            + reasons.joined(separator: "; ")
            + "]"
    }
}

private struct FindScannedEntry:
    Sendable,
    Codable,
    Hashable
{
    let path: String
    let isDirectory: Bool
}

private extension SystemIO.Tools.Find {
    func requireTargetedRoot(
        _ requested: PathAccessRootIdentifier?,
        workspace: WorkspaceContext
    ) throws {
        guard let requested else {
            return
        }

        guard requested == workspace.rootIdentifier else {
            throw PredefinedFileToolError.invalidValue(
                tool: Self.identifier.rawValue,
                field: "rootID",
                reason: "rootID '\(requested.rawValue)' does not match the already-targeted workspace root '\(workspace.rootIdentifier.rawValue)'"
            )
        }
    }

    func requireDirectory(
        _ authorized: AuthorizedPath
    ) throws {
        let snapshot = try FileInspector(
            authorized.absoluteURL
        ).inspect()

        guard snapshot.existed else {
            return
        }

        guard snapshot.kind == .directory else {
            throw PredefinedFileToolError.invalidValue(
                tool: Self.identifier.rawValue,
                field: "path",
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

    func normalizedIncludes(
        for input: SystemIO.Tools.Find.Input
    ) -> [String] {
        let normalized = input.includes.map {
            $0.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }.filter {
            !$0.isEmpty
        }

        guard normalized.isEmpty else {
            return normalized
        }

        guard let maxDepth = resolvedMaxDepth(
            for: input
        ) else {
            return ["**"]
        }

        return [maxDepth > 1 ? "**" : "*"]
    }

    /// A listing stays shallow by default; a query or includes search below.
    func resolvedMaxDepth(
        for input: SystemIO.Tools.Find.Input
    ) -> Int? {
        if let maxdepth = input.maxdepth {
            return max(
                0,
                maxdepth
            )
        }

        let recursive = input.recursive
            ?? (!normalizedQueries(input).isEmpty || !input.includes.isEmpty)

        return recursive
            ? nil
            : 1
    }

    func normalizedQueries(
        _ input: SystemIO.Tools.Find.Input
    ) -> [SearchQuery] {
        let explicit = input.queries.map {
            SearchQuery(
                $0.text,
                id: $0.id,
                weight: max(
                    1,
                    $0.weight ?? 1
                )
            )
        }.filter {
            !$0.isEmpty
        }

        if !explicit.isEmpty {
            return explicit
        }

        guard let query = input.query?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
              !query.isEmpty
        else {
            return []
        }

        return [
            SearchQuery(
                query
            ),
        ]
    }
}
