import Workspace
import Foundation
import Path
import Writers
import FileTypes

public struct FileEditor: Sendable {
    public let workspace: WorkspaceContext

    public init(
        workspace: WorkspaceContext
    ) {
        self.workspace = workspace
    }

    @discardableResult
    public func writeRecorded(
        _ text: String,
        to path: DescendantPath,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        let authorized = try authorizeForIO(
            path,
            capability: .write
        )
        let editResult = try StandardWriter(
            authorized.absoluteURL
        ).editor.edit(
            .replaceEntireFile(
                with: text
            ),
            encoding: options.encoding,
            options: options.write ?? recorder.writeOptions(),
            constraint: .unrestricted,
            context: recorder.writeExecutionContext()
        )

        return try await recorder.record(
            editResult: editResult,
            operationKind: .write_text,
            path: authorized.path,
            context: options.mutation
        )
    }

    @discardableResult
    public func writeRecorded(
        _ text: String,
        to path: StandardPath,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        let authorized = try authorizeForIO(
            path,
            capability: .write
        )
        return try await writeRecordedAuthorized(
            text,
            authorized: authorized,
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func writeRecorded(
        _ text: String,
        to rawPath: String,
        filetype: AnyFileType? = nil,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        let authorized = try authorizeForIO(
            rawPath,
            filetype: filetype,
            capability: .write
        )
        return try await writeRecordedAuthorized(
            text,
            authorized: authorized,
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func editRecorded(
        _ operation: StandardEditOperation,
        at path: DescendantPath,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        try await editRecorded(
            [
                operation
            ],
            at: path,
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func editRecorded(
        _ operation: StandardEditOperation,
        at path: StandardPath,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        try await editRecorded(
            [
                operation
            ],
            at: path,
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func editRecorded(
        _ operation: StandardEditOperation,
        at rawPath: String,
        filetype: AnyFileType? = nil,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        try await editRecorded(
            [
                operation
            ],
            at: rawPath,
            filetype: filetype,
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func editRecorded(
        _ operations: [StandardEditOperation],
        at path: DescendantPath,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        let authorized = try authorizeForIO(
            path,
            capability: .edit
        )
        return try await editRecordedAuthorized(
            operations,
            authorized: authorized,
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func editRecorded(
        _ operations: [StandardEditOperation],
        at path: StandardPath,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        let authorized = try authorizeForIO(
            path,
            capability: .edit
        )
        return try await editRecordedAuthorized(
            operations,
            authorized: authorized,
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func editRecorded(
        _ operations: [StandardEditOperation],
        at rawPath: String,
        filetype: AnyFileType? = nil,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        let authorized = try authorizeForIO(
            rawPath,
            filetype: filetype,
            capability: .edit
        )
        return try await editRecordedAuthorized(
            operations,
            authorized: authorized,
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func write(
        _ text: String,
        to path: DescendantPath,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditResult {
        let authorized = try authorizeForIO(
            path,
            capability: .write
        )
        return try writeAuthorized(
            text,
            authorized: authorized,
            encoding: encoding,
            options: options
        )
    }

    @discardableResult
    public func write(
        _ text: String,
        to path: StandardPath,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditResult {
        let authorized = try authorizeForIO(
            path,
            capability: .write
        )
        return try writeAuthorized(
            text,
            authorized: authorized,
            encoding: encoding,
            options: options
        )
    }

    @discardableResult
    public func write(
        _ text: String,
        to rawPath: String,
        filetype: AnyFileType? = nil,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditResult {
        let authorized = try authorizeForIO(
            rawPath,
            filetype: filetype,
            capability: .write
        )
        return try writeAuthorized(
            text,
            authorized: authorized,
            encoding: encoding,
            options: options
        )
    }

    public func previewWrite(
        _ text: String,
        to path: DescendantPath,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        let authorized = try authorizeForIO(
            path,
            capability: .write
        )
        return try previewWriteAuthorized(
            text,
            authorized: authorized,
            encoding: encoding
        )
    }

    public func previewWrite(
        _ text: String,
        to path: StandardPath,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        let authorized = try authorizeForIO(
            path,
            capability: .write
        )
        return try previewWriteAuthorized(
            text,
            authorized: authorized,
            encoding: encoding
        )
    }

    public func previewWrite(
        _ text: String,
        to rawPath: String,
        filetype: AnyFileType? = nil,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        let authorized = try authorizeForIO(
            rawPath,
            filetype: filetype,
            capability: .write
        )
        return try previewWriteAuthorized(
            text,
            authorized: authorized,
            encoding: encoding
        )
    }

    @discardableResult
    public func edit(
        _ operation: StandardEditOperation,
        at path: DescendantPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditResult {
        try edit(
            [
                operation
            ],
            at: path,
            mode: mode,
            encoding: encoding,
            options: options
        )
    }

    @discardableResult
    public func edit(
        _ operation: StandardEditOperation,
        at path: StandardPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditResult {
        try edit(
            [
                operation
            ],
            at: path,
            mode: mode,
            encoding: encoding,
            options: options
        )
    }

    @discardableResult
    public func edit(
        _ operation: StandardEditOperation,
        at rawPath: String,
        filetype: AnyFileType? = nil,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditResult {
        try edit(
            [
                operation
            ],
            at: rawPath,
            filetype: filetype,
            mode: mode,
            encoding: encoding,
            options: options
        )
    }

    @discardableResult
    public func edit(
        _ operations: [StandardEditOperation],
        at path: DescendantPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
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
            options: options
        )
    }

    @discardableResult
    public func edit(
        _ operations: [StandardEditOperation],
        at path: StandardPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
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
            options: options
        )
    }

    @discardableResult
    public func edit(
        _ operations: [StandardEditOperation],
        at rawPath: String,
        filetype: AnyFileType? = nil,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditResult {
        let authorized = try authorizeForIO(
            rawPath,
            filetype: filetype,
            capability: .edit
        )
        return try editAuthorized(
            operations,
            authorized: authorized,
            mode: mode,
            encoding: encoding,
            options: options
        )
    }

    public func previewEdit(
        _ operation: StandardEditOperation,
        at path: DescendantPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try previewEdit(
            [
                operation
            ],
            at: path,
            mode: mode,
            encoding: encoding
        )
    }

    public func previewEdit(
        _ operation: StandardEditOperation,
        at path: StandardPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try previewEdit(
            [
                operation
            ],
            at: path,
            mode: mode,
            encoding: encoding
        )
    }

    public func previewEdit(
        _ operation: StandardEditOperation,
        at rawPath: String,
        filetype: AnyFileType? = nil,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try previewEdit(
            [
                operation
            ],
            at: rawPath,
            filetype: filetype,
            mode: mode,
            encoding: encoding
        )
    }

    public func previewEdit(
        _ operations: [StandardEditOperation],
        at path: DescendantPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        let authorized = try authorizeForIO(
            path,
            capability: .edit
        )
        return try previewEditAuthorized(
            operations,
            authorized: authorized,
            mode: mode,
            encoding: encoding
        )
    }

    public func previewEdit(
        _ operations: [StandardEditOperation],
        at path: StandardPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        let authorized = try authorizeForIO(
            path,
            capability: .edit
        )
        return try previewEditAuthorized(
            operations,
            authorized: authorized,
            mode: mode,
            encoding: encoding
        )
    }

    public func previewEdit(
        _ operations: [StandardEditOperation],
        at rawPath: String,
        filetype: AnyFileType? = nil,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
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
            encoding: encoding
        )
    }
}

extension FileEditor {
    func authorizeForIO(
        _ path: DescendantPath,
        capability: WorkspaceCapability
    ) throws -> AuthorizedPath {
        let targetURL = path.relative.url(
            base: workspace.absoluteURL
        )
        return try workspace.authorize(
            targetURL.path,
            capability: capability
        ).authorizedPath
    }

    func authorizeForIO(
        _ path: StandardPath,
        capability: WorkspaceCapability
    ) throws -> AuthorizedPath {
        let targetURL = path.url(
            base: workspace.absoluteURL
        )
        return try workspace.authorize(
            targetURL.path,
            capability: capability
        ).authorizedPath
    }

    func authorizeForIO(
        _ rawPath: String,
        filetype _: AnyFileType? = nil,
        capability: WorkspaceCapability
    ) throws -> AuthorizedPath {
        try workspace.authorize(
            rawPath,
            capability: capability
        ).authorizedPath
    }
}

private extension FileEditor {
    func writeRecordedAuthorized(
        _ text: String,
        authorized: AuthorizedPath,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions
    ) async throws -> AgentFileMutationResult {
        let editResult = try StandardWriter(
            authorized.absoluteURL
        ).editor.edit(
            .replaceEntireFile(
                with: text
            ),
            encoding: options.encoding,
            options: options.write ?? recorder.writeOptions(),
            constraint: .unrestricted,
            context: recorder.writeExecutionContext()
        )

        return try await recorder.record(
            editResult: editResult,
            operationKind: .write_text,
            path: authorized.path,
            context: options.mutation
        )
    }

    func editRecordedAuthorized(
        _ operations: [StandardEditOperation],
        authorized: AuthorizedPath,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions
    ) async throws -> AgentFileMutationResult {
        let editResult = try StandardWriter(
            authorized.absoluteURL
        ).editor.edit(
            operations,
            mode: options.mode,
            encoding: options.encoding,
            options: options.write ?? recorder.writeOptions(),
            constraint: .unrestricted,
            context: recorder.writeExecutionContext()
        )

        return try await recorder.record(
            editResult: editResult,
            operationKind: .edit_operations,
            path: authorized.path,
            context: options.mutation
        )
    }

    func writeAuthorized(
        _ text: String,
        authorized: AuthorizedPath,
        encoding: String.Encoding,
        options: SafeWriteOptions
    ) throws -> StandardEditResult {
        try StandardWriter(
            authorized.absoluteURL
        ).editor.edit(
            .replaceEntireFile(
                with: text
            ),
            encoding: encoding,
            options: options
        )
    }

    func previewWriteAuthorized(
        _ text: String,
        authorized: AuthorizedPath,
        encoding: String.Encoding
    ) throws -> StandardEditResult {
        try StandardWriter(
            authorized.absoluteURL
        ).editor.preview(
            .replaceEntireFile(
                with: text
            ),
            encoding: encoding
        )
    }

    func editAuthorized(
        _ operations: [StandardEditOperation],
        authorized: AuthorizedPath,
        mode: StandardEditMode,
        encoding: String.Encoding,
        options: SafeWriteOptions
    ) throws -> StandardEditResult {
        try StandardWriter(
            authorized.absoluteURL
        ).editor.edit(
            operations,
            mode: mode,
            encoding: encoding,
            options: options
        )
    }

    func previewEditAuthorized(
        _ operations: [StandardEditOperation],
        authorized: AuthorizedPath,
        mode: StandardEditMode,
        encoding: String.Encoding
    ) throws -> StandardEditResult {
        try StandardWriter(
            authorized.absoluteURL
        ).editor.preview(
            operations,
            mode: mode,
            encoding: encoding
        )
    }
}
