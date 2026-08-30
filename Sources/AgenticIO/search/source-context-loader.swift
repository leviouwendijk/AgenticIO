import AgenticWorkspace
import Foundation
import IO
import Path
import Position
import Readers
import Selection

public enum SourceContextLoadError:
    Error,
    Sendable,
    LocalizedError
{
    case emptyCandidates
    case invalidLimit(
        name: String,
        value: Int
    )
    case tooManyCandidates(
        maximum: Int,
        actual: Int
    )
    case conflictingFingerprints(
        path: String
    )
    case missingSourceFingerprint(
        path: String
    )
    case staleSource(
        path: String,
        expected: ContentFingerprint,
        actual: ContentFingerprint
    )
    case candidateRangeTooLarge(
        path: String,
        requestedLines: Int,
        maximumLines: Int
    )
    case totalLineBudgetExceeded(
        actualLines: Int,
        maximumLines: Int
    )

    public var errorDescription: String? {
        switch self {
        case .emptyCandidates:
            return "Search context loading requires at least one source candidate."

        case .invalidLimit(let name, let value):
            return "Search context limit '\(name)' must be greater than or equal to zero; received \(value)."

        case .tooManyCandidates(let maximum, let actual):
            return "Search context requested \(actual) candidate(s), exceeding the maximum of \(maximum)."

        case .conflictingFingerprints(let path):
            return "Search context candidates for '\(path)' carry conflicting source fingerprints."

        case .missingSourceFingerprint(let path):
            return "Current source read for '\(path)' did not produce a content fingerprint."

        case .staleSource(let path, let expected, let actual):
            return "Search context candidate for '\(path)' is stale. Expected source fingerprint \(expected), but current source fingerprint is \(actual)."

        case .candidateRangeTooLarge(let path, let requestedLines, let maximumLines):
            return "Expanded search context candidate for '\(path)' requests \(requestedLines) line(s), exceeding the per-candidate maximum of \(maximumLines)."

        case .totalLineBudgetExceeded(let actualLines, let maximumLines):
            return "Search context materialization produced \(actualLines) line(s), exceeding the total maximum of \(maximumLines)."
        }
    }
}

public struct SourceContextReference:
    Sendable,
    Codable,
    Hashable
{
    public let path: String
    public let sectionKey: String?
    public let sourceFingerprint: ContentFingerprint
    public let lineRange: LineRange

    public init(
        path: String,
        sectionKey: String? = nil,
        sourceFingerprint: ContentFingerprint,
        lineRange: LineRange
    ) {
        self.path = path
        self.sectionKey = sectionKey
        self.sourceFingerprint = sourceFingerprint
        self.lineRange = lineRange
    }

    public init(
        _ candidate: SourceSearchCandidate
    ) {
        self.init(
            path: candidate.path,
            sectionKey: candidate.sectionKey,
            sourceFingerprint: candidate.sourceFingerprint,
            lineRange: candidate.lineRange
        )
    }
}

public struct SourceContextRequest:
    Sendable,
    Codable,
    Hashable
{
    public let rootID: PathAccessRootIdentifier
    public let candidates: [SourceContextReference]
    public let beforeLines: Int
    public let afterLines: Int
    public let maximumCandidates: Int
    public let maximumLinesPerCandidate: Int
    public let maximumTotalLines: Int

    public init(
        rootID: PathAccessRootIdentifier = .project,
        candidates: [SourceContextReference],
        beforeLines: Int = 3,
        afterLines: Int = 3,
        maximumCandidates: Int = 8,
        maximumLinesPerCandidate: Int = 120,
        maximumTotalLines: Int = 320
    ) {
        self.rootID = rootID
        self.candidates = candidates
        self.beforeLines = beforeLines
        self.afterLines = afterLines
        self.maximumCandidates = maximumCandidates
        self.maximumLinesPerCandidate = maximumLinesPerCandidate
        self.maximumTotalLines = maximumTotalLines
    }
}

