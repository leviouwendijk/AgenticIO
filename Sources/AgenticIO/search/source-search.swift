import AgenticWorkspace
import Concatenation
import Foundation
import IO
import Path
import Position
import Readers
import Search

public struct SourceSearchRequest: Sendable {
    public let rootID: PathAccessRootIdentifier
    public let definition: ConcatenationCorpusDefinition
    public let queries: [SearchQuery]
    public let options: SearchOptions
    public let frontierOptions: SearchFrontierOptions

    public init(
        rootID: PathAccessRootIdentifier = .project,
        definition: ConcatenationCorpusDefinition,
        queries: [SearchQuery],
        options: SearchOptions = .defaults,
        frontierOptions: SearchFrontierOptions = .defaults
    ) {
        self.rootID = rootID
        self.definition = definition
        self.queries = queries

        var completeOptions = options
        completeOptions.maximumResults = nil

        self.options = completeOptions
        self.frontierOptions = frontierOptions
    }
}

public struct SourceSearchDocumentID:
    Sendable,
    Codable,
    Hashable
{
    public let path: String
    public let sectionKey: String
    public let sliceIndex: Int
    public let sourceStartLine: Int
    public let sourceFingerprint: ContentFingerprint

    public init(
        path: String,
        sectionKey: String,
        sliceIndex: Int,
        sourceStartLine: Int,
        sourceFingerprint: ContentFingerprint
    ) {
        self.path = path
        self.sectionKey = sectionKey
        self.sliceIndex = sliceIndex
        self.sourceStartLine = sourceStartLine
        self.sourceFingerprint = sourceFingerprint
    }
}

public struct SourceSearchEvidence:
    Sendable,
    Codable,
    Hashable
{
    public let queryID: String?
    public let query: String
    public let strategy: String
    public let score: Int
    public let lineRanges: [LineRange]

    public init(
        queryID: String?,
        query: String,
        strategy: String,
        score: Int,
        lineRanges: [LineRange]
    ) {
        self.queryID = queryID
        self.query = query
        self.strategy = strategy
        self.score = score
        self.lineRanges = lineRanges
    }
}

public struct SourceSearchCandidate:
    Sendable,
    Codable,
    Hashable
{
    public let path: String
    public let sectionKey: String
    public let sourceFingerprint: ContentFingerprint
    public let lineRange: LineRange
    public let score: Int
    public let probeCount: Int
    public let evidence: [SourceSearchEvidence]

    public init(
        path: String,
        sectionKey: String,
        sourceFingerprint: ContentFingerprint,
        lineRange: LineRange,
        score: Int,
        probeCount: Int,
        evidence: [SourceSearchEvidence]
    ) {
        self.path = path
        self.sectionKey = sectionKey
        self.sourceFingerprint = sourceFingerprint
        self.lineRange = lineRange
        self.score = score
        self.probeCount = probeCount
        self.evidence = evidence
    }
}

public struct SourceSearchResult:
    Sendable,
    Codable
{
    public let mode: SearchMode
    public let corpusFingerprint: ContentFingerprint
    public let sourceCount: Int
    public let searchedDocumentCount: Int
    public let matchedDocumentCount: Int
    public let candidateCount: Int
    public let totalCandidateCount: Int
    public let returnedCandidateCount: Int
    public let truncated: Bool
    public let hasMore: Bool
    public let candidates: [SourceSearchCandidate]

    public init(
        mode: SearchMode,
        corpusFingerprint: ContentFingerprint,
        sourceCount: Int,
        searchedDocumentCount: Int,
        matchedDocumentCount: Int,
        candidateCount: Int,
        totalCandidateCount: Int,
        returnedCandidateCount: Int,
        truncated: Bool,
        hasMore: Bool,
        candidates: [SourceSearchCandidate]
    ) {
        self.mode = mode
        self.corpusFingerprint = corpusFingerprint
        self.sourceCount = sourceCount
        self.searchedDocumentCount = searchedDocumentCount
        self.matchedDocumentCount = matchedDocumentCount
        self.candidateCount = candidateCount
        self.totalCandidateCount = totalCandidateCount
        self.returnedCandidateCount = returnedCandidateCount
        self.truncated = truncated
        self.hasMore = hasMore
        self.candidates = candidates
    }
}

public enum SourceSearchError:
    Error,
    Sendable,
    LocalizedError
{
    case emptyQueries
    case sourceOutsideAuthorizedRoot(URL)
    case missingMaterialization(URL)

    public var errorDescription: String? {
        switch self {
        case .emptyQueries:
            return "Source search requires at least one non-empty query."

        case .sourceOutsideAuthorizedRoot(let source):
            return "Resolved source is outside the authorized workspace root: \(source.path)"

        case .missingMaterialization(let root):
            return "Source search refresh did not produce retained materialization for \(root.path)."
        }
    }
}

