import Agentic
import AgenticExecution
import Workspace
import Primitives
import Schema
import Macros


public extension SystemIO.Tools {
    @Tool
    struct ListPathRoots: Tool {
        /// Model-facing input for List pathRoots.
        @JSONSchema
        public struct Input: Sendable, Codable, Hashable {
            /// Whether root diagnostics are included.
            public let includeDiagnostics: Bool?

            public init(
                includeDiagnostics: Bool? = nil
            ) {
                self.includeDiagnostics = includeDiagnostics
            }
        }

        public struct Output: Result, Hashable {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let defaultRootID: String?
            public let roots: [WorkspaceRootToolSummary]

            public init(
                defaultRootID: String?,
                roots: [WorkspaceRootToolSummary]
            ) {
                self.defaultRootID = defaultRootID
                self.roots = roots
            }
        }


        public static let purpose = "List named workspace path roots without scanning or reading file contents."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "List workspace path roots.",
                access: .init(
                    capabilities: [
                        .list
                    ]
                ),
                policyChecks: [
                    "no_file_content_access",
                    "root_metadata_only"
                ]
            )
        }

        public func call(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> Output {
            let workspace = try WorkspaceToolSupport.requireWorkspace(
                workspace,
                toolName: Self.identifier.rawValue
            )

            return Output(
                defaultRootID: workspace.defaultRootIdentifier?.rawValue,
                roots: WorkspaceToolSupport.rootSummaries(
                    workspace: workspace,
                    includeDiagnostics: input.includeDiagnostics ?? true
                )
            )
            
        }
    }
}