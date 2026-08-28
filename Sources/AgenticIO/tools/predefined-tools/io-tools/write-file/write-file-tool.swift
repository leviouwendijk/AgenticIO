import Agentic
import AgenticExecution
import AgenticWorkspace
import Difference
import Foundation
import Primitives
import Writers

public struct WriteFileTool: AgentTool {
    public static let identifier: AgentToolIdentifier = "write_file"
    public static let description = "Replace the entire contents of a file in the workspace."
    public static let risk: ActionRisk = .boundedmutate

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }

    public var inputSchema: JSONValue? {
        nil
    }

    public var risk: ActionRisk {
        Self.risk
    }

    public let recorder: AgentFileMutationRecorder?
    public let context: AgentFileMutationContext

    public init(
        recorder: AgentFileMutationRecorder? = nil,
        context: AgentFileMutationContext = .empty
    ) {
        self.recorder = recorder
        self.context = context
    }

    public func preflight(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> ToolPreflight {
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )

        let decoded = try JSONToolBridge.decode(
            WriteFileToolInput.self,
            from: input
        )

        let authorized = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: decoded.rootID,
            path: decoded.path,
            capability: .write,
            toolName: name,
            type: .file
        )

        let byteCount = decoded.content.utf8.count
        let diffPreview = makeDiffPreview(
            authorized: authorized,
            replacement: decoded.content,
            contextLineCount: 3
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace.rootURL.path,
            targetPaths: [
                authorized.presentationPath
            ],
            summary: "Replace entire file contents at \(authorized.presentationPath)",
            estimatedWriteCount: 1,
            estimatedByteCount: byteCount,
            sideEffects: risk.defaultSideEffects,
            rootIDs: [
                decoded.rootID.rawValue
            ],
            capabilitiesRequired: [
                .write
            ],
            estimatedWriteBytes: byteCount,
            estimatedChangedLineCount: diffPreview.changedLineCount,
            isPreview: true,
            policyChecks: [
                "workspace_required",
                "root_path_authorized",
                "write_budget_estimated",
                "difference_preview_generated"
            ],
            diffPreview: diffPreview
        )
    }

    public func call(
        input: JSONValue,
        workspace: AgentWorkspace?
    ) async throws -> JSONValue {
        let workspace = try FileToolSupport.requireWorkspace(
            workspace,
            toolName: name
        )

        let decoded = try JSONToolBridge.decode(
            WriteFileToolInput.self,
            from: input
        )

        let authorized = try FileToolAccess.authorize(
            workspace: workspace,
            rootID: decoded.rootID,
            path: decoded.path,
            capability: .write,
            toolName: name,
            type: .file
        )

        let editor = FileEditor(
            workspace: workspace
        )

        let mutationContext = AgentFileMutationContext(
            rootID: authorized.rootID,
            toolCallID: context.toolCallID,
            preparedIntentID: context.preparedIntentID,
            metadata: mutationMetadata(
                authorized: authorized,
                context: context
            )
        )

        let write: (result: StandardEditResult, mutation: AgentFileMutationToolSummary?)

        if let recorder {
            let recorded = try await editor.writeRecorded(
                decoded.content,
                to: authorized.path,
                recorder: recorder,
                options: .init(
                    mutation: mutationContext
                )
            )

            write = (
                try editResult(
                    from: recorded
                ),
                .init(
                    result: recorded,
                    policy: recorder.policy
                )
            )
        } else {
            write = (
                try editor.write(
                    decoded.content,
                    to: authorized.path
                ),
                nil
            )
        }

        return try JSONToolBridge.encode(
            WriteFileToolOutput(
                rootID: authorized.rootID.rawValue,
                path: authorized.presentationPath,
                bytesWritten: write.result.writeResult?.bytesWritten ?? 0,
                diffSummary: .init(
                    insertedLineCount: write.result.insertions,
                    deletedLineCount: write.result.deletions
                ),
                changeCount: write.result.changeCount,
                originalChangedLineRanges: write.result.originalChangedLineRanges,
                editedChangedLineRanges: write.result.editedChangedLineRanges,
                mutation: write.mutation
            )
        )
    }

    public func call(
        input: JSONValue,
        context: AgentToolExecutionContext
    ) async throws -> JSONValue {
        let decoded = try JSONToolBridge.decode(
            WriteFileToolInput.self,
            from: input
        )

        return try await call(
            decoded,
            context: context
        )
    }

    public func call(
        _ input: WriteFileToolInput,
        context: AgentToolExecutionContext
    ) async throws -> JSONValue {
        let tool = Self(
            recorder: recorder,
            context: mergedMutationContext(
                toolContext: context,
                action: "write"
            )
        )

        return try await tool.call(
            input: try JSONToolBridge.encode(
                input
            ),
            workspace: context.workspace
        )
    }

    private func mergedMutationContext(
        toolContext: AgentToolExecutionContext,
        action: String
    ) -> AgentFileMutationContext {
        if self.context == .empty {
            return .init(
                toolContext: toolContext,
                additionalMetadata: [
                    "toolName": Self.identifier.rawValue,
                    "intent_action": action,
                    "intent_action_type": FileMutationIntentAction.write.actionType
                ]
            )
        }

        var mutationContext = self.context

        if mutationContext.toolCallID == nil {
            mutationContext.toolCallID = toolContext.toolCallID
        }

        if mutationContext.preparedIntentID == nil {
            mutationContext.preparedIntentID = toolContext.preparedIntentID
        }

        mutationContext.metadata.merge(
            toolContext.metadata
        ) { old, _ in
            old
        }

        mutationContext.metadata["toolName"] = Self.identifier.rawValue
        mutationContext.metadata["intent_action"] = action
        mutationContext.metadata["intent_action_type"] = FileMutationIntentAction.write.actionType
        mutationContext.metadata["execution_mode"] = toolContext.executionMode.rawValue

        return mutationContext
    }
}