public actor SourceSearcher {
    private let session: ConcatenationSession

    public init(
        session: ConcatenationSession = .init()
    ) {
        self.session = session
    }

    public func search(
        _ request: SourceSearchRequest,
        workspace: AgentWorkspace,
        toolName: String = "search_sources"
    ) throws -> SourceSearchResult {
        let queries = request.queries.filter {
            !$0.isEmpty
        }

        guard !queries.isEmpty else {
            throw SourceSearchError.emptyQueries
        }

        let root = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: request.rootID,
            path: ".",
            capability: .scan,
            toolName: toolName,
            type: .directory
        )

        let resolution = try request.definition.resolve(
            relativeTo: root.absoluteURL
        )

        let sources = try resolution.sources.map { source in
            let relativePath = try relativePath(
                source.file,
                under: root.absoluteURL
            )
            let authorized = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: request.rootID,
                path: relativePath,
                capability: .read,
                toolName: toolName,
                type: .file
            )

            return ConcatenationSource(
                file: authorized.absoluteURL,
                presentedPath: authorized.presentationPath,
                selections: source.selections
            )
        }

        let corpus = ConcatenationCorpus(
            location: root.absoluteURL,
            plan: ConcatenationPlan(
                context: resolution.plan.context,
                sources: sources,
                options: resolution.plan.options
            ),
            session: session,
            options: .defaults
        )

        _ = try corpus.refresh()

        guard let materialization = try corpus.materialize() else {
            throw SourceSearchError.missingMaterialization(
                root.absoluteURL
            )
        }

        let searchCorpus = makeSearchCorpus(
            materialization
        )
        let result = TextSearch.search(
            queries,
            in: searchCorpus,
            options: request.options
        )
        let frontier = result.frontier(
            options: request.frontierOptions
        )

        return SourceSearchResult(
            mode: frontier.mode,
            corpusFingerprint: materialization.snapshot.fingerprint,
            sourceCount: materialization.sources.count,
            searchedDocumentCount: searchCorpus.count,
            matchedDocumentCount: frontier.matchedDocumentCount,
            candidateCount: frontier.candidateCount,
            totalCandidateCount: frontier.totalCandidateCount,
            returnedCandidateCount: frontier.returnedCandidateCount,
            truncated: frontier.truncated,
            hasMore: frontier.hasMore,
            candidates: frontier.candidates.map(
                sourceCandidate
            )
        )
    }
}

private extension SourceSearcher {
    func relativePath(
        _ source: URL,
        under root: URL
    ) throws -> String {
        let source = source.standardizedFileURL
        let root = root.standardizedFileURL
        let rootPath = root.path.hasSuffix("/")
            ? root.path
            : root.path + "/"

        guard source.path.hasPrefix(rootPath) else {
            throw SourceSearchError.sourceOutsideAuthorizedRoot(
                source
            )
        }

        return String(
            source.path.dropFirst(
                rootPath.count
            )
        )
    }

    func makeSearchCorpus(
        _ materialization: ConcatenationCorpusMaterialization
    ) -> SearchCorpus<SourceSearchDocumentID> {
        var documents: [SearchDocument<SourceSearchDocumentID>] = []

        for source in materialization.sources {
            for (sliceIndex, slice) in source.section.slices.enumerated()
                where !slice.isEmpty
            {
                let identifier = SourceSearchDocumentID(
                    path: source.section.presentedPath,
                    sectionKey: source.record.sectionKey,
                    sliceIndex: sliceIndex,
                    sourceStartLine: slice.startLine,
                    sourceFingerprint: source.record.contentFingerprint
                )

                documents.append(
                    SearchDocument(
                        id: identifier,
                        text: slice.lines.joined(
                            separator: "\n"
                        )
                    )
                )
            }
        }

        return SearchCorpus(
            documents: documents
        )
    }

    func sourceCandidate(
        _ candidate: SearchCandidate<SourceSearchDocumentID>
    ) -> SourceSearchCandidate {
        let document = candidate.documentID

        return SourceSearchCandidate(
            path: document.path,
            sectionKey: document.sectionKey,
            sourceFingerprint: document.sourceFingerprint,
            lineRange: sourceLineRange(
                candidate.lineRange,
                startingAt: document.sourceStartLine
            ),
            score: candidate.score.value,
            probeCount: candidate.probeCount,
            evidence: candidate.evidence.map { evidence in
                SourceSearchEvidence(
                    queryID: evidence.queryID,
                    query: evidence.query,
                    strategy: evidence.strategy.rawValue,
                    score: evidence.score.value,
                    lineRanges: evidence.spans.map { span in
                        sourceLineRange(
                            span.lineRange,
                            startingAt: document.sourceStartLine
                        )
                    }
                )
            }
        )
    }

    func sourceLineRange(
        _ range: LineRange,
        startingAt sourceStartLine: Int
    ) -> LineRange {
        LineRange(
            uncheckedStart: sourceStartLine + range.start - 1,
            uncheckedEnd: sourceStartLine + range.end - 1
        )
    }
}
