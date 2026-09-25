import Agentic
import Workspace
import Primitives
import Schema
import Macros

public extension SystemIO.Tools {
    @Tool
    struct EstimateContextSize: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            public let plan: ContextCompositionPlan
            public let compose: Bool?

            public init(
                plan: ContextCompositionPlan,
                compose: Bool? = nil
            ) {
                self.plan = plan
                self.compose = compose
            }

            public var shouldCompose: Bool {
                compose ?? true
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let metadata: ContextMetadata
            public let inspection: ContextPlanInspection
            public let size: ContextSizeEstimate?
            public let composed: Bool

            public init(
                metadata: ContextMetadata,
                inspection: ContextPlanInspection,
                size: ContextSizeEstimate?,
                composed: Bool
            ) {
                self.metadata = metadata
                self.inspection = inspection
                self.size = size
                self.composed = composed
            }
        }

        public static let purpose = "Estimate context size and approximate token count for a context plan."
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
            if input.shouldCompose {
                try composer.validate(
                    input.plan,
                    workspace: workspace
                )
            }

            let inspection = ContextToolSupport.inspect(
                input.plan
            )
            let fileSources = input.shouldCompose
                ? ContextToolSupport.fileSources(
                    in: input.plan
                )
                : []

            return .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: input.shouldCompose
                    ? "Compose context internally to estimate final rendered size."
                    : "Estimate known context source sizes without rendering file-backed content.",
                access: access(
                    for: fileSources
                ),
                estimates: .init(
                    context: .init(
                        bytes: input.shouldCompose && inspection.hasUnknownSizeSources
                            ? nil
                            : inspection.knownCharacterCount,
                        tokens: input.shouldCompose && inspection.hasUnknownSizeSources
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
            let inspection = ContextToolSupport.inspect(
                input.plan
            )

            let size: ContextSizeEstimate?
            if input.shouldCompose {
                let composed = try composer.compose(
                    input.plan,
                    workspace: workspace
                )

                size = ContextToolSupport.estimate(
                    text: composed.text
                )
            } else {
                size = .init(
                    characterCount: inspection.knownCharacterCount,
                    byteCount: inspection.knownCharacterCount,
                    lineCount: 0,
                    approximateTokenCount: inspection.knownApproximateTokenCount
                )
            }

            return .init(
                metadata: input.plan.metadata,
                inspection: inspection,
                size: size,
                composed: input.shouldCompose
            )
        }
    }
}

private extension SystemIO.Tools.EstimateContextSize {
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
