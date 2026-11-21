import Agentic
import Workspace
import Concatenation
import Foundation
import Path
import Primitives
import Schema
import Macros
import Search

/// How a probe's text matches source: `contains` (literal text anywhere,
/// following caseSensitive; the default), `exact` (literal text, always
/// case-sensitive), `regex` (a regular expression; `^` and `$` match at
/// line ends), `identifier` (a whole identifier), `prefix` (text that starts
/// a searched slice), `subsequence` and `fuzzy` (approximate).
@JSONSchema
public enum SourceSearchStrategy:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case contains
    case exact
    case regex
    case identifier
    case prefix
    case subsequence
    case fuzzy

    /// Exact runs as a case-sensitive pattern of the escaped text: whole-
    /// field equality never matches inside source.
    var searchStrategy: SearchStrategy {
        switch self {
        case .exact, .regex:
            return .regex
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

    /// The text the matcher receives for a probe's text.
    func searchText(
        _ text: String
    ) -> String {
        switch self {
        case .exact:
            "(?-i)" + NSRegularExpression.escapedPattern(for: text)
        default:
            text
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


private extension SystemIO.Tools.Search.Input {
    enum CodingKeys: String, CodingKey {
        case rootID
        case includes
        case excludes
        case selections
        case within
        case query
        case pattern
        case contextLines
        case probes
        case lexicalPattern
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

public extension SystemIO.Tools.Search.Input {
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
            within: try container.decodeIfPresent(
                [SourceContextCandidateInput].self,
                forKey: .within
            ) ?? [],
            query: try container.decodeIfPresent(
                String.self,
                forKey: .query
            ),
            pattern: try container.decodeIfPresent(
                String.self,
                forKey: .pattern
            ),
            contextLines: try container.decodeIfPresent(
                Int.self,
                forKey: .contextLines
            ) ?? 0,
            probes: try container.decodeIfPresent(
                [SourceSearchProbeInput].self,
                forKey: .probes
            ) ?? [],
            lexicalPattern: try container.decodeIfPresent(
                LexicalPatternInput.self,
                forKey: .lexicalPattern
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

public extension SystemIO.Tools {
    @Tool
    struct Search: Tool {
        /// Search file contents, like rg: give `query` (literal text) or `pattern` (a regular expression), and `includes` path globs to narrow the files. Each hit shows its matching lines; `contextLines` adds lines around them. `probes` combine several terms with roles; `lexicalPattern` matches token patterns.
        @JSONSchema
        public struct Input: HashableSource
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

            /// Optional prior search candidates that restrict this search to freshness-validated source regions.
            @Schema(required: false)
            public let within: [SourceContextCandidateInput]

            /// Literal text to find (contains; follows caseSensitive). The short form: one required term, instead of probes.
            @Schema(required: false)
            public let query: String?

            /// A regular expression to find; `^` and `$` match at line ends. The short form, instead of probes.
            @Schema(required: false)
            public let pattern: String?

            /// Lines shown before and after each matching line. Defaults to 0.
            @Schema(required: false)
            public let contextLines: Int

            /// Several search terms, each with its own admission role and matching strategy. Mutually exclusive with query, pattern and lexicalPattern.
            @Schema(required: false)
            public let probes: [SourceSearchProbeInput]

            /// Optional bounded lexical token pattern. Mutually exclusive with probes.
            @Schema(required: false)
            public let lexicalPattern: LexicalPatternInput?

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
                within: [SourceContextCandidateInput] = [],
                query: String? = nil,
                pattern: String? = nil,
                contextLines: Int = 0,
                probes: [SourceSearchProbeInput] = [],
                lexicalPattern: LexicalPatternInput? = nil,
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
                self.within = within
                self.query = query
                self.pattern = pattern
                self.contextLines = min(10, max(0, contextLines))
                self.probes = probes
                self.lexicalPattern = lexicalPattern
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

        public typealias Output = SourceSearchResult

        public static let purpose = "Search file contents like rg: literal text (query) or a regular expression (pattern), each hit with its matching lines."
        public static let risk: ActionRisk = .observe

        public let searcher: SourceSearcher

        public init(
            searcher: SourceSearcher = .shared
        ) {
            self.searcher = searcher
        }

        public func preflight(
            _ input: Input,
            in context: ToolContext
        ) async throws -> ToolPreflight {
            let workspace = try FileToolSupport.requireWorkspace(
                context.workspace,
                toolName: Self.identifier.rawValue
            )

            let query = try input.resolvedSearchQuery(
                toolName: Self.identifier.rawValue
            )

            _ = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: input.rootID,
                path: ".",
                capability: .scan,
                toolName: Self.identifier.rawValue,
                type: .directory
            )

            _ = try ConcatenationCorpusDefinition.parsing(
                includes: input.includes,
                excludes: input.excludes,
                selections: input.selections
            )

            for candidate in input.within {
                _ = try candidate.reference()
                _ = try FileToolAccess.authorize(
                    workspace: workspace,
                    rootID: input.rootID,
                    path: candidate.path,
                    capability: .read,
                    toolName: Self.identifier.rawValue,
                    type: .file
                )
            }

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "Search \(query.summary) inside root '\(input.rootID.rawValue)'.",
                access: .init(
                    roots: [
                        input.rootID.rawValue,
                    ],
                    capabilities: [
                        .scan,
                        .read,
                    ]
                ),
                sideEffects: [],
                policyChecks: [
                    "workspace_required",
                    "workspace_root_scan_authorized",
                    "resolved_source_read_authorization_required",
                    "search_candidate_source_fingerprint_required",
                    "stale_search_candidate_rejected",
                    "selection_resolution_bounded_to_authorized_root",
                    "retained_source_cache_only",
                    "matching_lines_only",
                    "no_file_mutation",
                ]
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let workspace = try FileToolSupport.requireWorkspace(
                context.workspace,
                toolName: Self.identifier.rawValue
            )
            let definition = try ConcatenationCorpusDefinition.parsing(
                includes: input.includes,
                excludes: input.excludes,
                selections: input.selections
            )
            let query = try input.resolvedSearchQuery(
                toolName: Self.identifier.rawValue
            )
            let options = SearchOptions(
                mode: input.mode.searchMode,
                caseSensitive: input.caseSensitive,
                minimumScore: input.minimumScore,
                maximumResults: nil
            )
            let frontierOptions = SearchFrontierOptions(
                mergeDistanceLines: input.mergeDistanceLines,
                maximumCandidates: input.maximumCandidates,
                maximumCandidatesPerDocument: input.maximumCandidatesPerDocument,
                offset: input.offset
            )
            let within = try input.within.map {
                try $0.reference()
            }
            let request: SourceSearchRequest

            switch query {
            case .text(let probes):
                request = SourceSearchRequest(
                    rootID: input.rootID,
                    definition: definition,
                    probes: probes,
                    options: options,
                    frontierOptions: frontierOptions,
                    within: within,
                    expectedCorpusFingerprint:
                        input.expectedCorpusFingerprint?.fingerprint,
                    contextLines: input.contextLines
                )

            case .lexical(let pattern):
                request = SourceSearchRequest(
                    rootID: input.rootID,
                    definition: definition,
                    lexicalPattern: pattern,
                    options: options,
                    frontierOptions: frontierOptions,
                    within: within,
                    expectedCorpusFingerprint:
                        input.expectedCorpusFingerprint?.fingerprint,
                    contextLines: input.contextLines
                )
            }

            let result = try await searcher.search(
                request,
                workspace: workspace,
                toolName: Self.identifier.rawValue
            )

            return result
            
        }

        public func process(
            _ output: Output,
            input _: Input
        ) -> ToolExecution.Projection? {
            let result = output

            return .init(
                status: "passed",
                summary: "Source \(result.kind.rawValue) search (\(result.mode.rawValue)) returned \(result.returnedCandidateCount) of \(result.totalCandidateCount) candidate region(s) from offset \(result.offset) across \(result.sourceCount) retained source(s).",
                facts: [
                    .init(
                        label: "kind",
                        value: result.kind.rawValue
                    ),
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
        }
    }
}
