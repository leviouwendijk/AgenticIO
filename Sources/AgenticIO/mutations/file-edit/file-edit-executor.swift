import Agentic
import AgenticWorkspace
import Foundation
import Writers

/// Executes one structured file edit request outside the model-facing tool layer.
///
/// Model-facing file mutation goes through `MutateFilesTool`. This executor is
/// for internal single-file workflows such as prepared-intent replay while
/// sharing the same resolver and policy semantics as `mutate_files.edit_text`.
public struct FileEditExecutor: Sendable {
    public static let name = "file_edit_executor"

    public struct Result: Sendable {
        public let edit: StandardEditResult
        public let mutation: AgentFileMutationToolSummary?

        public init(
            edit: StandardEditResult,
            mutation: AgentFileMutationToolSummary? = nil
        ) {
            self.edit = edit
            self.mutation = mutation
        }
    }

    public let recorder: AgentFileMutationRecorder?
    public let context: AgentFileMutationContext
    public let policy: FileEditPolicy

    public init(
        recorder: AgentFileMutationRecorder? = nil,
        context: AgentFileMutationContext = .empty,
        policy: FileEditPolicy = .unrestricted
    ) {
        self.recorder = recorder
        self.context = context
        self.policy = policy
    }

    public func preview(
        _ request: FileEditRequest,
        workspace: AgentWorkspace,
        authorizationToolName: String = MutateFilesTool.identifier.rawValue
    ) throws -> StandardEditResult {
        let resolution = try FileEditResolver(
            toolName: authorizationToolName
        ).resolve(
            request,
            workspace: workspace
        )

        try resolution.requireCurrentSnapshot()

        let constraint = try policy.constraint(
            for: request,
            authorized: resolution.authorized,
            operations: resolution.operations
        )

        return try FileEditor(
            workspace: workspace
        ).previewEdit(
            resolution.operations,
            at: resolution.authorized.path,
            mode: resolution.editMode,
            constraint: constraint
        )
    }

    public func execute(
        _ request: FileEditRequest,
        workspace: AgentWorkspace,
        authorizationToolName: String = MutateFilesTool.identifier.rawValue
    ) async throws -> Result {
        let resolution = try FileEditResolver(
            toolName: authorizationToolName
        ).resolve(
            request,
            workspace: workspace
        )

        try resolution.requireCurrentSnapshot()

        let constraint = try policy.constraint(
            for: request,
            authorized: resolution.authorized,
            operations: resolution.operations
        )
        let editor = FileEditor(
            workspace: workspace
        )

        _ = try editor.previewEdit(
            resolution.operations,
            at: resolution.authorized.path,
            mode: resolution.editMode,
            constraint: constraint
        )

        try resolution.requireCurrentSnapshot()

        var mutationContext = context
        mutationContext.rootID = resolution.authorized.rootID
        mutationContext.metadata["executor"] = Self.name
        mutationContext.metadata["authorization_tool_name"] = authorizationToolName
        mutationContext.metadata["root_id"] = resolution.authorized.rootID.rawValue
        mutationContext.metadata["path"] = resolution.authorized.presentationPath

        if let recorder {
            let recorded = try await editor.editRecorded(
                resolution.operations,
                at: resolution.authorized.path,
                constraint: constraint,
                recorder: recorder,
                options: .init(
                    mode: resolution.editMode,
                    mutation: mutationContext
                )
            )

            guard let edit = recorded.editResult else {
                throw PredefinedFileToolError.invalidValue(
                    tool: Self.name,
                    field: "recorder",
                    reason: "recorded mutation result did not include an edit result"
                )
            }

            return .init(
                edit: edit,
                mutation: .init(
                    result: recorded,
                    policy: recorder.policy
                )
            )
        }

        return .init(
            edit: try editor.edit(
                resolution.operations,
                at: resolution.authorized.path,
                mode: resolution.editMode,
                constraint: constraint
            )
        )
    }
}
