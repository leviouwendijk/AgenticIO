import Agentic
import Workspace
import Primitives
import Schema
import Macros

public extension SystemIO.Tools {
    @Tool
    struct ComposeContext: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            public let plan: ContextCompositionPlan
            public let maxCharacters: Int?

            public init(
                plan: ContextCompositionPlan,
                maxCharacters: Int? = nil
            ) {
                self.plan = plan
                self.maxCharacters = maxCharacters
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let metadata: ContextMetadata
            public let content: String
            public let size: ContextSizeEstimate
            public let inspection: ContextPlanInspection
            public let truncated: Bool

            public init(
                metadata: ContextMetadata,
                content: String,
                size: ContextSizeEstimate,
                inspection: ContextPlanInspection,
                truncated: Bool
            ) {
                self.metadata = metadata
                self.content = content
                self.size = size
                self.inspection = inspection
                self.truncated = truncated
            }
        }

        public static let purpose = "Compose a context plan into prompt-ready text using the configured ContextComposer."
        public static let risk: ActionRisk = .observe

        public let composer: ContextComposer

        public init(
            composer: ContextComposer = .init()
        ) {
            self.composer = composer
        }

        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            try composer.validate(
                input.plan,
                workspace: workspace
            )

            let inspection = ContextToolSupport.inspect(
                input.plan
            )
            let fileSources = ContextToolSupport.fileSources(
                in: input.plan
            )

            return .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: summary(
                    inspection: inspection,
                    maxCharacters: input.maxCharacters
                ),
                access: access(
                    for: fileSources
                ),
                estimates: .init(
                    context: .init(
                        bytes: inspection.hasUnknownSizeSources
                            ? nil
                            : inspection.knownCharacterCount,
                        tokens: inspection.hasUnknownSizeSources
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
            workspace: WorkspaceContext?
        ) async throws -> Output {
            let composed = try composer.compose(
                input.plan,
                workspace: workspace
            )
            let trimmed = ContextToolSupport.truncated(
                composed.text,
                maxCharacters: input.maxCharacters
            )
            let size = ContextToolSupport.estimate(
                text: trimmed.text
            )

            return .init(
                metadata: composed.metadata,
                content: trimmed.text,
                size: size,
                inspection: ContextToolSupport.inspect(
                    input.plan
                ),
                truncated: trimmed.truncated
            )
        }
    }
}

private extension SystemIO.Tools.ComposeContext {
    func summary(
        inspection: ContextPlanInspection,
        maxCharacters: Int?
    ) -> String {
        var parts = [
            "Compose \(inspection.sourceCount) context source(s)"
        ]

        if inspection.hasFileBackedSources {
            parts.append(
                "including file-backed source(s)"
            )
        }

        if let maxCharacters {
            parts.append(
                "capped at \(maxCharacters) character(s)"
            )
        }

        return parts.joined(separator: ", ")
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