public struct SourceContextLine:
    Sendable,
    Codable,
    Hashable
{
    public let number: Int
    public let text: String

    public init(
        number: Int,
        text: String
    ) {
        self.number = number
        self.text = text
    }
}

public struct SourceContextSlice:
    Sendable,
    Codable,
    Hashable
{
    public let lineRange: LineRange
    public let lines: [SourceContextLine]

    public init(
        lineRange: LineRange,
        lines: [SourceContextLine]
    ) {
        self.lineRange = lineRange
        self.lines = lines
    }
}

public struct SourceContextFile:
    Sendable,
    Codable,
    Hashable
{
    public let path: String
    public let sectionKeys: [String]
    public let sourceFingerprint: ContentFingerprint
    public let totalLineCount: Int
    public let selectedLineCount: Int
    public let slices: [SourceContextSlice]

    public init(
        path: String,
        sectionKeys: [String],
        sourceFingerprint: ContentFingerprint,
        totalLineCount: Int,
        selectedLineCount: Int,
        slices: [SourceContextSlice]
    ) {
        self.path = path
        self.sectionKeys = sectionKeys
        self.sourceFingerprint = sourceFingerprint
        self.totalLineCount = totalLineCount
        self.selectedLineCount = selectedLineCount
        self.slices = slices
    }
}

public struct SourceContextResult:
    Sendable,
    Codable,
    Hashable
{
    public let rootID: String
    public let candidateCount: Int
    public let sourceCount: Int
    public let totalLineCount: Int
    public let sources: [SourceContextFile]

    public init(
        rootID: String,
        candidateCount: Int,
        sourceCount: Int,
        totalLineCount: Int,
        sources: [SourceContextFile]
    ) {
        self.rootID = rootID
        self.candidateCount = candidateCount
        self.sourceCount = sourceCount
        self.totalLineCount = totalLineCount
        self.sources = sources
    }
}

public struct SourceContextLoader: Sendable {
    public let toolName: String

    public init(
        toolName: String = "load_search_context"
    ) {
        self.toolName = toolName
    }

    public func validate(
        _ request: SourceContextRequest
    ) throws {
        guard !request.candidates.isEmpty else {
            throw SourceContextLoadError.emptyCandidates
        }

        for (name, value) in [
            ("beforeLines", request.beforeLines),
            ("afterLines", request.afterLines),
            ("maximumCandidates", request.maximumCandidates),
            ("maximumLinesPerCandidate", request.maximumLinesPerCandidate),
            ("maximumTotalLines", request.maximumTotalLines),
        ] {
            guard value >= 0 else {
                throw SourceContextLoadError.invalidLimit(
                    name: name,
                    value: value
                )
            }
        }

        guard request.candidates.count <= request.maximumCandidates else {
            throw SourceContextLoadError.tooManyCandidates(
                maximum: request.maximumCandidates,
                actual: request.candidates.count
            )
        }
    }

