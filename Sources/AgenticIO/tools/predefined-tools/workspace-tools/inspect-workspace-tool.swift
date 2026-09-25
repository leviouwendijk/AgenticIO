import Agentic
import AgenticExecution
import Workspace
import Primitives
import Schema
import Macros


public extension SystemIO.Tools {
    @Tool
    struct InspectWorkspace: Tool {
        /// Model-facing input for InspectWorkspace.
        @JSONSchema
        public struct Input: HashableSource {
            /// Whether workspace diagnostics are included.
            public let includeDiagnostics: Bool?
            /// Whether current path grants are included.
            public let includeGrants: Bool?

            public init(
                includeDiagnostics: Bool? = nil,
                includeGrants: Bool? = nil
            ) {
                self.includeDiagnostics = includeDiagnostics
                self.includeGrants = includeGrants
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let hasWorkspace: Bool
            public let defaultRootID: String?
            public let rootCount: Int
            public let grantCount: Int
            public let roots: [WorkspaceRootToolSummary]
            public let grants: [WorkspaceGrantToolSummary]
            public let diagnostics: [String]

            public init(
                hasWorkspace: Bool,
                defaultRootID: String?,
                rootCount: Int,
                grantCount: Int,
                roots: [WorkspaceRootToolSummary],
                grants: [WorkspaceGrantToolSummary],
                diagnostics: [String]
            ) {
                self.hasWorkspace = hasWorkspace
                self.defaultRootID = defaultRootID
                self.rootCount = rootCount
                self.grantCount = grantCount
                self.roots = roots
                self.grants = grants
                self.diagnostics = diagnostics
            }
        }


        public static let purpose = "Inspect attached workspace roots, grants, and diagnostics without reading file contents."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "Inspect workspace roots, grants, and diagnostics.",
                access: .init(
                    capabilities: [
                        .list
                    ]
                ),
                policyChecks: [
                    "no_file_content_access",
                    "workspace_metadata_only"
                ]
            )
        }

        public func call(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> Output {

            guard let workspace = workspace else {
                return Output(
                    hasWorkspace: false,
                    defaultRootID: nil,
                    rootCount: 0,
                    grantCount: 0,
                    roots: [],
                    grants: [],
                    diagnostics: [
                        "No WorkspaceContext is attached."
                    ]
                )
                
            }

            let includeDiagnostics = input.includeDiagnostics ?? true
            let includeGrants = input.includeGrants ?? true

            return Output(
                hasWorkspace: true,
                defaultRootID: workspace.defaultRootIdentifier?.rawValue,
                rootCount: workspace.roots.count,
                grantCount: workspace.grants.count,
                roots: WorkspaceToolSupport.rootSummaries(
                    workspace: workspace,
                    includeDiagnostics: includeDiagnostics
                ),
                grants: includeGrants
                    ? WorkspaceToolSupport.grantSummaries(
                        workspace: workspace
                    )
                    : [],
                diagnostics: includeDiagnostics
                    ? WorkspaceToolSupport.diagnostics(
                        workspace: workspace
                    )
                    : []
            )
            
        }
    }
}
