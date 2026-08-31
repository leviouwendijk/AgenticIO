import Agentic
import AgenticExecution
import AgenticWorkspace
import Concatenation
import Foundation
import Path
import Primitives
import Schema
import SchemaMacros
import Search

/// Deterministic text matching strategy used for authorized source search.
@JSONSchema
public enum SourceSearchStrategy:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case exact
    case prefix
    case contains
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
        case .subsequence:
            return .subsequence
        case .fuzzy:
            return .fuzzy
        }
    }
}

/// One deterministic source-search probe.
@JSONSchema
public struct SourceSearchQueryInput:
    Sendable,
    Codable,
    Hashable
{
    /// Text to search for.
    public let text: String

    /// Optional stable identifier retained in returned search evidence.
    public let id: String?

    /// Relative weight of this probe. Defaults to 1.
    @Schema(required: false)
    public let weight: Int

    public init(
        text: String,
        id: String? = nil,
        weight: Int = 1
    ) {
        self.text = text
        self.id = id
        self.weight = max(
            1,
            weight
        )
    }
}

private extension SourceSearchQueryInput {
    enum CodingKeys: String, CodingKey {
        case text
        case id
        case weight
    }
}

public extension SourceSearchQueryInput {
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self.init(
            text: try container.decode(
                String.self,
                forKey: .text
            ),
            id: try container.decodeIfPresent(
                String.self,
                forKey: .id
            ),
            weight: try container.decodeIfPresent(
                Int.self,
                forKey: .weight
            ) ?? 1
        )
    }
}

/// Search file content inside one authorized workspace source universe and return compact ranked source ranges without returning file contents.
@JSONSchema
public struct SearchSourcesToolInput:
    Sendable,
    Codable,
    Hashable
{
    /// Workspace root identifier. Defaults to project.
    @Schema(required: false)
    public let rootID: PathAccessRootIdentifier

    /// Path include expressions resolved inside the selected workspace root. Defaults to all descendants.
    @Schema(required: false)
    public let includes: [String]

    /// Path exclude expressions resolved inside the selected workspace root.
    @Schema(required: false)
    public let excludes: [String]

    /// Optional Path/Selection expressions that restrict source content before search.
    @Schema(required: false)
    public let selections: [String]

    /// One or more deterministic search probes.
    public let queries: [SourceSearchQueryInput]

    /// Text matching strategy. Defaults to fuzzy.
    @Schema(required: false)
    public let strategy: SourceSearchStrategy

    /// Whether matching is case-sensitive. Defaults to false.
    @Schema(required: false)
    public let caseSensitive: Bool

    /// Minimum raw Search score accepted. Defaults to 1.
    @Schema(required: false)
    public let minimumScore: Int

    /// Maximum raw Search hits retained before frontier convergence. Defaults to 32.
    @Schema(required: false)
    public let maximumResults: Int

    /// Maximum source-line distance used to merge nearby evidence into one frontier candidate. Defaults to 3.
    @Schema(required: false)
    public let mergeDistanceLines: Int

    /// Maximum converged source regions returned. Defaults to 16.
    @Schema(required: false)
    public let maximumCandidates: Int

    /// Maximum candidate regions retained from any one Search document. Defaults to 2.
    @Schema(required: false)
    public let maximumCandidatesPerDocument: Int

    public init(
        rootID: PathAccessRootIdentifier = .project,
        includes: [String] = ["**"],
        excludes: [String] = [],
        selections: [String] = [],
        queries: [SourceSearchQueryInput],
        strategy: SourceSearchStrategy = .fuzzy,
        caseSensitive: Bool = false,
        minimumScore: Int = 1,
        maximumResults: Int = 32,
        mergeDistanceLines: Int = 3,
        maximumCandidates: Int = 16,
        maximumCandidatesPerDocument: Int = 2
    ) {
        self.rootID = rootID
        self.includes = includes.isEmpty
            ? ["**"]
            : includes
        self.excludes = excludes
        self.selections = selections
        self.queries = queries
        self.strategy = strategy
        self.caseSensitive = caseSensitive
        self.minimumScore = minimumScore
        self.maximumResults = max(
            0,
            maximumResults
        )
        self.mergeDistanceLines = max(
            0,
            mergeDistanceLines
        )
        self.maximumCandidates = max(
            0,
            maximumCandidates
        )
        self.maximumCandidatesPerDocument = max(
            0,
            maximumCandidatesPerDocument
        )
    }
}

private extension SearchSourcesToolInput {
    enum CodingKeys: String, CodingKey {
        case rootID
        case includes
        case excludes
        case selections
        case queries
        case strategy
        case caseSensitive
        case minimumScore
        case maximumResults
        case mergeDistanceLines
        case maximumCandidates
        case maximumCandidatesPerDocument
    }
}

