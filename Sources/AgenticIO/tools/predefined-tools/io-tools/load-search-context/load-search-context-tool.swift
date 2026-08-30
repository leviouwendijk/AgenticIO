import Agentic
import AgenticExecution
import AgenticWorkspace
import IO
import Path
import Position
import Primitives
import Schema
import SchemaMacros

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

@JSONSchema
public struct LoadSearchContextToolInput:
    Sendable,
    Codable,
    Hashable
{
    @Schema(required: false)
    public let rootID: PathAccessRootIdentifier

    public let candidates: [SourceContextCandidateInput]

    @Schema(required: false)
    public let beforeLines: Int

    @Schema(required: false)
    public let afterLines: Int

    @Schema(required: false)
    public let maximumCandidates: Int

    @Schema(required: false)
    public let maximumLinesPerCandidate: Int

    @Schema(required: false)
    public let maximumTotalLines: Int

    public init(
        rootID: PathAccessRootIdentifier = .project,
        candidates: [SourceContextCandidateInput],
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

private extension LoadSearchContextToolInput {
    enum CodingKeys: String, CodingKey {
        case rootID
        case candidates
        case beforeLines
        case afterLines
        case maximumCandidates
        case maximumLinesPerCandidate
        case maximumTotalLines
    }
}

public extension LoadSearchContextToolInput {
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
            beforeLines: try container.decodeIfPresent(
                Int.self,
                forKey: .beforeLines
            ) ?? 3,
            afterLines: try container.decodeIfPresent(
                Int.self,
                forKey: .afterLines
            ) ?? 3,
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

public struct LoadSearchContextTool: TypedInstanceAgentTool {
    public typealias Input = LoadSearchContextToolInput

    public static let identifier: AgentToolIdentifier = "load_search_context"
    public static let description = "Load bounded exact source slices from search_sources candidates after reauthorizing paths and validating that source fingerprints are still current."
    public static let risk: ActionRisk = .observe

    public let loader: SourceContextLoader

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }

    public var risk: ActionRisk {
        Self.risk
    }

    public init(
        loader: SourceContextLoader = .init()
    ) {
        self.loader = loader
    }

    public func preflight(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )
        let decoded = try JSONToolBridge.decode(
            LoadSearchContextToolInput.self,
            from: input
        )
        let request = try request(
            from: decoded
        )

        try loader.validate(
            request
        )

        var targetPaths: [String] = []
        var seen: Set<String> = []

        for candidate in decoded.candidates {
            let authorized = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: decoded.rootID,
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
            summary: "Validate and admit exact source context for \(decoded.candidates.count) search candidate(s).",
            rootIDs: [
                decoded.rootID.rawValue,
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
                "bounded_context_admission",
                "no_file_mutation",
            ]
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )
        let decoded = try JSONToolBridge.decode(
            LoadSearchContextToolInput.self,
            from: input
        )
        let result = try loader.load(
            try request(
                from: decoded
            ),
            workspace: workspace
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
            SourceContextResult.self,
            from: output
        ) else {
            return .none
        }

        return .init(
            projection: .init(
                status: "passed",
                summary: "Loaded \(result.totalLineCount) validated source line(s) across \(result.sourceCount) source(s).",
                facts: [
                    .init(
                        label: "candidates",
                        value: String(
                            result.candidateCount
                        )
                    ),
                    .init(
                        label: "sources",
                        value: String(
                            result.sourceCount
                        )
                    ),
                    .init(
                        label: "lines",
                        value: String(
                            result.totalLineCount
                        )
                    ),
                ]
            )
        )
    }
}

private extension LoadSearchContextTool {
    func request(
        from input: LoadSearchContextToolInput
    ) throws -> SourceContextRequest {
        SourceContextRequest(
            rootID: input.rootID,
            candidates: try input.candidates.map {
                try $0.reference()
            },
            beforeLines: input.beforeLines,
            afterLines: input.afterLines,
            maximumCandidates: input.maximumCandidates,
            maximumLinesPerCandidate: input.maximumLinesPerCandidate,
            maximumTotalLines: input.maximumTotalLines
        )
    }
}
