import Agentic
import Workspace
import Primitives
import Schema
import Macros
import Path


public extension SystemIO.Tools {
    @Tool
    struct InspectWorkspace: Tool {
        /// The workspace's roots and path grants, optionally narrowed to one root.
        @JSONSchema
        public struct Input: HashableSource {
            /// Only this root and its grants. Defaults to every root.
            public let rootID: PathAccessRootIdentifier?
            /// Whether workspace diagnostics are included. Defaults to true.
            public let includeDiagnostics: Bool?
            /// Whether current path grants are included. Defaults to true.
            public let includeGrants: Bool?
            /// Whether expired grants are included. Defaults to false.
            public let includeExpired: Bool?

            public init(
                rootID: PathAccessRootIdentifier? = nil,
                includeDiagnostics: Bool? = nil,
                includeGrants: Bool? = nil,
                includeExpired: Bool? = nil
            ) {
                self.rootID = rootID
                self.includeDiagnostics = includeDiagnostics
                self.includeGrants = includeGrants
                self.includeExpired = includeExpired
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
            in context: CapabilityContext
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
            in context: CapabilityContext
        ) async throws -> Output {

            guard let workspace = context.workspace else {
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
            let roots = WorkspaceToolSupport.rootSummaries(
                workspace: workspace,
                includeDiagnostics: includeDiagnostics
            ).filter { root in
                input.rootID.map { root.rootID == $0.rawValue } ?? true
            }
            let grants = WorkspaceToolSupport.grantSummaries(
                workspace: workspace
            ).filter { summary in
                if let rootID = input.rootID,
                   summary.rootID != rootID.rawValue {
                    return false
                }
                if input.includeExpired != true,
                   summary.status == "expired" {
                    return false
                }
                return true
            }

            return Output(
                hasWorkspace: true,
                defaultRootID: workspace.defaultRootIdentifier?.rawValue,
                rootCount: workspace.roots.count,
                grantCount: workspace.grants.count,
                roots: roots,
                grants: includeGrants
                    ? grants
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
