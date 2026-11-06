import Agentic
import AgenticStandard
import Macros
import Schema

public extension SystemIO.Agents {
    @Agent
    enum DirectoryOrganizer {
        @JSONSchema
        public struct Input: HashableSource {
            public let objective: String
            public let path: String
            public let desiredStructure: String?
            public let constraints: [String]
            public let applyChanges: Bool

            public init(
                objective: String,
                path: String,
                desiredStructure: String? = nil,
                constraints: [String] = [],
                applyChanges: Bool = false
            ) {
                self.objective = objective
                self.path = path
                self.desiredStructure = desiredStructure
                self.constraints = constraints
                self.applyChanges = applyChanges
            }
        }

        @JSONSchema
        public struct Output: HashableResult {
            public let summary: String
            public let proposedMoves: [SystemIO.DirectoryMove]
            public let appliedMoves: [SystemIO.DirectoryMove]
            public let unresolved: [String]
            public let verification: [String]

            public init(
                summary: String,
                proposedMoves: [SystemIO.DirectoryMove] = [],
                appliedMoves: [SystemIO.DirectoryMove] = [],
                unresolved: [String] = [],
                verification: [String] = []
            ) {
                self.summary = summary
                self.proposedMoves = proposedMoves
                self.appliedMoves = appliedMoves
                self.unresolved = unresolved
                self.verification = verification
            }
        }

        public static let purpose = """
        Analyze and reorganize authorized directory trees using reviewable, loss-preserving relocations.
        """

        public static let instructions = """
        Work only within the authorized workspace and the requested directory scope.
        Inspect the current tree before choosing an organizational scheme. Prefer
        path and filename evidence; read file contents only to resolve material ambiguity.

        Treat the requested organization as task input, not a built-in convention.
        Do not assume a particular project, business, period, source type, or folder layout.
        When several plausible layouts would materially differ, report the alternatives
        or request clarification rather than inventing a taxonomy.

        Produce an explicit source-to-destination move plan before applying changes.
        Preserve all data and file identity. Treat package or bundle directories as
        complete resources unless the request explicitly calls for their inspection.
        Account for hidden entries, symlinks, duplicate names, destination collisions,
        ancestor/descendant moves, and move ordering. Never silently overwrite.

        If applyChanges is false, stop at a proposed plan. If true, use the installed
        mutate_files tool with move entries, coherent bounded passes, and normal
        host-governed preflight and approval. Do not bypass denial or approval by
        using other tools. Do not edit contents, rename for aesthetics, delete files,
        or remove nonempty directories without explicit task authorization.

        When filename normalization is explicitly requested, use the installed
        convert_case tool for deterministic casing instead of improvising the
        conversion. Pass the filename stem or an individual directory-name
        segment, never a complete filesystem path. Preserve existing filename
        extensions, hidden-file semantics, and unrelated path segments. Reject
        any candidate filename segment containing a path separator. Treat the
        converted text as a proposed destination, not as permission to rename.
        Apply authorized renames only through reviewed mutate_files move entries,
        with normal destination collision and path authorization checks.

        After an applied pass, rescan the affected locations. Verify that each expected
        destination exists and each moved source is absent, and distinguish verified
        outcomes from unverified assumptions. Report all skipped paths, collisions,
        failures, and remaining work; never claim success from intention alone.
        """

        public static let capabilities = AgentCapabilities(
            available: .init(
                tools: .init(
                    members: [
                        SystemIO.Tools.ScanFilepaths.identifier,
                        SystemIO.Tools.SearchFilepaths.identifier,
                        SystemIO.Tools.ReadFile.identifier,
                        SystemIO.Tools.MutateFiles.identifier,
                        Standard.Tools.ConvertCase.identifier,
                    ]
                ),
                inferences: .init(
                    members: [
                        SystemIO.Inferences.PlanDirectoryOrganization.definition.identifier,
                    ]
                )
            ),
            visible: .init(
                tools: .init(
                    members: [
                        SystemIO.Tools.ScanFilepaths.identifier,
                        SystemIO.Tools.SearchFilepaths.identifier,
                        SystemIO.Tools.ReadFile.identifier,
                        SystemIO.Tools.MutateFiles.identifier,
                        Standard.Tools.ConvertCase.identifier,
                    ]
                )
            )
        )
    }
}
