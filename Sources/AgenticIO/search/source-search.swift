import Agentic
import Schema
import Workspace
import Concatenation
import Foundation
import IO
import Path
import Position
import Readers
import Search
import Parsing

public struct SourceSearchRequest: Sendable {
    public let rootID: PathAccessRootIdentifier
    public let definition: ConcatenationCorpusDefinition
    public let probes: [SearchProbe]
    public let lexicalPattern: LexicalPattern?
    public let options: SearchOptions
    public let frontierOptions: SearchFrontierOptions
    public let within: [SourceContextReference]
    public let expectedCorpusFingerprint: ContentFingerprint?

    public var queries: [SearchQuery] {
        probes.map(\.query)
    }

    public init(
        rootID: PathAccessRootIdentifier = .project,
        definition: ConcatenationCorpusDefinition,
        probes: [SearchProbe],
        lexicalPattern: LexicalPattern? = nil,
        options: SearchOptions = .defaults,
        frontierOptions: SearchFrontierOptions = .defaults,
        within: [SourceContextReference] = [],
        expectedCorpusFingerprint: ContentFingerprint? = nil
    ) {
        self.rootID = rootID
        self.definition = definition
        self.probes = probes
        self.lexicalPattern = lexicalPattern

        var completeOptions = options
        completeOptions.maximumResults = nil

        self.options = completeOptions
        self.frontierOptions = frontierOptions
        self.within = within
        self.expectedCorpusFingerprint = expectedCorpusFingerprint
    }

    public init(
        rootID: PathAccessRootIdentifier = .project,
        definition: ConcatenationCorpusDefinition,
        queries: [SearchQuery],
        options: SearchOptions = .defaults,
        frontierOptions: SearchFrontierOptions = .defaults,
        within: [SourceContextReference] = [],
        expectedCorpusFingerprint: ContentFingerprint? = nil
    ) {
        self.init(
            rootID: rootID,
            definition: definition,
            probes: queries.map { query in
                SearchProbe(
                    query,
                    role: .preferred,
                    strategy: options.strategy
                )
            },
            lexicalPattern: nil,
            options: options,
            frontierOptions: frontierOptions,
            within: within,
            expectedCorpusFingerprint: expectedCorpusFingerprint
        )
    }

