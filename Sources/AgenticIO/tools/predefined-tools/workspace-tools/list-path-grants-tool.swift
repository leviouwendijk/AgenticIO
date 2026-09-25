import Agentic
import AgenticExecution
import Workspace
import Foundation
import Primitives
import Schema
import Macros
import Path


public extension SystemIO.Tools {
    @Tool
    struct ListPathGrants: Tool {
        /// Model-facing input for List pathGrants.
        @JSONSchema
        public struct Input: HashableSource {
            /// Optional root identifier used to filter grants.
            public let rootID: PathAccessRootIdentifier?
            /// Whether expired grants are included.
            public let includeExpired: Bool?

            public init(
                rootID: PathAccessRootIdentifier? = nil,
                includeExpired: Bool? = nil
            ) {
                self.rootID = rootID
                self.includeExpired = includeExpired
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let grants: [WorkspaceGrantToolSummary]

            public init(
                grants: [WorkspaceGrantToolSummary]
            ) {
                self.grants = grants
            }
        }


        public static let purpose = "List active workspace path grants and their capabilities."
        public static let risk: ActionRisk = .observe

        public init() {}

        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "List workspace path grants.",
                access: .init(
                    capabilities: [
                        .list
                    ]
                ),
                policyChecks: [
                    "no_file_content_access",
                    "grant_metadata_only"
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
            let grants = workspace.grants.filter { grant in
                if let rootID = input.rootID,
                   grant.rootIdentifier != rootID {
                    return false
                }

                if input.includeExpired != true,
                   let status = workspace.status(of: grant.id),
                   case .expired = status {
                    return false
                }

                return true
            }

            return Output(
                grants: grants.map {
                    WorkspaceGrantToolSummary(
                        grant: $0,
                        status: workspace.status(
                            of: $0.id
                        )
                    )
                }
            )
            
        }
    }
}