    public func load(
        _ request: SourceContextRequest,
        workspace: AgentWorkspace
    ) throws -> SourceContextResult {
        try validate(
            request
        )

        let groups = grouped(
            request.candidates
        )
        var sources: [SourceContextFile] = []
        var totalSelectedLines = 0

        for group in groups {
            guard let first = group.candidates.first else {
                continue
            }

            guard group.candidates.allSatisfy({
                $0.sourceFingerprint == first.sourceFingerprint
            }) else {
                throw SourceContextLoadError.conflictingFingerprints(
                    path: group.path
                )
            }

            let authorized = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: request.rootID,
                path: group.path,
                capability: .read,
                toolName: toolName,
                type: .file
            )
            let readResult = try LineReader(
                authorized.absoluteURL
            ).read(
                options: sourceReadOptions
            )

            guard let actualFingerprint = readResult
                .fileSnapshot?
                .contentFingerprint else {
                throw SourceContextLoadError.missingSourceFingerprint(
                    path: authorized.presentationPath
                )
            }

            guard actualFingerprint == first.sourceFingerprint else {
                throw SourceContextLoadError.staleSource(
                    path: authorized.presentationPath,
                    expected: first.sourceFingerprint,
                    actual: actualFingerprint
                )
            }

            let selections = try group.candidates.map { candidate in
                let expanded = try expandedRange(
                    candidate.lineRange,
                    beforeLines: request.beforeLines,
                    afterLines: request.afterLines,
                    path: authorized.presentationPath,
                    maximumLines: request.maximumLinesPerCandidate
                )

                return ContentSelection.lines(
                    expanded
                )
            }
            let resolved = SelectionResolver.resolve(
                file: authorized.absoluteURL,
                readResult: readResult,
                selections: selections
            )

            totalSelectedLines += resolved.selectedLineCount

            guard totalSelectedLines <= request.maximumTotalLines else {
                throw SourceContextLoadError.totalLineBudgetExceeded(
                    actualLines: totalSelectedLines,
                    maximumLines: request.maximumTotalLines
                )
            }

            sources.append(
                SourceContextFile(
                    path: authorized.presentationPath,
                    sectionKeys: uniqueSectionKeys(
                        group.candidates
                    ),
                    sourceFingerprint: actualFingerprint,
                    totalLineCount: resolved.totalLineCount,
                    selectedLineCount: resolved.selectedLineCount,
                    slices: try resolved.slices.map { slice in
                        SourceContextSlice(
                            lineRange: try LineRange(
                                start: slice.startLine,
                                end: slice.endLine
                            ),
                            lines: slice.lines.enumerated().map { offset, text in
                                SourceContextLine(
                                    number: slice.startLine + offset,
                                    text: text
                                )
                            }
                        )
                    }
                )
            )
        }

        return SourceContextResult(
            rootID: request.rootID.rawValue,
            candidateCount: request.candidates.count,
            sourceCount: sources.count,
            totalLineCount: totalSelectedLines,
            sources: sources
        )
    }
}

private extension SourceContextLoader {
    struct CandidateGroup {
        let path: String
        var candidates: [SourceContextReference]
    }

    var sourceReadOptions: LineReadOptions {
        .init(
            text: .init(
                decoding: .commonTextFallbacks,
                missingFilePolicy: .throwError,
                newlineNormalization: .unix
            )
        )
    }

    func grouped(
        _ candidates: [SourceContextReference]
    ) -> [CandidateGroup] {
        var groups: [CandidateGroup] = []
        var indexByPath: [String: Int] = [:]

        for candidate in candidates {
            if let index = indexByPath[candidate.path] {
                groups[index].candidates.append(
                    candidate
                )
            } else {
                indexByPath[candidate.path] = groups.count
                groups.append(
                    CandidateGroup(
                        path: candidate.path,
                        candidates: [
                            candidate,
                        ]
                    )
                )
            }
        }

        return groups
    }

    func expandedRange(
        _ range: LineRange,
        beforeLines: Int,
        afterLines: Int,
        path: String,
        maximumLines: Int
    ) throws -> LineRange {
        let start = max(
            1,
            range.start - beforeLines
        )
        let end = range.end + afterLines
        let requestedLines = max(
            0,
            end - start + 1
        )

        guard requestedLines <= maximumLines else {
            throw SourceContextLoadError.candidateRangeTooLarge(
                path: path,
                requestedLines: requestedLines,
                maximumLines: maximumLines
            )
        }

        return try LineRange(
            start: start,
            end: end
        )
    }

    func uniqueSectionKeys(
        _ candidates: [SourceContextReference]
    ) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for candidate in candidates {
            guard let key = candidate.sectionKey,
                  !seen.contains(key) else {
                continue
            }

            seen.insert(
                key
            )
            result.append(
                key
            )
        }

        return result
    }
}
