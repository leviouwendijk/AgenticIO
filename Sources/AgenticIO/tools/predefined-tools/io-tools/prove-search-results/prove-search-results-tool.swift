import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Parsing
import Path
import Position
import Primitives
import Schema
import SchemaMacros
import Search

@JSONSchema
public enum SourceProofSpecificationNodeInput:
    Sendable,
    Codable,
    Hashable
{
    case literal(value: String)
    case identifier
    case sequence(children: [Int])
    case choice(children: [Int])
    case optional(child: Int)
    case repetition(
        child: Int,
        minimum: Int,
        maximum: Int?
    )
    case capture(
        name: String,
        child: Int
    )
    case until(child: Int)
    case balanced(
        opening: String,
        closing: String
    )
}

@JSONSchema
public struct SourceProofSpecificationInput:
    Sendable,
    Codable,
    Hashable
{
    /// A flat structural-expression graph. Node references are zero-based indices.
    /// To keep the model-authored graph acyclic and bounded, nodes may reference
    /// only nodes that appear earlier in this array.
    public let nodes: [SourceProofSpecificationNodeInput]

    /// Zero-based index of the node used as the final proof specification.
    public let root: Int

    public init(
        nodes: [SourceProofSpecificationNodeInput],
        root: Int
    ) {
        self.nodes = nodes
        self.root = root
    }

    func parserSpecification() throws -> StructuredParser.Specification {
        guard !nodes.isEmpty else {
            throw SourceProofSpecificationInputError.emptyNodes
        }

        guard nodes.indices.contains(root) else {
            throw SourceProofSpecificationInputError.invalidRoot(
                root
            )
        }

        var specifications: [StructuredParser.Specification] = []
        specifications.reserveCapacity(
            nodes.count
        )

        for (
            index,
            node
        ) in nodes.enumerated() {
            specifications.append(
                try node.parserSpecification(
                    index: index,
                    prior: specifications
                )
            )
        }

        return specifications[root]
    }
}

public enum SourceProofSpecificationInputError:
    Error,
    Sendable,
    LocalizedError
{
    case emptyNodes
    case invalidRoot(Int)
    case invalidReference(
        node: Int,
        referenced: Int
    )

    public var errorDescription: String? {
        switch self {
        case .emptyNodes:
            "Source proof specification requires at least one node."

        case .invalidRoot(let root):
            "Source proof specification root index \(root) is outside the node array."

        case .invalidReference(
            let node,
            let referenced
        ):
            "Source proof node \(node) references node \(referenced). Nodes may reference only earlier nodes."
        }
    }
}

private extension SourceProofSpecificationNodeInput {
    func parserSpecification(
        index: Int,
        prior: [StructuredParser.Specification]
    ) throws -> StructuredParser.Specification {
        func resolve(
            _ reference: Int
        ) throws -> StructuredParser.Specification {
            guard prior.indices.contains(reference) else {
                throw SourceProofSpecificationInputError
                    .invalidReference(
                        node: index,
                        referenced: reference
                    )
            }

            return prior[reference]
        }

        switch self {
        case .literal(let value):
            return .literal(value)

        case .identifier:
            return .identifier

        case .sequence(let children):
            return .sequence(
                try children.map(resolve)
            )

        case .choice(let children):
            return .choice(
                try children.map(resolve)
            )

        case .optional(let child):
            return .optional(
                try resolve(child)
            )

        case .repetition(
            let child,
            let minimum,
            let maximum
        ):
            return .repetition(
                specification: try resolve(child),
                minimum: minimum,
                maximum: maximum
            )

        case .capture(
            let name,
            let child
        ):
            return .capture(
                name: name,
                specification: try resolve(child)
            )

        case .until(let child):
            return .until(
                try resolve(child)
            )

        case .balanced(
            let opening,
            let closing
        ):
            return .balanced(
                opening: opening,
                closing: closing
            )
        }
    }
}

