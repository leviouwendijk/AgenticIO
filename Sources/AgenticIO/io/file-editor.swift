import AgenticWorkspace
import Foundation
import Path
import Writers
import FileTypes

public struct FileEditor: Sendable {
    public let workspace: AgentWorkspace

    public init(
        workspace: AgentWorkspace
    ) {
        self.workspace = workspace
    }

    @discardableResult
    public func writeRecorded(
        _ text: String,
        to path: ScopedPath,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        let editResult = try StandardWriter(
            workspace.absoluteURL(
                for: path
            )
        ).editor.edit(
            .replaceEntireFile(
                with: text
            ),
            encoding: options.encoding,
            options: try options.write ?? recorder.writeOptions()
        )

        return try await recorder.record(
            editResult: editResult,
            operationKind: .write_text,
            scopedPath: path,
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
        try await writeRecorded(
            text,
            to: workspace.resolve(
                path
            ),
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
        try await writeRecorded(
            text,
            to: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func editRecorded(
        _ operation: StandardEditOperation,
        at path: ScopedPath,
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
            operation,
            at: workspace.resolve(
                path
            ),
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
            operation,
            at: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func editRecorded(
        _ operations: [StandardEditOperation],
        at path: ScopedPath,
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
            options: try options.write ?? recorder.writeOptions()
        )

        return try await recorder.record(
            editResult: editResult,
            operationKind: .edit_operations,
            scopedPath: path,
            context: options.mutation
        )
    }

    @discardableResult
    public func editRecorded(
        _ operations: [StandardEditOperation],
        at path: StandardPath,
        recorder: AgentFileMutationRecorder,
        options: AgentFileEditOptions = .default
    ) async throws -> AgentFileMutationResult {
        try await editRecorded(
            operations,
            at: workspace.resolve(
                path
            ),
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
        try await editRecorded(
            operations,
            at: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            recorder: recorder,
            options: options
        )
    }

    @discardableResult
    public func write(
        _ text: String,
        to path: ScopedPath,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditResult {
        try StandardWriter(
            workspace.absoluteURL(for: path)
        ).editor.edit(
            .replaceEntireFile(with: text),
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
        try write(
            text,
            to: workspace.resolve(path),
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
        try write(
            text,
            to: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            encoding: encoding,
            options: options
        )
    }

    public func previewWrite(
        _ text: String,
        to path: ScopedPath,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try StandardWriter(
            workspace.absoluteURL(for: path)
        ).editor.preview(
            .replaceEntireFile(with: text),
            encoding: encoding
        )
    }

    public func previewWrite(
        _ text: String,
        to path: StandardPath,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try previewWrite(
            text,
            to: workspace.resolve(path),
            encoding: encoding
        )
    }

    public func previewWrite(
        _ text: String,
        to rawPath: String,
        filetype: AnyFileType? = nil,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try previewWrite(
            text,
            to: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            encoding: encoding
        )
    }

    @discardableResult
    public func edit(
        _ operation: StandardEditOperation,
        at path: ScopedPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditResult {
        try StandardWriter(
            workspace.absoluteURL(for: path)
        ).editor.edit(
            operation,
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
            operation,
            at: workspace.resolve(path),
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
            operation,
            at: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            mode: mode,
            encoding: encoding,
            options: options
        )
    }

    @discardableResult
    public func edit(
        _ operations: [StandardEditOperation],
        at path: ScopedPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) throws -> StandardEditResult {
        try StandardWriter(
            workspace.absoluteURL(for: path)
        ).editor.edit(
            operations,
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
        try edit(
            operations,
            at: workspace.resolve(path),
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
        try edit(
            operations,
            at: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            mode: mode,
            encoding: encoding,
            options: options
        )
    }

    public func previewEdit(
        _ operation: StandardEditOperation,
        at path: ScopedPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try StandardWriter(
            workspace.absoluteURL(for: path)
        ).editor.preview(
            operation,
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
            operation,
            at: workspace.resolve(path),
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
            operation,
            at: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            mode: mode,
            encoding: encoding
        )
    }

    public func previewEdit(
        _ operations: [StandardEditOperation],
        at path: ScopedPath,
        mode: StandardEditMode = .sequential,
        encoding: String.Encoding = .utf8
    ) throws -> StandardEditResult {
        try StandardWriter(
            workspace.absoluteURL(for: path)
        ).editor.preview(
            operations,
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
        try previewEdit(
            operations,
            at: workspace.resolve(path),
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
        try previewEdit(
            operations,
            at: workspace.resolve(
                rawPath,
                filetype: filetype
            ),
            mode: mode,
            encoding: encoding
        )
    }
}
