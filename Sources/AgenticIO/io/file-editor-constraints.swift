import AgenticWorkspace
import Foundation
import Path
import Writers
import FileTypes

extension FileEditor {
    public func previewEdit(
        _ operation: StandardEditOperation,
        at path: DescendantPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try previewEdit(
            [
                operation,
            ],
            at: path,
            mode: mode,
            encoding: encoding,
            constraint: constraint
        )
    }

    public func previewEdit(
        _ operation: StandardEditOperation,
        at path: StandardPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try previewEdit(
            operation,
            at: workspace.resolve(
                path
            ),
            mode: mode,
            encoding: encoding,
            constraint: constraint
        )
    }

    public func previewEdit(
        _ operation: StandardEditOperation,
        at rawPath: String,
        filetype: AnyFileType? = nil,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try previewEdit(
            operation,
            at: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            mode: mode,
            encoding: encoding,
            constraint: constraint
        )
    }

    public func previewEdit(
        _ operations: [StandardEditOperation],
        at path: DescendantPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try StandardWriter(
            workspace.absoluteURL(
                for: path
            )
        ).editor.preview(
            operations,
            mode: mode,
            encoding: encoding,
            constraint: constraint
        )
    }

    public func previewEdit(
        _ operations: [StandardEditOperation],
        at path: StandardPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try previewEdit(
            operations,
            at: workspace.resolve(
                path
            ),
            mode: mode,
            encoding: encoding,
            constraint: constraint
        )
    }

    public func previewEdit(
        _ operations: [StandardEditOperation],
        at rawPath: String,
        filetype: AnyFileType? = nil,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try previewEdit(
            operations,
            at: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            mode: mode,
            encoding: encoding,
            constraint: constraint
        )
    }

    @discardableResult
    public func edit(
        _ operation: StandardEditOperation,
        at path: DescendantPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try edit(
            [
                operation,
            ],
            at: path,
            mode: mode,
            encoding: encoding,
            options: options,
            constraint: constraint
        )
    }

    @discardableResult
    public func edit(
        _ operations: [StandardEditOperation],
        at path: DescendantPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try StandardWriter(
            workspace.absoluteURL(
                for: path
            )
        ).editor.edit(
            operations,
            mode: mode,
            encoding: encoding,
            options: options,
            constraint: constraint
        )
    }

    @discardableResult
    public func editRecorded(
        _ operations: [StandardEditOperation],
        at path: DescendantPath,
        constraint: StandardEditConstraint,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        let editResult = try StandardWriter(
            workspace.absoluteURL(
                for: path
            )
        ).editor.edit(
            operations,
            mode: options.mode,
            encoding: options.encoding,
            options: try options.write ?? recorder.writeOptions(),
            constraint: constraint
        )

        return try await recorder.record(
            editResult: editResult,
            operationKind: .edit_operations,
            path: path,
            context: options.mutation
        )
    }
}
