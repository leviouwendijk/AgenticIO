import Agentic
import Workspace
import Primitives
import Schema
import Macros

/// What io_tool_compose_context does with a plan.
@JSONSchema
public enum ContextComposeMode:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    /// Inspect the plan's sources; sizes are the known ones, nothing is rendered.
    case inspect
    /// Render internally and return only the final size.
    case estimate
    /// Render and return the prompt-ready text.
    case compose
}

private extension SystemIO.Tools.ComposeContext.Input {
    enum CodingKeys: String, CodingKey {
        case plan
        case mode
        case maxCharacters
    }
}

public extension SystemIO.Tools.ComposeContext.Input {
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self.init(
            plan: try container.decode(
                ContextCompositionPlan.self,
                forKey: .plan
            ),
            mode: try container.decodeIfPresent(
                ContextComposeMode.self,
                forKey: .mode
            ) ?? .compose,
            maxCharacters: try container.decodeIfPresent(
                Int.self,
                forKey: .maxCharacters
            )
        )
    }
}

public extension SystemIO.Tools {
    @Tool
    struct ComposeContext: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            public let plan: ContextCompositionPlan

            /// inspect (sources and known sizes), estimate (rendered size only) or compose (the text). Defaults to compose.
            @Schema(required: false)
            public let mode: ContextComposeMode

            /// Maximum characters of composed text. Compose only.
            public let maxCharacters: Int?

            public init(
                plan: ContextCompositionPlan,
                mode: ContextComposeMode = .compose,
                maxCharacters: Int? = nil
            ) {
                self.plan = plan
                self.mode = mode
                self.maxCharacters = maxCharacters
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let mode: ContextComposeMode
            public let metadata: ContextMetadata
            /// The composed text. Compose only.
            public let content: String?
            public let size: ContextSizeEstimate
            public let inspection: ContextPlanInspection
            public let truncated: Bool

            public init(
                mode: ContextComposeMode,
                metadata: ContextMetadata,
                content: String?,
                size: ContextSizeEstimate,
                inspection: ContextPlanInspection,
                truncated: Bool
            ) {
                self.mode = mode
                self.metadata = metadata
                self.content = content
                self.size = size
                self.inspection = inspection
                self.truncated = truncated
            }
        }

        public static let purpose = "Inspect, size or compose a context plan into prompt-ready text using the configured ContextComposer."
        public static let risk: ActionRisk = .observe

        public let composer: ContextComposer

        public init(
            composer: ContextComposer = .init()
        ) {
            self.composer = composer
        }

        public func preflight(
            _ input: Input,
            in context: ToolContext
        ) async throws -> ToolPreflight {
            let renders = input.mode != .inspect

            if renders {
                try composer.validate(
                    input.plan,
                    workspace: context.workspace
                )
            }

            let inspection = ContextToolSupport.inspect(
                input.plan
            )
            let fileSources = renders
                ? ContextToolSupport.fileSources(
                    in: input.plan
                )
                : []

            return .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: summary(
                    inspection: inspection,
                    input: input
                ),
                access: access(
                    for: fileSources
                ),
                estimates: .init(
                    context: .init(
                        bytes: renders && inspection.hasUnknownSizeSources
                            ? nil
                            : inspection.knownCharacterCount,
                        tokens: renders && inspection.hasUnknownSizeSources
                            ? nil
                            : inspection.knownApproximateTokenCount,
                        files: fileSources.isEmpty
                            ? nil
                            : fileSources.count
                    )
                ),
                policyChecks: fileSources.isEmpty
                    ? []
                    : [
                        "workspace_context_required_for_file_sources",
                        "scan_and_read_authority_required"
                    ]
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let inspection = ContextToolSupport.inspect(
                input.plan
            )

            switch input.mode {
            case .inspect:
                return .init(
                    mode: .inspect,
                    metadata: input.plan.metadata,
                    content: nil,
                    size: .init(
                        characterCount: inspection.knownCharacterCount,
                        byteCount: inspection.knownCharacterCount,
                        lineCount: 0,
                        approximateTokenCount: inspection.knownApproximateTokenCount
                    ),
                    inspection: inspection,
                    truncated: false
                )

            case .estimate:
                let composed = try composer.compose(
                    input.plan,
                    workspace: context.workspace
                )

                return .init(
                    mode: .estimate,
                    metadata: input.plan.metadata,
                    content: nil,
                    size: ContextToolSupport.estimate(
                        text: composed.text
                    ),
                    inspection: inspection,
                    truncated: false
                )

            case .compose:
                let composed = try composer.compose(
                    input.plan,
                    workspace: context.workspace
                )
                let trimmed = ContextToolSupport.truncated(
                    composed.text,
                    maxCharacters: input.maxCharacters
                )

                return .init(
                    mode: .compose,
                    metadata: composed.metadata,
                    content: trimmed.text,
                    size: ContextToolSupport.estimate(
                        text: trimmed.text
                    ),
                    inspection: inspection,
                    truncated: trimmed.truncated
                )
            }
        }
    }
}

private extension SystemIO.Tools.ComposeContext {
    func summary(
        inspection: ContextPlanInspection,
        input: Input
    ) -> String {
        switch input.mode {
        case .inspect:
            return "Inspect \(inspection.sourceCount) context source(s) without rendering full content."

        case .estimate:
            return "Compose \(inspection.sourceCount) context source(s) internally to estimate final rendered size."

        case .compose:
            var parts = [
                "Compose \(inspection.sourceCount) context source(s)"
            ]

            if inspection.hasFileBackedSources {
                parts.append(
                    "including file-backed source(s)"
                )
            }

            if let maxCharacters = input.maxCharacters {
                parts.append(
                    "capped at \(maxCharacters) character(s)"
                )
            }

            return parts.joined(separator: ", ")
        }
    }

    func access(
        for fileSources: [ContextFileSource]
    ) -> ToolPreflight.Access {
        guard !fileSources.isEmpty else {
            return .none
        }

        return .init(
            roots: Array(
                Set(
                    fileSources.map {
                        $0.rootID.rawValue
                    }
                )
            ).sorted(),
            capabilities: [
                .scan,
                .read
            ],
            includesHidden: fileSources.contains {
                $0.includeHidden
            },
            followsSymlinks: fileSources.contains {
                $0.followSymlinks
            }
        )
    }
}
