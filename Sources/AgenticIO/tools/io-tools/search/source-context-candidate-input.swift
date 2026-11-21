import Agentic
import Workspace
import IO
import Path
import Position
import Primitives
import Schema
import Macros

@JSONSchema
public struct SourceFingerprintInput:
    Sendable,
    Codable,
    Hashable
{
    public let algorithm: String
    public let value: String

    public init(
        algorithm: String,
        value: String
    ) {
        self.algorithm = algorithm
        self.value = value
    }

    public init(
        _ fingerprint: ContentFingerprint
    ) {
        self.init(
            algorithm: fingerprint.algorithm,
            value: fingerprint.value
        )
    }

    public var fingerprint: ContentFingerprint {
        ContentFingerprint(
            algorithm: algorithm,
            value: value
        )
    }
}

@JSONSchema
public struct SourceLineRangeInput:
    Sendable,
    Codable,
    Hashable
{
    public let start: Int
    public let end: Int

    public init(
        start: Int,
        end: Int
    ) {
        self.start = start
        self.end = end
    }

    public init(
        _ range: LineRange
    ) {
        self.init(
            start: range.start,
            end: range.end
        )
    }

    public func lineRange() throws -> LineRange {
        try LineRange(
            start: start,
            end: end
        )
    }
}

@JSONSchema
public struct SourceContextCandidateInput:
    Sendable,
    Codable,
    Hashable
{
    public let path: String
    public let sectionKey: String?
    public let sourceFingerprint: SourceFingerprintInput
    public let lineRange: SourceLineRangeInput

    public init(
        path: String,
        sectionKey: String? = nil,
        sourceFingerprint: SourceFingerprintInput,
        lineRange: SourceLineRangeInput
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
            sourceFingerprint: .init(
                candidate.sourceFingerprint
            ),
            lineRange: .init(
                candidate.lineRange
            )
        )
    }

    public func reference() throws -> SourceContextReference {
        SourceContextReference(
            path: path,
            sectionKey: sectionKey,
            sourceFingerprint: sourceFingerprint.fingerprint,
            lineRange: try lineRange.lineRange()
        )
    }
}
