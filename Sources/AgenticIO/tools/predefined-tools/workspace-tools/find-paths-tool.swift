import Agentic
import AgenticExecution
import AgenticWorkspace
import Path
import PathParsing
import Primitives
import Schema
import SchemaMacros
import Search

@JSONSchema
public enum FindPathsStrategy:
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
public struct FindPathsQueryInput: Sendable, Codable, Hashable {
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

/// Model-facing input for Find paths.
@JSONSchema
public struct FindPathsToolInput: Sendable, Codable, Hashable {
    /// Optional workspace root identifier.
    public let rootID: PathAccessRootIdentifier?
    /// Optional legacy single path-name query. Used when queries is omitted or empty.
    public let query: String?
    /// Optional weighted path-name probes. When non-empty, these take precedence over query.
    public let queries: [FindPathsQueryInput]?
    /// Optional include patterns.
    public let includes: [String]?
    /// Optional exclude patterns.
    public let excludes: [String]?
    /// Whether to scan recursively.
    public let recursive: Bool?
    /// Whether hidden paths are included.
    public let includeHidden: Bool?
    /// Whether directory symlinks are followed.
    public let followSymlinks: Bool?
    /// Whether files are returned.
    public let includeFiles: Bool?
    /// Whether directories are returned.
    public let includeDirectories: Bool?
    /// Optional Search strategy. Defaults to contains to preserve existing behavior.
    public let strategy: FindPathsStrategy?
    /// Whether Search matching is case-sensitive. Defaults to false.
    public let caseSensitive: Bool?
    /// Optional minimum Search score. Defaults to 1.
    public let minimumScore: Int?
    /// Optional maximum number of returned paths. Defaults to 100.
    public let maxEntries: Int?