@JSONSchema
public enum SourceProofCardinalityInput:
    Sendable,
    Codable,
    Hashable
{
    case exactly(count: Int)
    case atLeast(count: Int)
    case atMost(count: Int)

    var parserCardinality: StructuredParser.Cardinality {
        switch self {
        case .exactly(let count):
            .exactly(count)

        case .atLeast(let count):
            .atLeast(count)

        case .atMost(let count):
            .atMost(count)
        }
    }
}

@JSONSchema
public struct ProveSearchResultsToolInput:
    Sendable,
    Codable,
    Hashable
{
    /// Workspace root identifier. Defaults to project.
    @Schema(required: false)
    public let rootID: PathAccessRootIdentifier

    /// Search candidate references to freshness-validate and prove.
    public let candidates: [SourceContextCandidateInput]

    /// Candidate-local structural specification.
    public let specification: SourceProofSpecificationInput

    /// Required match cardinality per candidate. Defaults to at least one.
    @Schema(required: false)
    public let cardinality: SourceProofCardinalityInput

    /// Maximum candidate count admitted for proof.
    @Schema(required: false)
    public let maximumCandidates: Int

    /// Maximum lines admitted from one candidate.
    @Schema(required: false)
    public let maximumLinesPerCandidate: Int

    /// Maximum lines admitted across the request.
    @Schema(required: false)
    public let maximumTotalLines: Int

    public init(
        rootID: PathAccessRootIdentifier = .project,
        candidates: [SourceContextCandidateInput],
        specification: SourceProofSpecificationInput,
        cardinality: SourceProofCardinalityInput = .atLeast(
            count: 1
        ),
        maximumCandidates: Int = 8,
        maximumLinesPerCandidate: Int = 120,
        maximumTotalLines: Int = 320
    ) {
        self.rootID = rootID
        self.candidates = candidates
        self.specification = specification
        self.cardinality = cardinality
        self.maximumCandidates = maximumCandidates
        self.maximumLinesPerCandidate = maximumLinesPerCandidate
        self.maximumTotalLines = maximumTotalLines
    }
}

private extension ProveSearchResultsToolInput {
    enum CodingKeys:
        String,
        CodingKey
    {
        case rootID
        case candidates
        case specification
        case cardinality
        case maximumCandidates
        case maximumLinesPerCandidate
        case maximumTotalLines
    }
}

public extension ProveSearchResultsToolInput {
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
            candidates: try container.decode(
                [SourceContextCandidateInput].self,
                forKey: .candidates
            ),
            specification: try container.decode(
                SourceProofSpecificationInput.self,
                forKey: .specification
            ),
            cardinality: try container.decodeIfPresent(
                SourceProofCardinalityInput.self,
                forKey: .cardinality
            ) ?? .atLeast(
                count: 1
            ),
            maximumCandidates: try container.decodeIfPresent(
                Int.self,
                forKey: .maximumCandidates
            ) ?? 8,
            maximumLinesPerCandidate: try container.decodeIfPresent(
                Int.self,
                forKey: .maximumLinesPerCandidate
            ) ?? 120,
            maximumTotalLines: try container.decodeIfPresent(
                Int.self,
                forKey: .maximumTotalLines
            ) ?? 320
        )
    }
}

public struct SourceProofRange:
    Sendable,
    Codable,
    Hashable
{
    public let offsetStart: Int
    public let offsetEnd: Int
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int

    public init(
        offsetStart: Int,
        offsetEnd: Int,
        startLine: Int,
        startColumn: Int,
        endLine: Int,
        endColumn: Int
    ) {
        self.offsetStart = offsetStart
        self.offsetEnd = offsetEnd
        self.startLine = startLine
        self.startColumn = startColumn
        self.endLine = endLine
        self.endColumn = endColumn
    }
}

public struct SourceProofCaptureResult:
    Sendable,
    Codable,
    Hashable
{
    public let name: String
    public let value: String
    public let range: SourceProofRange
}

public struct SourceProofMatchResult:
    Sendable,
    Codable,
    Hashable
{
    public let range: SourceProofRange
    public let captures: [SourceProofCaptureResult]
}

public struct SourceCandidateProofResult:
    Sendable,
    Codable,
    Hashable
{
    public let path: String
    public let sectionKey: String?
    public let sourceFingerprint: SourceFingerprintInput
    public let candidateLineRange: SourceLineRangeInput
    public let matches: [SourceProofMatchResult]
}