public extension SearchSourcesToolInput {
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
            ) ?? .project,
            includes: try container.decodeIfPresent(
                [String].self,
                forKey: .includes
            ) ?? ["**"],
            excludes: try container.decodeIfPresent(
                [String].self,
                forKey: .excludes
            ) ?? [],
            selections: try container.decodeIfPresent(
                [String].self,
                forKey: .selections
            ) ?? [],
            queries: try container.decode(
                [SourceSearchQueryInput].self,
                forKey: .queries
            ),
            strategy: try container.decodeIfPresent(
                SourceSearchStrategy.self,
                forKey: .strategy
            ) ?? .fuzzy,
            caseSensitive: try container.decodeIfPresent(
                Bool.self,
                forKey: .caseSensitive
            ) ?? false,
            minimumScore: try container.decodeIfPresent(
                Int.self,
                forKey: .minimumScore
            ) ?? 1,
            maximumResults: try container.decodeIfPresent(
                Int.self,
                forKey: .maximumResults
            ) ?? 32,
            mergeDistanceLines: try container.decodeIfPresent(
                Int.self,
                forKey: .mergeDistanceLines
            ) ?? 3,
            maximumCandidates: try container.decodeIfPresent(
                Int.self,
                forKey: .maximumCandidates
            ) ?? 16,
            maximumCandidatesPerDocument: try container.decodeIfPresent(
                Int.self,
                forKey: .maximumCandidatesPerDocument
            ) ?? 2
        )
    }
}

public struct SearchSourcesTool: TypedInstanceAgentTool {
    public typealias Input = SearchSourcesToolInput

    public static let identifier: AgentToolIdentifier = "search_sources"
    public static let description = "Search content inside an authorized workspace source universe and return compact ranked source ranges without returning source contents."
    public static let risk: ActionRisk = .observe

    public let searcher: SourceSearcher

    public init(
        searcher: SourceSearcher = .init()
    ) {
        self.searcher = searcher
    }

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }

    public var risk: ActionRisk {
        Self.risk
    }

    public func preflight(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            SearchSourcesToolInput.self,
            from: input
        )
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )

        guard decoded.queries.contains(where: {
            !$0.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }) else {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "queries",
                reason: "must contain at least one non-empty search probe"
            )
        }

        _ = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: decoded.rootID,
            path: ".",
            capability: .scan,
            toolName: name,
            type: .directory
        )

        _ = try ConcatenationCorpusDefinition.parsing(
            includes: decoded.includes,
            excludes: decoded.excludes,
            selections: decoded.selections
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace.rootURL.path,
            summary: "Search \(decoded.queries.count) source probe(s) inside root '\(decoded.rootID.rawValue)'.",
            sideEffects: [],
            rootIDs: [
                decoded.rootID.rawValue,
            ],
            capabilitiesRequired: [
                .scan,
                .read,
            ],
            policyChecks: [
                "workspace_required",
                "workspace_root_scan_authorized",
                "resolved_source_read_authorization_required",
                "selection_resolution_bounded_to_authorized_root",
                "retained_source_cache_only",
                "no_source_content_returned",
                "no_file_mutation",
            ]
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let decoded = try JSONToolBridge.decode(
            SearchSourcesToolInput.self,
            from: input
        )
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )
        let definition = try ConcatenationCorpusDefinition.parsing(
            includes: decoded.includes,
            excludes: decoded.excludes,
            selections: decoded.selections
        )
        let request = SourceSearchRequest(
            rootID: decoded.rootID,
            definition: definition,
            queries: decoded.queries.map { query in
                SearchQuery(
                    query.text,
                    id: query.id,
                    weight: query.weight
                )
            },
            options: SearchOptions(
                strategy: decoded.strategy.searchStrategy,
                caseSensitive: decoded.caseSensitive,
                minimumScore: decoded.minimumScore,
                maximumResults: decoded.maximumResults
            ),
            frontierOptions: SearchFrontierOptions(
                mergeDistanceLines: decoded.mergeDistanceLines,
                maximumCandidates: decoded.maximumCandidates,
                maximumCandidatesPerDocument: decoded.maximumCandidatesPerDocument
            )
        )

        let result = try await searcher.search(
            request,
            workspace: workspace,
            toolName: name
        )

        return try JSONToolBridge.encode(
            result
        )
    }

    public func processResult(
        input _: JSONValue,
        output: JSONValue,
        workspace _: AgentWorkspace?
    ) -> AgentToolResultProcessing {
        guard let result = try? JSONToolBridge.decode(
            SourceSearchResult.self,
            from: output
        ) else {
            return .none
        }

        return .init(
            projection: .init(
                status: "passed",
                summary: "Source search returned \(result.candidates.count) ranked candidate region(s) across \(result.sourceCount) retained source(s).",
                facts: [
                    .init(
                        label: "sources",
                        value: String(
                            result.sourceCount
                        )
                    ),
                    .init(
                        label: "searched_slices",
                        value: String(
                            result.searchedDocumentCount
                        )
                    ),
                    .init(
                        label: "candidates",
                        value: String(
                            result.candidates.count
                        )
                    ),
                    .init(
                        label: "corpus_fingerprint",
                        value: result.corpusFingerprint.description
                    ),
                ]
            )
        )
    }
}
