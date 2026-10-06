import Agentic
import Workspace
import Path
import PathParsing
import Primitives
import Schema
import Macros
import Search

@JSONSchema
public enum SearchFilepathsStrategy:
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
        }
    }
}

@JSONSchema
public struct SearchFilepathsQueryInput: Sendable, Codable, Hashable {
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


public struct SearchFilepathsToolEvidence: Sendable, Codable, Hashable {
    public let queryID: String?
    public let query: String
    public let strategy: SearchFilepathsStrategy
    public let score: Int

    public init(
        queryID: String? = nil,
        query: String,
        strategy: SearchFilepathsStrategy,
        score: Int
    ) {
        self.queryID = queryID
        self.query = query
        self.strategy = strategy
        self.score = score
    }
}

public struct SearchFilepathsToolEntry: Sendable, Codable, Hashable {
    public let rootID: String
    public let path: String
    public let isDirectory: Bool
    public let score: Int?
    public let probeCount: Int?
    public let evidence: [SearchFilepathsToolEvidence]?

    public init(
        rootID: String,
        path: String,
        isDirectory: Bool,
        score: Int? = nil,
        probeCount: Int? = nil,
        evidence: [SearchFilepathsToolEvidence]? = nil
    ) {
        self.rootID = rootID
        self.path = path
        self.isDirectory = isDirectory
        self.score = score
        self.probeCount = probeCount
        self.evidence = evidence
    }
}


public extension SystemIO.Tools {
    @Tool
    struct SearchFilepaths: Tool {
        /// Model-facing input for Find paths.
        @JSONSchema
        public struct Input: HashableSource {
            /// Optional workspace root identifier.
            public let rootID: PathAccessRootIdentifier?
            /// Optional legacy single path-name query. Used when queries is omitted or empty.
            public let query: String?
            /// Optional weighted path-name probes. When non-empty, these take precedence over query.
            public let queries: [SearchFilepathsQueryInput]?
            /// Optional include patterns.
            public let includes: [String]?
            /// Optional exclude patterns.
            public let excludes: [String]?
            /// Whether to scan recursively when maxdepth is omitted. Defaults to true.
            public let recursive: Bool?
            /// Optional maximum traversal depth. When provided, this overrides recursive.
            public let maxdepth: Int?
            /// Whether hidden paths are included.
            public let includeHidden: Bool?
            /// Whether directory symlinks are followed.
            public let followSymlinks: Bool?
            /// Whether files are returned.
            public let includeFiles: Bool?
            /// Whether directories are returned.
            public let includeDirectories: Bool?
            /// Optional Search strategy. Defaults to contains to preserve existing behavior.
            public let strategy: SearchFilepathsStrategy?
            /// Whether Search matching is case-sensitive. Defaults to false.
            public let caseSensitive: Bool?
            /// Optional minimum Search score. Defaults to 1.
            public let minimumScore: Int?
            /// Optional maximum number of returned paths. Defaults to 100.
            public let maxEntries: Int?

            public init(
                rootID: PathAccessRootIdentifier? = nil,
                query: String? = nil,
                queries: [SearchFilepathsQueryInput]? = nil,
                includes: [String]? = nil,
                excludes: [String]? = nil,
                recursive: Bool? = nil,
                maxdepth: Int? = nil,
                includeHidden: Bool? = nil,
                followSymlinks: Bool? = nil,
                includeFiles: Bool? = nil,
                includeDirectories: Bool? = nil,
                strategy: SearchFilepathsStrategy? = nil,
                caseSensitive: Bool? = nil,
                minimumScore: Int? = nil,
                maxEntries: Int? = nil
            ) {
                self.rootID = rootID
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
                self.strategy = strategy
                self.caseSensitive = caseSensitive
                self.minimumScore = minimumScore
                self.maxEntries = maxEntries
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let rootID: String
            public let searchedPathCount: Int?
            public let candidateCount: Int?
            public let entries: [SearchFilepathsToolEntry]
            public let truncated: Bool

            public init(
                rootID: String,
                entries: [SearchFilepathsToolEntry],
                truncated: Bool,
                searchedPathCount: Int? = nil,
                candidateCount: Int? = nil
            ) {
                self.rootID = rootID
                self.searchedPathCount = searchedPathCount
                self.candidateCount = candidateCount
                self.entries = entries
                self.truncated = truncated
            }
        }