public struct ProveSearchResultsToolOutput:
    Sendable,
    Codable,
    Hashable
{
    public let rootID: String
    public let candidateCount: Int
    public let provenCandidateCount: Int
    public let matchCount: Int
    public let proofs: [SourceCandidateProofResult]
}

public enum ProveSearchResultsToolError:
    Error,
    Sendable,
    LocalizedError
{
    case missingCandidateMaterial(
        path: String,
        startLine: Int,
        endLine: Int
    )

    public var errorDescription: String? {
        switch self {
        case .missingCandidateMaterial(
            let path,
            let startLine,
            let endLine
        ):
            "Fresh source material did not contain the complete proof candidate \(path):\(startLine)-\(endLine)."
        }
    }
}

public struct ProveSearchResultsTool:
    AgentTool
{
    public typealias Input = ProveSearchResultsToolInput
    public typealias Output = ProveSearchResultsToolOutput

    public static let identifier: AgentToolIdentifier =
        "prove_search_results"

    public static let description =
        """
        Structurally prove freshness-validated source-search candidates through Search and Parsing. Reauthorize candidate files, reject stale fingerprints, evaluate only bounded candidate material, return exact match and capture coordinates, and never execute arbitrary code or mutate files.
        """

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

    private let loader: SourceContextLoader

    public init() {
        loader = SourceContextLoader(
            toolName: Self.identifier.rawValue
        )
    }

    public func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {
        let workspace = try FileToolSupport.requireWorkspace(
            context.workspace,
            toolName: name
        )
        let request = try sourceContextRequest(
            from: input
        )

        _ = try input.specification
            .parserSpecification()
            .compile()

        try loader.validate(
            request
        )

        var targetPaths: [String] = []
        var seen: Set<String> = []

        for candidate in input.candidates {
            let authorized = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: input.rootID,
                path: candidate.path,
                capability: .read,
                toolName: name,
                type: .file
            )

            if seen.insert(
                authorized.presentationPath
            ).inserted {
                targetPaths.append(
                    authorized.presentationPath
                )
            }
        }

        return ToolPreflight(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace.rootURL.path,
            targetPaths: targetPaths,
            summary: "Freshness-validate and structurally prove \(input.candidates.count) source search candidate(s).",
            rootIDs: [
                input.rootID.rawValue,
            ],
            capabilitiesRequired: [
                .read,
            ],
            policyChecks: [
                "workspace_required",
                "workspace_read_authorized",
                "search_candidate_source_fingerprint_required",
                "stale_search_context_rejected",
                "selection_resolver_materialization",
                "candidate_bounded_structural_proof",
                "structured_parser_specification",
                "no_source_content_returned",
                "no_file_mutation",
            ]
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {
        let workspace = try FileToolSupport.requireWorkspace(
            context.workspace,
            toolName: name
        )
        let context = try loader.load(
            try sourceContextRequest(
                from: input
            ),
            workspace: workspace
        )
        let materials = try proofMaterials(
            input: input,
            context: context
        )
        let corpus = SearchCorpus(
            documents: materials.enumerated().map {
                index,
                material in

                SearchDocument(
                    id: index,
                    text: material.text
                )
            }
        )
        let frontier = SearchFrontier(
            mode: .exhaustive,
            matchedDocumentCount: materials.count,
            searchedHitCount: materials.count,
            discoveredCandidateCount: materials.count,
            totalCandidateCount: materials.count,
            offset: 0,
            candidates: materials.enumerated().map {
                index,
                material in

                SearchCandidate(
                    documentID: index,
                    lineRange: LineRange(
                        uncheckedStart: 1,
                        uncheckedEnd: material.lines.count
                    ),
                    score: .zero,
                    evidence: []
                )
            }
        )
        let specification = try input.specification
            .parserSpecification()
        let result = try frontier.prove(
            in: corpus,
            with: specification,
            requiring: input.cardinality.parserCardinality
        )
        let proofs = result.proofs.map {
            proof in

            let material = materials[proof.documentID]

            return SourceCandidateProofResult(
                path: material.input.path,
                sectionKey: material.input.sectionKey,
                sourceFingerprint: material.input.sourceFingerprint,
                candidateLineRange: material.input.lineRange,
                matches: proof.matches.map {
                    match in

                    SourceProofMatchResult(
                        range: sourceRange(
                            match.range,
                            lines: material.lines
                        ),
                        captures: match.captures.map {
                            capture in

                            SourceProofCaptureResult(
                                name: capture.name,
                                value: capture.value,
                                range: sourceRange(
                                    capture.range,
                                    lines: material.lines
                                )
                            )
                        }
                    )
                }
            )
        }

        return ProveSearchResultsToolOutput(
            rootID: input.rootID.rawValue,
            candidateCount: result.candidateCount,
            provenCandidateCount: result.provenCandidateCount,
            matchCount: result.matchCount,
            proofs: proofs
        )
        
    }
}

private extension ProveSearchResultsTool {
    struct ProofMaterial {
        let input: SourceContextCandidateInput
        let lines: [SourceContextLine]
        let text: String
    }

    func sourceContextRequest(
        from input: ProveSearchResultsToolInput
    ) throws -> SourceContextRequest {
        SourceContextRequest(
            rootID: input.rootID,
            candidates: try input.candidates.map {
                try $0.reference()
            },
            beforeLines: 0,
            afterLines: 0,
            maximumCandidates: input.maximumCandidates,
            maximumLinesPerCandidate: input.maximumLinesPerCandidate,
            maximumTotalLines: input.maximumTotalLines
        )
    }

    func proofMaterials(
        input: ProveSearchResultsToolInput,
        context: SourceContextResult
    ) throws -> [ProofMaterial] {
        try input.candidates.map {
            candidate in

            let lineRange = try candidate.lineRange.lineRange()

            guard let source = context.sources.first(
                where: {
                    $0.path == candidate.path
                        && $0.sourceFingerprint
                            == candidate.sourceFingerprint.fingerprint
                }
            ) else {
                throw ProveSearchResultsToolError
                    .missingCandidateMaterial(
                        path: candidate.path,
                        startLine: lineRange.start,
                        endLine: lineRange.end
                    )
            }

            var linesByNumber: [Int: SourceContextLine] = [:]

            for slice in source.slices {
                for line in slice.lines {
                    linesByNumber[line.number] = line
                }
            }

            let lines = (lineRange.start...lineRange.end)
                .compactMap {
                    linesByNumber[$0]
                }

            guard lines.count == lineRange.end - lineRange.start + 1 else {
                throw ProveSearchResultsToolError
                    .missingCandidateMaterial(
                        path: candidate.path,
                        startLine: lineRange.start,
                        endLine: lineRange.end
                    )
            }

            return ProofMaterial(
                input: candidate,
                lines: lines,
                text: lines.map(\.text).joined(
                    separator: "\n"
                )
            )
        }
    }

    func sourceRange(
        _ range: PositionRange,
        lines: [SourceContextLine]
    ) -> SourceProofRange {
        let start = sourcePoint(
            offset: range.start.offset,
            lines: lines
        )
        let end = sourcePoint(
            offset: range.end.offset,
            lines: lines
        )

        return SourceProofRange(
            offsetStart: range.start.offset,
            offsetEnd: range.end.offset,
            startLine: start.line,
            startColumn: start.column,
            endLine: end.line,
            endColumn: end.column
        )
    }

    func sourcePoint(
        offset: Int,
        lines: [SourceContextLine]
    ) -> (
        line: Int,
        column: Int
    ) {
        guard let first = lines.first else {
            return (
                1,
                1
            )
        }

        var remaining = max(
            0,
            offset
        )

        for (
            index,
            line
        ) in lines.enumerated() {
            let lineLength = line.text.count

            if remaining <= lineLength {
                return (
                    line.number,
                    remaining + 1
                )
            }

            remaining -= lineLength

            if index < lines.count - 1 {
                remaining = max(
                    0,
                    remaining - 1
                )
            }
        }

        let last = lines.last ?? first

        return (
            last.number,
            last.text.count + 1
        )
    }
}