    public init(
        rootID: PathAccessRootIdentifier = .project,
        definition: ConcatenationCorpusDefinition,
        lexicalPattern: LexicalPattern,
        options: SearchOptions = .defaults,
        frontierOptions: SearchFrontierOptions = .defaults,
        within: [SourceContextReference] = [],
        expectedCorpusFingerprint: ContentFingerprint? = nil
    ) {
        self.init(
            rootID: rootID,
            definition: definition,
            probes: [],
            lexicalPattern: lexicalPattern,
            options: options,
            frontierOptions: frontierOptions,
            within: within,
            expectedCorpusFingerprint: expectedCorpusFingerprint
        )
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

public enum SourceSearchKind:
    String,
    Sendable,
    Codable,
    Hashable
{
    case text
    case lexical
}

public struct SourceSearchCapture:
    Sendable,
    Codable,
    Hashable
{
    public let name: String
    public let lineRange: LineRange
    public let tokens: [String]

    public init(
        name: String,
        lineRange: LineRange,
        tokens: [String]
    ) {
        self.name = name
        self.lineRange = lineRange
        self.tokens = tokens
    }
}

public struct SourceSearchEvidence:
    Sendable,
    Codable,
    Hashable
{
    public let queryID: String?
    public let query: String
    public let role: String
    public let strategy: String
    public let score: Int
    public let lineRanges: [LineRange]

    public init(
        queryID: String?,
        query: String,
        role: String,
        strategy: String,
        score: Int,
        lineRanges: [LineRange]
    ) {
        self.queryID = queryID
        self.query = query
        self.role = role
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
    public let captures: [SourceSearchCapture]

    public init(
        path: String,
        sectionKey: String,
        sourceFingerprint: ContentFingerprint,
        lineRange: LineRange,
        score: Int,
        probeCount: Int,
        evidence: [SourceSearchEvidence],
        captures: [SourceSearchCapture] = []
    ) {
        self.path = path
        self.sectionKey = sectionKey
        self.sourceFingerprint = sourceFingerprint
        self.lineRange = lineRange
        self.score = score
        self.probeCount = probeCount
        self.evidence = evidence
        self.captures = captures
    }
}

public struct SourceSearchResult: Result {
    public static var jsonschema: JSONSchema {
        .object()
    }

    public let kind: SourceSearchKind
    public let mode: SearchMode
    public let corpusFingerprint: ContentFingerprint
    public let sourceCount: Int
    public let searchedDocumentCount: Int
    public let matchedDocumentCount: Int
    public let discoveredCandidateCount: Int
    public let totalCandidateCount: Int
    public let offset: Int
    public let returnedCandidateCount: Int
    public let nextOffset: Int?
    public let truncated: Bool
    public let hasMore: Bool
    public let candidates: [SourceSearchCandidate]

    public init(
        kind: SourceSearchKind = .text,
        mode: SearchMode,
        corpusFingerprint: ContentFingerprint,
        sourceCount: Int,
        searchedDocumentCount: Int,
        matchedDocumentCount: Int,
        discoveredCandidateCount: Int,
        totalCandidateCount: Int,
        offset: Int,
        returnedCandidateCount: Int,
        nextOffset: Int?,
        truncated: Bool,
        hasMore: Bool,
        candidates: [SourceSearchCandidate]
    ) {
        self.kind = kind
        self.mode = mode
        self.corpusFingerprint = corpusFingerprint
        self.sourceCount = sourceCount
        self.searchedDocumentCount = searchedDocumentCount
        self.matchedDocumentCount = matchedDocumentCount
        self.discoveredCandidateCount = discoveredCandidateCount
        self.totalCandidateCount = totalCandidateCount
        self.offset = offset
        self.returnedCandidateCount = returnedCandidateCount
        self.nextOffset = nextOffset
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
    case emptySearch
    case conflictingSearchModes
    case sourceOutsideAuthorizedRoot(URL)
    case missingMaterialization(URL)
    case staleCorpus(
        expected: ContentFingerprint,
        actual: ContentFingerprint
    )

    public var errorDescription: String? {
        switch self {
        case .emptySearch:
            return "Source search requires either at least one non-empty probe or one lexical pattern."

        case .conflictingSearchModes:
            return "Source search accepts text probes or one lexical pattern per request, not both."

        case .sourceOutsideAuthorizedRoot(let source):
            return "Resolved source is outside the authorized workspace root: \(source.path)"

        case .missingMaterialization(let root):
            return "Source search refresh did not produce retained materialization for \(root.path)."

        case .staleCorpus(let expected, let actual):
            return "Source search continuation is stale. Expected corpus fingerprint \(expected), but current corpus fingerprint is \(actual). Restart from offset 0."
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
        workspace: WorkspaceContext,
        toolName: String = "search_sources"
    ) throws -> SourceSearchResult {
        let probes = request.probes.filter {
            !$0.isEmpty
        }
        let lexicalPattern = request.lexicalPattern

        guard !probes.isEmpty || lexicalPattern != nil else {
            throw SourceSearchError.emptySearch
        }

        guard probes.isEmpty || lexicalPattern == nil else {
            throw SourceSearchError.conflictingSearchModes
        }

        if !request.within.isEmpty {
            return try search(
                request,
                probes: probes,
                lexicalPattern: lexicalPattern,
                within: request.within,
                workspace: workspace,
                toolName: toolName
            )
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

        let corpusFingerprint = materialization.snapshot.fingerprint

        if let expectedCorpusFingerprint = request.expectedCorpusFingerprint,
           expectedCorpusFingerprint != corpusFingerprint
        {
            throw SourceSearchError.staleCorpus(
                expected: expectedCorpusFingerprint,
                actual: corpusFingerprint
            )
        }

        let searchCorpus = makeSearchCorpus(
            materialization
        )

        return sourceSearchResult(
            request,
            probes: probes,
            lexicalPattern: lexicalPattern,
            in: searchCorpus,
            corpusFingerprint: corpusFingerprint,
            sourceCount: materialization.sources.count
        )
    }
}

private extension SourceSearcher {
    func search(
        _ request: SourceSearchRequest,
        probes: [SearchProbe],
        lexicalPattern: LexicalPattern?,
        within candidates: [SourceContextReference],
        workspace: WorkspaceContext,
        toolName: String
    ) throws -> SourceSearchResult {
        let corpusFingerprint = refinementFingerprint(
            for: candidates
        )

        if let expectedCorpusFingerprint = request.expectedCorpusFingerprint,
           expectedCorpusFingerprint != corpusFingerprint
        {
            throw SourceSearchError.staleCorpus(
                expected: expectedCorpusFingerprint,
                actual: corpusFingerprint
            )
        }

        let searchCorpus = try makeSearchCorpus(
            candidates,
            rootID: request.rootID,
            workspace: workspace,
            toolName: toolName
        )
        return sourceSearchResult(
            request,
            probes: probes,
            lexicalPattern: lexicalPattern,
            in: searchCorpus,
            corpusFingerprint: corpusFingerprint,
            sourceCount: Set(candidates.map(\.path)).count
        )
    }

    func sourceSearchResult(
        _ request: SourceSearchRequest,
        probes: [SearchProbe],
        lexicalPattern: LexicalPattern?,
        in searchCorpus: SearchCorpus<SourceSearchDocumentID>,
        corpusFingerprint: ContentFingerprint,
        sourceCount: Int
    ) -> SourceSearchResult {
        if let lexicalPattern {
            return lexicalSourceSearchResult(
                request,
                pattern: lexicalPattern,
                in: searchCorpus,
                corpusFingerprint: corpusFingerprint,
                sourceCount: sourceCount
            )
        }

        let result = TextSearch.search(
            probes: probes,
            in: searchCorpus,
            options: request.options
        )
        let frontier = result.frontier(
            options: request.frontierOptions
        )

        return SourceSearchResult(
            kind: .text,
            mode: frontier.mode,
            corpusFingerprint: corpusFingerprint,
            sourceCount: sourceCount,
            searchedDocumentCount: searchCorpus.count,
            matchedDocumentCount: frontier.matchedDocumentCount,
            discoveredCandidateCount: frontier.discoveredCandidateCount,
            totalCandidateCount: frontier.totalCandidateCount,
            offset: frontier.offset,
            returnedCandidateCount: frontier.returnedCandidateCount,
            nextOffset: frontier.nextOffset,
            truncated: frontier.truncated,
            hasMore: frontier.hasMore,
            candidates: frontier.candidates.map(
                sourceCandidate
            )
        )
    }

    func lexicalSourceSearchResult(
        _ request: SourceSearchRequest,
        pattern: LexicalPattern,
        in searchCorpus: SearchCorpus<SourceSearchDocumentID>,
        corpusFingerprint: ContentFingerprint,
        sourceCount: Int
    ) -> SourceSearchResult {
        let result = LexicalSearch.search(
            pattern,
            in: searchCorpus,
            caseSensitive: request.options.caseSensitive
        )
        let semanticMatches: [
            LexicalMatch<SourceSearchDocumentID>
        ]

        switch request.options.mode {
        case .ranked:
            semanticMatches = diversifiedLexicalMatches(
                result.matches,
                maximumCandidatesPerDocument:
                    request.frontierOptions.maximumCandidatesPerDocument
            )

        case .exhaustive:
            semanticMatches = result.matches
        }

        let offset = request.frontierOptions.offset
        let pageStart = min(
            offset,
            semanticMatches.count
        )
        let remaining = semanticMatches.dropFirst(
            pageStart
        )
        let selected: [LexicalMatch<SourceSearchDocumentID>]

        if let maximumCandidates = request.frontierOptions.maximumCandidates {
            selected = Array(
                remaining.prefix(
                    maximumCandidates
                )
            )
        } else {
            selected = Array(
                remaining
            )
        }

        let hasMore = pageStart + selected.count < semanticMatches.count
        let nextOffset = hasMore && !selected.isEmpty
            ? offset + selected.count
            : nil
        let truncated = (
            semanticMatches.count > 0
                && offset > 0
        ) || hasMore

        return SourceSearchResult(
            kind: .lexical,
            mode: request.options.mode,
            corpusFingerprint: corpusFingerprint,
            sourceCount: sourceCount,
            searchedDocumentCount: result.searchedDocumentCount,
            matchedDocumentCount: result.matchedDocumentCount,
            discoveredCandidateCount: result.matchCount,
            totalCandidateCount: semanticMatches.count,
            offset: offset,
            returnedCandidateCount: selected.count,
            nextOffset: nextOffset,
            truncated: truncated,
            hasMore: hasMore,
            candidates: selected.map(
                sourceCandidate
            )
        )
    }

    func diversifiedLexicalMatches(
        _ matches: [LexicalMatch<SourceSearchDocumentID>],
        maximumCandidatesPerDocument: Int?
    ) -> [LexicalMatch<SourceSearchDocumentID>] {
        guard let maximumCandidatesPerDocument else {
            return matches
        }

        var selected: [LexicalMatch<SourceSearchDocumentID>] = []
        var documentCounts: [SourceSearchDocumentID: Int] = [:]

        for match in matches {
            let count = documentCounts[
                match.documentID,
                default: 0
            ]

            guard count < maximumCandidatesPerDocument else {
                continue
            }

            documentCounts[match.documentID] = count + 1
            selected.append(
                match
            )
        }

        return selected
    }

    func makeSearchCorpus(
        _ candidates: [SourceContextReference],
        rootID: PathAccessRootIdentifier,
        workspace: WorkspaceContext,
        toolName: String
    ) throws -> SearchCorpus<SourceSearchDocumentID> {
        let maximumCandidates = 8
        let maximumLinesPerCandidate = 120
        let maximumTotalLines = 320

        guard candidates.count <= maximumCandidates else {
            throw SourceContextLoadError.tooManyCandidates(
                maximum: maximumCandidates,
                actual: candidates.count
            )
        }

        var documents: [SearchDocument<SourceSearchDocumentID>] = []
        var admittedLineCount = 0
        let loader = SourceContextLoader(
            toolName: toolName
        )

        for candidate in candidates {
            let requestedLines = max(
                1,
                candidate.lineRange.end - candidate.lineRange.start + 1
            )

            guard requestedLines <= maximumLinesPerCandidate else {
                throw SourceContextLoadError.candidateRangeTooLarge(
                    path: candidate.path,
                    requestedLines: requestedLines,
                    maximumLines: maximumLinesPerCandidate
                )
            }

            admittedLineCount += requestedLines

            guard admittedLineCount <= maximumTotalLines else {
                throw SourceContextLoadError.totalLineBudgetExceeded(
                    actualLines: admittedLineCount,
                    maximumLines: maximumTotalLines
                )
            }

            let context = try loader.load(
                SourceContextRequest(
                    rootID: rootID,
                    candidates: [
                        candidate,
                    ],
                    beforeLines: 0,
                    afterLines: 0,
                    maximumCandidates: 1,
                    maximumLinesPerCandidate: maximumLinesPerCandidate,
                    maximumTotalLines: maximumLinesPerCandidate
                ),
                workspace: workspace
            )

            for source in context.sources {
                for slice in source.slices where !slice.lines.isEmpty {
                    documents.append(
                        SearchDocument(
                            id: SourceSearchDocumentID(
                                path: source.path,
                                sectionKey: candidate.sectionKey
                                    ?? source.sectionKeys.first
                                    ?? "",
                                sliceIndex: documents.count,
                                sourceStartLine: slice.lineRange.start,
                                sourceFingerprint: source.sourceFingerprint
                            ),
                            text: slice.lines
                                .map(\.text)
                                .joined(
                                    separator: "\n"
                                )
                        )
                    )
                }
            }
        }

        return SearchCorpus(
            documents: documents
        )
    }

    func refinementFingerprint(
        for candidates: [SourceContextReference]
    ) -> ContentFingerprint {
        ContentFingerprint.fingerprint(
            for: candidates.map { candidate in
                [
                    candidate.path,
                    candidate.sectionKey ?? "",
                    candidate.sourceFingerprint.description,
                    "\(candidate.lineRange.start):\(candidate.lineRange.end)",
                ].joined(
                    separator: "\u{0}"
                )
            }.joined(
                separator: "\n"
            )
        )
    }

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
                    role: evidence.role.rawValue,
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

    func sourceCandidate(
        _ match: LexicalMatch<SourceSearchDocumentID>
    ) -> SourceSearchCandidate {
        let document = match.documentID

        return SourceSearchCandidate(
            path: document.path,
            sectionKey: document.sectionKey,
            sourceFingerprint: document.sourceFingerprint,
            lineRange: sourceLineRange(
                match.lineRange,
                startingAt: document.sourceStartLine
            ),
            score: 1,
            probeCount: 0,
            evidence: [],
            captures: match.captures.map { capture in
                SourceSearchCapture(
                    name: capture.name,
                    lineRange: sourceLineRange(
                        capture.lineRange,
                        startingAt: document.sourceStartLine
                    ),
                    tokens: capture.tokens.map {
                        $0.string()
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