    public init(
        rootID: PathAccessRootIdentifier? = nil,
        query: String? = nil,
        queries: [FindPathsQueryInput]? = nil,
        includes: [String]? = nil,
        excludes: [String]? = nil,
        recursive: Bool? = nil,
        includeHidden: Bool? = nil,
        followSymlinks: Bool? = nil,
        includeFiles: Bool? = nil,
        includeDirectories: Bool? = nil,
        strategy: FindPathsStrategy? = nil,
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

public struct FindPathsToolEvidence: Sendable, Codable, Hashable {
    public let queryID: String?
    public let query: String
    public let strategy: FindPathsStrategy
    public let score: Int

    public init(
        queryID: String? = nil,
        query: String,
        strategy: FindPathsStrategy,
        score: Int
    ) {
        self.queryID = queryID
        self.query = query
        self.strategy = strategy
        self.score = score
    }
}

public struct FindPathsToolEntry: Sendable, Codable, Hashable {
    public let rootID: String
    public let path: String
    public let isDirectory: Bool
    public let score: Int?
    public let probeCount: Int?
    public let evidence: [FindPathsToolEvidence]?

    public init(
        rootID: String,
        path: String,
        isDirectory: Bool,
        score: Int? = nil,
        probeCount: Int? = nil,
        evidence: [FindPathsToolEvidence]? = nil
    ) {
        self.rootID = rootID
        self.path = path
        self.isDirectory = isDirectory
        self.score = score
        self.probeCount = probeCount
        self.evidence = evidence
    }
}

public struct FindPathsToolOutput: Sendable, Codable, Hashable {
    public let rootID: String
    public let searchedPathCount: Int?
    public let candidateCount: Int?
    public let entries: [FindPathsToolEntry]
    public let truncated: Bool

    public init(
        rootID: String,
        entries: [FindPathsToolEntry],
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

public struct FindPathsTool: TypedInstanceAgentTool {
    public typealias Input = FindPathsToolInput

    public static let identifier: AgentToolIdentifier = "find_paths"
    public static let description = "Find and rank path names inside an authorized workspace root without reading file contents."
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
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            FindPathsToolInput.self,
            from: input
        )
        let rootID = decoded.rootID ?? .project
        let probeCount = normalizedQueries(
            decoded
        ).count

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace?.rootURL.path,
            summary: probeCount == 0
                ? "List authorized path names in root '\(rootID.rawValue)'."
                : "Search authorized path names in root '\(rootID.rawValue)' using \(probeCount) probe(s).",
            rootIDs: [
                rootID.rawValue,
            ],
            capabilitiesRequired: [
                .scan,
            ],
            estimatedScanDepth: decoded.recursive == false
                ? 1
                : nil,
            includesHiddenPaths: decoded.includeHidden ?? false,
            followsSymlinks: decoded.followSymlinks ?? false,
            policyChecks: [
                "workspace_required",
                "path_name_scan_only",
                "authorized_paths_ranked_after_scan",
                "no_file_content_access",
            ]
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let workspace = try WorkspaceToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )
        let decoded = try JSONToolBridge.decode(
            FindPathsToolInput.self,
            from: input
        )
        let rootID = decoded.rootID ?? .project
        let recursive = decoded.recursive ?? true
        let maxEntries = max(
            0,
            decoded.maxEntries ?? 100
        )
        let includes = try normalizedIncludes(
            decoded.includes
        ).map {
            try PathParse.expression($0)
        }
        let excludes = try (decoded.excludes ?? []).map {
            try PathParse.expression($0)
        }
        let scan = try workspace.scan(
            .init(
                includes: includes,
                excludes: excludes
            ),
            rootID: rootID,
            configuration: .init(
                maxDepth: recursive ? nil : 1,
                includeHidden: decoded.includeHidden ?? false,
                followSymlinks: decoded.followSymlinks ?? false,
                emitDirectories: decoded.includeDirectories ?? true,
                emitFiles: decoded.includeFiles ?? true
            )
        )
        let entries = try workspace.authorizedEntries(
            from: scan,
            rootID: rootID,
            capability: .scan,
            toolName: name
        )
        let queries = normalizedQueries(
            decoded
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

            return try JSONToolBridge.encode(
                FindPathsToolOutput(
                    rootID: rootID.rawValue,
                    entries: returned.map {
                        .init(
                            rootID: rootID.rawValue,
                            path: $0.relativePath,
                            isDirectory: $0.isDirectory
                        )
                    },
                    truncated: truncated,
                    searchedPathCount: entries.count,
                    candidateCount: entries.count
                )
            )
        }

        let corpus = SearchCorpus(
            documents: entries.map { entry in
                SearchDocument(
                    id: FindPathsDocumentID(
                        path: entry.relativePath,
                        isDirectory: entry.isDirectory
                    ),
                    text: entry.relativePath
                )
            }
        )
        let result = TextSearch.search(
            queries,
            in: corpus,
            options: SearchOptions(
                strategy: (decoded.strategy ?? .contains).searchStrategy,
                caseSensitive: decoded.caseSensitive ?? false,
                minimumScore: decoded.minimumScore ?? 1,
                maximumResults: maxEntries
            )
        )

        return try JSONToolBridge.encode(
            FindPathsToolOutput(
                rootID: rootID.rawValue,
                entries: result.hits.map { hit in
                    .init(
                        rootID: rootID.rawValue,
                        path: hit.documentID.path,
                        isDirectory: hit.documentID.isDirectory,
                        score: hit.score.value,
                        probeCount: hit.evidence.count,
                        evidence: hit.evidence.map { evidence in
                            FindPathsToolEvidence(
                                queryID: evidence.queryID,
                                query: evidence.query,
                                strategy: FindPathsStrategy(
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
        )
    }

    public func processResult(
        input _: JSONValue,
        output: JSONValue,
        workspace _: AgentWorkspace?
    ) -> AgentToolResultProcessing {
        guard let result = try? JSONToolBridge.decode(
            FindPathsToolOutput.self,
            from: output
        ) else {
            return .none
        }

        return .init(
            projection: .init(
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
        )
    }
}

private struct FindPathsDocumentID:
    Sendable,
    Codable,
    Hashable
{
    let path: String
    let isDirectory: Bool
}

internal extension FindPathsTool {
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
        _ input: FindPathsToolInput
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