        public static let purpose = "Find and rank path names inside an authorized workspace root without reading file contents, with optional bounded traversal depth."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            in context: ToolContext
        ) async throws -> ToolPreflight {
            let rootID = context.workspace?.rootIdentifier
                ?? input.rootID
                ?? .project
            let probeCount = normalizedQueries(
                input
            ).count

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: probeCount == 0
                    ? "List authorized path names in the targeted workspace context."
                    : "Search authorized path names in the targeted workspace context using \(probeCount) probe(s).",
                access: .init(
                    roots: [
                        rootID.rawValue,
                    ],
                    capabilities: [
                        .scan,
                    ],
                    includesHidden: input.includeHidden ?? false,
                    followsSymlinks: input.followSymlinks ?? false
                ),
                estimates: .init(
                    scan: .init(
                        depth: resolvedMaxDepth(
                            input
                        )
                    )
                ),
                policyChecks: [
                    "workspace_required",
                    "workspace_context_already_targeted",
                    "path_name_scan_only",
                    "authorized_paths_ranked_after_scan",
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

            _ = try workspace.authorize(
                ".",
                capability: .scan
            )

            let maxEntries = max(
                0,
                input.maxEntries ?? 100
            )
            let includes = try normalizedIncludes(
                input.includes
            ).map {
                try PathParse.expression($0)
            }
            let excludes = try (input.excludes ?? []).map {
                try PathParse.expression($0)
            }
            let scan = try PathScan.scan(
                .init(
                    includes: includes,
                    excludes: excludes
                ),
                relativeTo: .directoryURL(
                    workspace.absoluteURL
                ),
                configuration: .init(
                    maxDepth: resolvedMaxDepth(
                        input
                    ),
                    includeHidden: input.includeHidden ?? false,
                    followSymlinks: input.followSymlinks ?? false,
                    emitDirectories: input.includeDirectories ?? true,
                    emitFiles: input.includeFiles ?? true
                )
            )
            let entries = try scan.matches.map { match in
                let authorized = try workspace.authorize(
                    match.url.path,
                    capability: .scan
                ).authorizedPath

                return SearchFilepathsScannedEntry(
                    path: authorized.presentationPath,
                    isDirectory: match.type == .directory
                )
            }
            let queries = normalizedQueries(
                input
            )

            guard !queries.isEmpty else {
                let truncated = entries.count > maxEntries
                let returned = truncated
                    ? Array(
                        entries.prefix(
                            maxEntries
                        )
                    )
                    : entries

                return Output(
                    rootID: workspace.rootIdentifier.rawValue,
                    entries: returned.map {
                        .init(
                            rootID: workspace.rootIdentifier.rawValue,
                            path: $0.path,
                            isDirectory: $0.isDirectory
                        )
                    },
                    truncated: truncated,
                    searchedPathCount: entries.count,
                    candidateCount: entries.count
                )
            }

            let corpus: SearchCorpus<SearchFilepathsDocumentID> = SearchCorpus(
                documents: entries.map { entry in
                    SearchDocument(
                        id: SearchFilepathsDocumentID(
                            path: entry.path,
                            isDirectory: entry.isDirectory
                        ),
                        text: entry.path
                    )
                }
            )
            let result = TextSearch.search(
                queries,
                in: corpus,
                options: SearchOptions(
                    strategy: (input.strategy ?? .contains).searchStrategy,
                    caseSensitive: input.caseSensitive ?? false,
                    minimumScore: input.minimumScore ?? 1,
                    maximumResults: maxEntries
                )
            )

            return Output(
                rootID: workspace.rootIdentifier.rawValue,
                entries: result.hits.map { hit in
                    .init(
                        rootID: workspace.rootIdentifier.rawValue,
                        path: hit.documentID.path,
                        isDirectory: hit.documentID.isDirectory,
                        score: hit.score.value,
                        probeCount: hit.evidence.count,
                        evidence: hit.evidence.map { evidence in
                            SearchFilepathsToolEvidence(
                                queryID: evidence.queryID,
                                query: evidence.query,
                                strategy: SearchFilepathsStrategy(
                                    searchStrategy: evidence.strategy
                                ),
                                score: evidence.score.value
                            )
                        }
                    )
                },
                truncated: result.candidateCount > result.hits.count,
                searchedPathCount: result.searchedDocumentCount,
                candidateCount: result.candidateCount
            )
        }

        public func process(
            _ output: Output,
            input _: Input
        ) -> ToolCall.ResultProjection? {
            let result = output

            return .init(
                status: "passed",
                summary: "find_paths returned \(result.entries.count) path(s) from \(result.searchedPathCount ?? result.entries.count) authorized path(s).",
                facts: [
                    .init(
                        label: "candidates",
                        value: String(
                            result.candidateCount ?? result.entries.count
                        )
                    ),
                    .init(
                        label: "returned",
                        value: String(
                            result.entries.count
                        )
                    ),
                ]
                
            )
        }
    }
}

private struct SearchFilepathsScannedEntry {
    let path: String
    let isDirectory: Bool
}

private struct SearchFilepathsDocumentID:
    Sendable,
    Codable,
    Hashable
{
    let path: String
    let isDirectory: Bool
}

internal extension SystemIO.Tools.SearchFilepaths {
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

    func resolvedMaxDepth(
        _ input: SystemIO.Tools.SearchFilepaths.Input
    ) -> Int? {
        if let maxdepth = input.maxdepth {
            return max(
                0,
                maxdepth
            )
        }

        return (input.recursive ?? true)
            ? nil
            : 1
    }

    func normalizedIncludes(
        _ values: [String]?
    ) -> [String] {
        let values = values ?? []
        let normalized = values.map {
            $0.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }.filter {
            !$0.isEmpty
        }

        guard !normalized.isEmpty else {
            return [
                "**",
            ]
        }

        return normalized
    }

    func normalizedQueries(
        _ input: SystemIO.Tools.SearchFilepaths.Input
    ) -> [SearchQuery] {
        let explicit = (input.queries ?? []).map {
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

        guard let query = normalizedQuery(
            input.query
        ) else {
            return []
        }

        return [
            SearchQuery(
                query
            ),
        ]
    }

    func normalizedQuery(
        _ value: String?
    ) -> String? {
        let trimmed = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let trimmed,
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}
