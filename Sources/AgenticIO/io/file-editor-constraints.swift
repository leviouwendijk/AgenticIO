import Workspace
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
        at rawPath: String,
        filetype: AnyFileType? = nil,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try previewEdit(
            [
                operation,
            ],
            at: rawPath,
            filetype: filetype,
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
        let authorized = try authorizeForIO(
            path,
            capability: .edit
        )
        return try previewEditAuthorized(
            operations,
            authorized: authorized,
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
        let authorized = try authorizeForIO(
            path,
            capability: .edit
        )
        return try previewEditAuthorized(
            operations,
            authorized: authorized,
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
        let authorized = try authorizeForIO(
            rawPath,
            filetype: filetype,
            capability: .edit
        )
        return try previewEditAuthorized(
            operations,
            authorized: authorized,
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
        let authorized = try authorizeForIO(
            path,
            capability: .edit
        )
        return try editAuthorized(
            operations,
            authorized: authorized,
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
        let authorized = try authorizeForIO(
            path,
            capability: .edit
        )
        let editResult = try StandardWriter(
            authorized.absoluteURL
        ).editor.edit(
            operations,
            mode: options.mode,
            encoding: options.encoding,
            options: options.write ?? recorder.writeOptions(),
            constraint: constraint,
            context: recorder.writeExecutionContext()
        )

        return try await recorder.record(
            editResult: editResult,
            operationKind: .edit_operations,
            path: authorized.path,
            context: options.mutation
        )
    }
}

private extension FileEditor {
    func previewEditAuthorized(
        _ operations: [StandardEditOperation],
        authorized: AuthorizedPath,
        mode: StandardEditMode,
        encoding: String.Encoding,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try StandardWriter(
            authorized.absoluteURL
        ).editor.preview(
            operations,
            mode: mode,
            encoding: encoding,
            constraint: constraint
        )
    }

    func editAuthorized(
        _ operations: [StandardEditOperation],
        authorized: AuthorizedPath,
        mode: StandardEditMode,
        encoding: String.Encoding,
        options: SafeWriteOptions,
        constraint: StandardEditConstraint
    ) throws -> StandardEditResult {
        try StandardWriter(
            authorized.absoluteURL
        ).editor.edit(
            operations,
            mode: mode,
            encoding: encoding,
            options: options,
            constraint: constraint
        )
    }
}
