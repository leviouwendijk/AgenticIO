import Agentic
import Workspace
import Primitives
import Schema
import Macros

public extension SystemIO.Tools {
    @Tool
    struct InspectContextSources: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            public let plan: ContextCompositionPlan

            public init(
                plan: ContextCompositionPlan
            ) {
                self.plan = plan
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let metadata: ContextMetadata
            public let inspection: ContextPlanInspection

            public init(
                metadata: ContextMetadata,
                inspection: ContextPlanInspection
            ) {
                self.metadata = metadata
                self.inspection = inspection
            }
        }

        public static let purpose = "Inspect a context plan without rendering full context content."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            workspace _: WorkspaceContext?
        ) async throws -> ToolPreflight {
            let inspection = ContextToolSupport.inspect(
                input.plan
            )

            return .init(
                tool: Self.definition.identifier,
                risk: Self.definition.risk,
                summary: "Inspect \(inspection.sourceCount) context source(s) without rendering full content.",
                estimates: .init(
                    context: .init(
                        bytes: inspection.knownCharacterCount,
                        tokens: inspection.knownApproximateTokenCount
                    )
                )
            )
        }

        public func call(
            _ input: Input,
            workspace _: WorkspaceContext?
        ) async throws -> Output {
            .init(
                metadata: input.plan.metadata,
                inspection: ContextToolSupport.inspect(
                    input.plan
                )
            )
        }
    }
}
