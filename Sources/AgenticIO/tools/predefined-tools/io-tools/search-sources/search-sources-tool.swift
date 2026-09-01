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
}

/// Search candidate selection semantics.
@JSONSchema
public enum SourceSearchMode:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case ranked
    case exhaustive

    var searchMode: SearchMode {
        switch self {
        case .ranked:
            return .ranked

        case .exhaustive:
            return .exhaustive
        }
    }
}

/// Search file content inside one authorized workspace source universe and return compact ranked or exhaustive source ranges without returning file contents.
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

    /// Deterministic source-search probes. Each probe owns its admission role and matching strategy.
    public let probes: [SourceSearchProbeInput]

    /// Search mode. Ranked applies ranking and source diversity before delivery; exhaustive preserves every matching region. Defaults to ranked.
    @Schema(required: false)
    public let mode: SourceSearchMode

    /// Whether matching is case-sensitive. Defaults to false.
    @Schema(required: false)
    public let caseSensitive: Bool

    /// Minimum raw Search score accepted. Defaults to 1.
    @Schema(required: false)
    public let minimumScore: Int

    /// Zero-based position in the deterministic semantic candidate universe. Defaults to 0.
    @Schema(required: false)
    public let offset: Int

    /// Optional corpus fingerprint from a previous page. Continuation fails if the current source universe changed.
    @Schema(required: false)
    public let expectedCorpusFingerprint: SourceFingerprintInput?

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
        probes: [SourceSearchProbeInput],
        mode: SourceSearchMode = .ranked,
        caseSensitive: Bool = false,
        minimumScore: Int = 1,
        offset: Int = 0,
        expectedCorpusFingerprint: SourceFingerprintInput? = nil,
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
        self.probes = probes
        self.mode = mode
        self.caseSensitive = caseSensitive
        self.minimumScore = minimumScore
        self.offset = max(
            0,
            offset
        )
        self.expectedCorpusFingerprint = expectedCorpusFingerprint
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
        case probes
        case mode
        case caseSensitive
        case minimumScore
        case offset
        case expectedCorpusFingerprint
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
            probes: try container.decode(
                [SourceSearchProbeInput].self,
                forKey: .probes
            ),
            mode: try container.decodeIfPresent(
                SourceSearchMode.self,
                forKey: .mode
            ) ?? .ranked,
            caseSensitive: try container.decodeIfPresent(
                Bool.self,
                forKey: .caseSensitive
            ) ?? false,
            minimumScore: try container.decodeIfPresent(
                Int.self,
                forKey: .minimumScore
            ) ?? 1,
            offset: try container.decodeIfPresent(
                Int.self,
                forKey: .offset
            ) ?? 0,
            expectedCorpusFingerprint: try container.decodeIfPresent(
                SourceFingerprintInput.self,
                forKey: .expectedCorpusFingerprint
            ),
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
    public static let description = "Search content inside an authorized workspace source universe and return compact ranked or exhaustive source ranges without returning source contents."
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

        let probes = try decoded.resolvedSearchProbes(
            toolName: name
        )

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
            summary: "Search \(probes.count) source probe(s) inside root '\(decoded.rootID.rawValue)'.",
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
        let probes = try decoded.resolvedSearchProbes(
            toolName: name
        )
        let request = SourceSearchRequest(
            rootID: decoded.rootID,
            definition: definition,
            probes: probes,
            options: SearchOptions(
                mode: decoded.mode.searchMode,
                caseSensitive: decoded.caseSensitive,
                minimumScore: decoded.minimumScore,
                maximumResults: nil
            ),
            frontierOptions: SearchFrontierOptions(
                mergeDistanceLines: decoded.mergeDistanceLines,
                maximumCandidates: decoded.maximumCandidates,
                maximumCandidatesPerDocument: decoded.maximumCandidatesPerDocument,
                offset: decoded.offset
            ),
            expectedCorpusFingerprint: decoded.expectedCorpusFingerprint?.fingerprint
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
                summary: "Source search (\(result.mode.rawValue)) returned \(result.returnedCandidateCount) of \(result.totalCandidateCount) candidate region(s) from offset \(result.offset) across \(result.sourceCount) retained source(s).",
                facts: [
                    .init(
                        label: "mode",
                        value: result.mode.rawValue
                    ),
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
                        label: "matched_documents",
                        value: String(
                            result.matchedDocumentCount
                        )
                    ),
                    .init(
                        label: "discovered_candidate_regions",
                        value: String(
                            result.discoveredCandidateCount
                        )
                    ),
                    .init(
                        label: "total_candidate_regions",
                        value: String(
                            result.totalCandidateCount
                        )
                    ),
                    .init(
                        label: "offset",
                        value: String(
                            result.offset
                        )
                    ),
                    .init(
                        label: "returned_candidates",
                        value: String(
                            result.returnedCandidateCount
                        )
                    ),
                    .init(
                        label: "next_offset",
                        value: result.nextOffset.map {
                            String(
                                $0
                            )
                        } ?? "none"
                    ),
                    .init(
                        label: "truncated",
                        value: String(
                            result.truncated
                        )
                    ),
                    .init(
                        label: "has_more",
                        value: String(
                            result.hasMore
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