private extension WriteFileTool {
    func makeDiffPreview(
        authorized: AgenticAuthorizedPath,
        replacement: String,
        contextLineCount: Int
    ) -> ToolPreflightDiffPreview {
        let original = readExistingText(
            at: authorized.absoluteURL
        )

        let difference = TextDiffer.diff(
            old: original,
            new: replacement,
            oldName: "a/\(authorized.presentationPath)",
            newName: "b/\(authorized.presentationPath)"
        )

        let options = DifferenceRenderOptions(
            showHeader: true,
            showUnchangedLines: false,
            contextLineCount: contextLineCount
        )

        let layout = DifferenceRenderer.layout(
            difference,
            options: options
        )

        let rendered = difference.hasChanges
            ? DifferenceRenderer.render(
                layout,
                options: options
            )
            : """
            --- a/\(authorized.presentationPath)
            +++ b/\(authorized.presentationPath)
            # no textual changes
            """

        return .init(
            title: "Preview diff for \(authorized.presentationPath)",
            contextLineCount: contextLineCount,
            text: rendered,
            layout: layout,
            insertedLineCount: difference.insertions,
            deletedLineCount: difference.deletions
        )
    }

    func readExistingText(
        at url: URL
    ) -> String {
        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return ""
        }

        return (
            try? String(
                contentsOf: url,
                encoding: .utf8
            )
        ) ?? ""
    }

    func mutationMetadata(
        authorized: AgenticAuthorizedPath,
        context: AgentFileMutationContext
    ) -> [String: String] {
        var metadata = [
            "tool_name": name,
            "root_id": authorized.rootID.rawValue,
            "path": authorized.presentationPath
        ]

        for (key, value) in context.metadata {
            metadata[key] = value
        }

        return metadata
    }

    func editResult(
        from result: AgentFileMutationResult
    ) throws -> StandardEditResult {
        guard let editResult = result.editResult else {
            throw PredefinedFileToolError.invalidValue(
                tool: name,
                field: "recorder",
                reason: "recorded mutation result did not include an edit result"
            )
        }

        return editResult
    }
}
