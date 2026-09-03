import Agentic
import AgenticExecution
import AgenticWorkspace
import Difference
import Foundation
import Path
import Primitives
import Schema
import SchemaMacros
import Writers

@JSONSchema
public enum MutateFilesToolEntryKind: String, Sendable, Codable, Hashable, CaseIterable {
    case create_text
    case replace_text
    case edit_text
    case move
    case delete
}

/// One file mutation entry.
/// create_text requires path and content and fails if the file exists.
/// replace_text requires path and content and defaults replacePolicy to upsert.
/// edit_text requires path and operations using the same operation schema as edit_file.
/// move requires path as the source and destination as the destination path.
/// delete requires path and defaults deletePolicy to existing.
@JSONSchema
public struct MutateFilesToolEntry: Sendable, Codable, Hashable {
    /// Mutation kind.
    public let kind: MutateFilesToolEntryKind

    /// Workspace root identifier. Usually use 'project'.
    public let rootID: PathAccessRootIdentifier?

    /// Path relative to the workspace root.
    public let path: String

    /// Text content for create_text or replace_text.
    public let content: String?

    /// Policy for replace_text.
    public let replacePolicy: StandardReplacePolicy?

    /// Policy for delete.
    public let deletePolicy: StandardDeletePolicy?

    /// Structured edit operations for edit_text.
    public let operations: [EditFileToolOperation]?

    /// Destination path for move.
    public let destination: String?

    /// For move, create missing destination parent directories. Defaults to true.
    public let createParentDirectories: Bool?

    public init(
        kind: MutateFilesToolEntryKind,
        rootID: PathAccessRootIdentifier? = nil,
        path: String,
        content: String? = nil,
        replacePolicy: StandardReplacePolicy? = nil,
        deletePolicy: StandardDeletePolicy? = nil,
        operations: [EditFileToolOperation]? = nil,
        destination: String? = nil,
        createParentDirectories: Bool? = nil
    ) {
        self.kind = kind
        self.rootID = rootID
        self.path = path
        self.content = content
        self.replacePolicy = replacePolicy
        self.deletePolicy = deletePolicy
        self.operations = operations
        self.destination = destination
        self.createParentDirectories = createParentDirectories
    }
}

@JSONSchema
public struct MutateFilesToolInput: Sendable, Codable, Hashable {
    /// Brief reason for this coherent mutation pass.
    public let reason: String?

    /// Default workspace root identifier. Usually use 'project'.
    @Schema(required: false)
    public let rootID: PathAccessRootIdentifier

    /// Failure behavior for the pass.
    @Schema(required: false)
    public let failurePolicy: StandardMutationFailurePolicy

    /// Ordered file mutation entries. All entries are planned and applied as one pass.
    public let entries: [MutateFilesToolEntry]

    public init(
        reason: String? = nil,
        rootID: PathAccessRootIdentifier = .project,
        failurePolicy: StandardMutationFailurePolicy = .rollback_applied,
        entries: [MutateFilesToolEntry]
    ) {
        self.reason = reason
        self.rootID = rootID
        self.failurePolicy = failurePolicy
        self.entries = entries
    }
}

private extension MutateFilesToolInput {
    enum CodingKeys: String, CodingKey {
        case reason
        case rootID
        case failurePolicy
        case entries
    }
}

public extension MutateFilesToolInput {
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self.init(
            reason: try container.decodeIfPresent(
                String.self,
                forKey: .reason
            ),
            rootID: try container.decodeIfPresent(
                PathAccessRootIdentifier.self,
                forKey: .rootID
            ) ?? .project,
            failurePolicy: try container.decodeIfPresent(
                StandardMutationFailurePolicy.self,
                forKey: .failurePolicy
            ) ?? .rollback_applied,
            entries: try container.decode(
                [MutateFilesToolEntry].self,
                forKey: .entries
            )
        )
    }
}

public struct MutateFilesToolEntryOutput: Sendable, Codable, Hashable {
    public let index: Int
    public let path: String
    public let target: String
    public let resource: String
    public let delta: String
    public let warnings: [String]
    public let insertions: Int
    public let deletions: Int
    public let changeCount: Int

    public init(
        index: Int,
        path: String,
        target: String,
        resource: String,
        delta: String,
        warnings: [String],
        insertions: Int,
        deletions: Int,
        changeCount: Int
    ) {
        self.index = index
        self.path = path
        self.target = target
        self.resource = resource
        self.delta = delta
        self.warnings = warnings
        self.insertions = insertions
        self.deletions = deletions
        self.changeCount = changeCount
    }
}

public struct MutateFilesToolRecordOutput: Sendable, Codable, Hashable {
    public let id: UUID
    public let target: String
    public let operationKind: String
    public let resource: String
    public let delta: String
    public let rollbackable: Bool

    public init(
        id: UUID,
        target: String,
        operationKind: String,
        resource: String,
        delta: String,
        rollbackable: Bool
    ) {
        self.id = id
        self.target = target
        self.operationKind = operationKind
        self.resource = resource
        self.delta = delta
        self.rollbackable = rollbackable
    }
}

public struct MutateFilesToolOutput: Sendable, Codable, Hashable {
    public let planID: UUID
    public let resultID: UUID
    public let status: String
    public let entryCount: Int
    public let targetCount: Int
    public let creates: Int
    public let updates: Int
    public let deletes: Int
    public let unchanged: Int
    public let appliedEntryIDs: [UUID]
    public let rollbackAvailable: Bool
    public let failureMessage: String?
    public let entries: [MutateFilesToolEntryOutput]
    public let records: [MutateFilesToolRecordOutput]

    public init(
        planID: UUID,
        resultID: UUID,
        status: String,
        entryCount: Int,
        targetCount: Int,
        creates: Int,
        updates: Int,
        deletes: Int,
        unchanged: Int,
        appliedEntryIDs: [UUID],
        rollbackAvailable: Bool,
        failureMessage: String?,
        entries: [MutateFilesToolEntryOutput],
        records: [MutateFilesToolRecordOutput]
    ) {
        self.planID = planID
        self.resultID = resultID
        self.status = status
        self.entryCount = entryCount
        self.targetCount = targetCount
        self.creates = creates
        self.updates = updates
        self.deletes = deletes
        self.unchanged = unchanged
        self.appliedEntryIDs = appliedEntryIDs
        self.rollbackAvailable = rollbackAvailable
        self.failureMessage = failureMessage
        self.entries = entries
        self.records = records
    }
}

public struct MutateFilesTool:
    TypedInstanceAgentTool,
    WorkspaceTargetableTool
{
    public typealias Input = MutateFilesToolInput

    public static let identifier: AgentToolIdentifier = .mutate_files
    public static let description = "Apply one coherent pass of file mutations in the workspace."
    public static let risk: ActionRisk = .boundedmutate

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }


    public var risk: ActionRisk {
        Self.risk
    }

    public let context: AgentFileMutationContext

    public init(
        context: AgentFileMutationContext = .empty
    ) {
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
            MutateFilesToolInput.self,
            from: input
        )
        let authorized = try authorizeEntries(
            decoded,
            workspace: workspace
        )
        let plan = try workspaceWriter(
            workspace
        ).mutations.plan(
            workspaceEntries(
                decoded
            ),
            metadata: mutationMetadata(
                input: decoded,
                context: context
            )
        )

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: workspace.rootURL.path,
            targetPaths: authorized
                .flatMap { $0 }
                .map(\.presentationPath),
            summary: preflightSummary(
                input: decoded,
                plan: plan
            ),
            estimatedWriteCount: plan.entries.count,
            estimatedByteCount: estimatedByteCount(
                input: decoded
            ),
            sideEffects: risk.defaultSideEffects,
            rootIDs: Array(
                Set(
                    authorized
                        .flatMap { $0 }
                        .map {
                            $0.rootID.rawValue
                        }
                )
            ).sorted(),
            capabilitiesRequired: [
                .write
            ],
            estimatedWriteBytes: estimatedByteCount(
                input: decoded
            ),
            estimatedChangedLineCount: estimatedChangedLineCount(
                plan: plan
            ),
            isPreview: true,
            policyChecks: [
                "workspace_required",
                "agentic_path_grants_authorized",
                "workspace_paths_authorized",
                "workspace_mutation_entries_resolved",
                "standard_mutation_plan_created"
            ],
            warnings: plan.entries.flatMap {
                $0.warnings.map(\.rawValue)
            },
            diffPreview: makeDiffPreview(
                plan: plan,
                authorized: authorized
            )
        )
    }

    public func preflight(
        input: JSONValue,
        context toolContext: AgentToolExecutionContext
    ) async throws -> ToolPreflight {
        let decoded = try JSONToolBridge.decode(
            MutateFilesToolInput.self,
            from: input
        )
        let targetedInput = try workspaceTargetedInput(
            decoded,
            context: toolContext
        )

        return try await Self(
            context: mergedMutationContext(
                toolContext: toolContext
            )
        ).preflight(
            input: try JSONToolBridge.encode(
                targetedInput
            ),
            workspace: toolContext.workspace
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
            MutateFilesToolInput.self,
            from: input
        )

        _ = try authorizeEntries(
            decoded,
            workspace: workspace
        )

        let plan = try workspaceWriter(
            workspace
        ).mutations.plan(
            workspaceEntries(
                decoded
            ),
            metadata: mutationMetadata(
                input: decoded,
                context: context
            )
        )

        let result = workspaceWriter(
            workspace
        ).mutations.apply(
            plan,
            options: .init(
                failure: decoded.failurePolicy
            )
        )

        return try JSONToolBridge.encode(
            output(
                plan: plan,
                result: result
            )
        )
    }

    public func call(
        input: JSONValue,
        context toolContext: AgentToolExecutionContext
    ) async throws -> JSONValue {
        let decoded = try JSONToolBridge.decode(
            MutateFilesToolInput.self,
            from: input
        )
        let targetedInput = try workspaceTargetedInput(
            decoded,
            context: toolContext
        )

        return try await Self(
            context: mergedMutationContext(
                toolContext: toolContext
            )
        ).call(
            input: try JSONToolBridge.encode(
                targetedInput
            ),
            workspace: toolContext.workspace
        )
    }

    public func processResult(
        input _: JSONValue,
        output: JSONValue,
        workspace: AgentWorkspace?
    ) -> AgentToolResultProcessing {
        guard let result = try? JSONToolBridge.decode(
            MutateFilesToolOutput.self,
            from: output
        ) else {
            return .none
        }

        let changedEntries = result.entries.filter {
            $0.changeCount > 0
                || $0.resource != "unchanged"
        }

        let rootPath =
            workspace?
                .rootURL
                .standardizedFileURL
                .path

        func displayPath(
            _ path: String
        ) -> String {
            guard path.hasPrefix("/"),
                  let rootPath
            else {
                return path
            }

            let target =
                URL(
                    fileURLWithPath: path
                )
                .standardizedFileURL
                .path

            let prefix =
                rootPath.hasSuffix("/")
                    ? rootPath
                    : rootPath + "/"

            guard target.hasPrefix(prefix) else {
                return path
            }

            return String(
                target.dropFirst(
                    prefix.count
                )
            )
        }

        func detail(
            _ entry: MutateFilesToolEntryOutput
        ) -> String {
            var parts = [
                entry.resource
            ]

            if entry.insertions > 0 {
                parts.append(
                    "+\(entry.insertions)"
                )
            }

            if entry.deletions > 0 {
                parts.append(
                    "-\(entry.deletions)"
                )
            }

            if parts.count == 1,
               entry.changeCount > 0 {
                parts.append(
                    "\(entry.changeCount) changes"
                )
            }

            return parts.joined(
                separator: " · "
            )
        }

        var counts: [String] = []

        if result.creates > 0 {
            counts.append(
                "\(result.creates) created"
            )
        }

        if result.updates > 0 {
            counts.append(
                "\(result.updates) updated"
            )
        }

        if result.deletes > 0 {
            counts.append(
                "\(result.deletes) deleted"
            )
        }

        if result.unchanged > 0 {
            counts.append(
                "\(result.unchanged) unchanged"
            )
        }

        return .init(
            projection: .init(
                status:
                    changedEntries.isEmpty
                        ? "no changes"
                        : result.status,
                summary:
                    counts.isEmpty
                        ? "No files changed."
                        : counts.joined(
                            separator: " · "
                        ),
                facts: changedEntries.map { entry in
                    .init(
                        label: displayPath(
                            entry.path
                        ),
                        value: detail(
                            entry
                        )
                    )
                }
            )
        )
    }
}

private extension MutateFilesTool {
    func workspaceTargetedInput(
        _ input: MutateFilesToolInput,
        context toolContext: AgentToolExecutionContext
    ) throws -> MutateFilesToolInput {
        guard let location = toolContext.workspaceLocation else {
            return input
        }

        let workspace = try FileToolSupport.requireWorkspace(
            toolContext.workspace,
            toolName: name
        )
        let entries = try input.entries.map { entry in
            let rootID = entry.rootID ?? input.rootID
            let path = try workspace.resolve(
                entry.path,
                relativeTo: location,
                rootID: rootID,
                type: .file
            ).presentingRelative(
                filetype: true
            )
            let destination: String?

            if entry.kind == .move {
                destination = try workspace.resolve(
                    entry.requiredDestination(
                        toolName: name
                    ),
                    relativeTo: location,
                    rootID: rootID,
                    type: .file
                ).presentingRelative(
                    filetype: true
                )
            } else {
                destination = entry.destination
            }

            return MutateFilesToolEntry(
                kind: entry.kind,
                rootID: entry.rootID,
                path: path,
                content: entry.content,
                replacePolicy: entry.replacePolicy,
                deletePolicy: entry.deletePolicy,
                operations: entry.operations,
                destination: destination,
                createParentDirectories: entry.createParentDirectories
            )
        }

        return MutateFilesToolInput(
            reason: input.reason,
            rootID: input.rootID,
            failurePolicy: input.failurePolicy,
            entries: entries
        )
    }

    func workspaceWriter(
        _ workspace: AgentWorkspace
    ) -> WorkspaceWriter {
        WorkspaceWriter(
            access: workspace.accessController.paths
        )
    }

    func authorizeEntries(
        _ input: MutateFilesToolInput,
        workspace: AgentWorkspace
    ) throws -> [[AgenticAuthorizedPath]] {
        try input.entries.map { entry in
            let rootID = entry.rootID ?? input.rootID
            let source = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: rootID,
                path: entry.path,
                capability: .write,
                toolName: name,
                type: .file
            )

            guard entry.kind == .move else {
                return [
                    source,
                ]
            }

            let destination = try FileToolAccess.authorize(
                workspace: workspace,
                rootID: rootID,
                path: try entry.requiredDestination(
                    toolName: name
                ),
                capability: .write,
                toolName: name,
                type: .file
            )

            return [
                source,
                destination,
            ]
        }
    }

    func workspaceEntries(
        _ input: MutateFilesToolInput
    ) throws -> [WorkspaceMutationEntry] {
        try input.entries.map { entry in
            try entry.workspaceEntry(
                defaultRootID: input.rootID,
                toolName: name
            )
        }
    }

    func preflightSummary(
        input: MutateFilesToolInput,
        plan: StandardMutationPlan
    ) -> String {
        let reason = input.reason?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let prefix = reason.map {
            $0.isEmpty ? "" : "\($0) "
        } ?? ""

        return "\(prefix)Apply \(plan.entries.count) file mutation(s) across \(plan.report.targetCount) target(s)."
    }

    func estimatedByteCount(
        input: MutateFilesToolInput
    ) -> Int {
        input.entries.reduce(0) { partial, entry in
            partial + (entry.content?.utf8.count ?? 0)
        }
    }

    func estimatedChangedLineCount(
        plan: StandardMutationPlan
    ) -> Int {
        plan.entries.reduce(0) { partial, entry in
            partial + (entry.diff?.changeCount ?? 0)
        }
    }

    func makeDiffPreview(
        plan: StandardMutationPlan,
        authorized: [[AgenticAuthorizedPath]]
    ) -> ToolPreflightDiffPreview {
        let presentationPathsByEntryID: [UUID: String] = Dictionary(
            uniqueKeysWithValues: plan.entries.enumerated().compactMap { pair in
                guard authorized.indices.contains(
                    pair.offset
                ) else {
                    return nil
                }

                return (
                    pair.element.id,
                    authorized[pair.offset].first?.presentationPath
                        ?? pair.element.target.lastPathComponent
                )
            }
        )

        let preview = plan.diffPreview(
            contextLineCount: 3
        ) { entry in
            presentationPathsByEntryID[
                entry.id
            ] ?? entry.target.lastPathComponent
        }

        return .init(
            title: preview.title,
            contextLineCount: preview.contextLineCount,
            text: preview.text,
            layout: preview.layout,
            insertedLineCount: preview.insertedLineCount,
            deletedLineCount: preview.deletedLineCount
        )
    }

    func output(
        plan: StandardMutationPlan,
        result: StandardMutationResult
    ) -> MutateFilesToolOutput {
        MutateFilesToolOutput(
            planID: plan.id,
            resultID: result.id,
            status: result.status.rawValue,
            entryCount: plan.report.entryCount,
            targetCount: plan.report.targetCount,
            creates: plan.report.creates,
            updates: plan.report.updates,
            deletes: plan.report.deletes,
            unchanged: plan.report.unchanged,
            appliedEntryIDs: result.applied,
            rollbackAvailable: result.rollback != nil,
            failureMessage: result.failed?.message,
            entries: plan.entries.enumerated().map { offset, entry in
                entryOutput(
                    entry,
                    authorizedIndex: offset
                )
            },
            records: result.records.map(recordOutput)
        )
    }

    func entryOutput(
        _ entry: StandardPlannedMutation,
        authorizedIndex: Int
    ) -> MutateFilesToolEntryOutput {
        MutateFilesToolEntryOutput(
            index: entry.index,
            path: entry.target.path,
            target: entry.target.path,
            resource: entry.resource.rawValue,
            delta: entry.delta.rawValue,
            warnings: entry.warnings.map(\.rawValue),
            insertions: entry.diff?.insertions ?? 0,
            deletions: entry.diff?.deletions ?? 0,
            changeCount: entry.diff?.changeCount ?? 0
        )
    }

    func recordOutput(
        _ record: WriteMutationRecord
    ) -> MutateFilesToolRecordOutput {
        MutateFilesToolRecordOutput(
            id: record.id,
            target: record.target.path,
            operationKind: record.operationKind.rawValue,
            resource: record.surfacedResourceChangeKind.rawValue,
            delta: record.surfacedDeltaKind.rawValue,
            rollbackable: record.surface.rollback.available
        )
    }

    func mutationMetadata(
        input: MutateFilesToolInput,
        context: AgentFileMutationContext
    ) -> [String: String] {
        var metadata = context.metadata
        metadata["tool_name"] = name
        metadata["intent_action"] = "mutate"
        metadata["intent_action_type"] = "file_mutation_pass"
        metadata["root_id"] = input.rootID.rawValue

        if let reason = input.reason,
           !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["reason"] = reason
        }

        return metadata
    }

    func mergedMutationContext(
        toolContext: AgentToolExecutionContext
    ) -> AgentFileMutationContext {
        if context == .empty {
            return .init(
                toolContext: toolContext,
                additionalMetadata: [
                    "toolName": Self.identifier.rawValue,
                    "intent_action": "mutate",
                    "intent_action_type": "file_mutation_pass"
                ]
            )
        }

        var mutationContext = context

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
        mutationContext.metadata["intent_action"] = "mutate"
        mutationContext.metadata["intent_action_type"] = "file_mutation_pass"
        mutationContext.metadata["execution_mode"] = toolContext.executionMode.rawValue

        return mutationContext
    }
}

private extension MutateFilesToolEntry {
    func workspaceEntry(
        defaultRootID: PathAccessRootIdentifier,
        toolName: String
    ) throws -> WorkspaceMutationEntry {
        let rootID = rootID ?? defaultRootID

        switch kind {
        case .create_text:
            return .createText(
                at: path,
                rootIdentifier: rootID,
                content: try requiredContent(
                    toolName: toolName
                ),
                options: .overwriteWithoutBackup
            )

        case .replace_text:
            return .replaceText(
                at: path,
                rootIdentifier: rootID,
                content: try requiredContent(
                    toolName: toolName
                ),
                policy: replacePolicy ?? .upsert,
                options: .overwriteWithoutBackup
            )

        case .edit_text:
            let operations = try requiredOperations(
                toolName: toolName
            )

            return .editText(
                at: path,
                rootIdentifier: rootID,
                operations: try operations.map {
                    try $0.standardEditOperation()
                },
                mode: EditFileToolInput(
                    rootID: rootID,
                    path: path,
                    operations: operations
                ).resolvedEditMode,
                options: .init(
                    write: .overwriteWithoutBackup
                )
            )

        case .move:
            return .move(
                from: path,
                to: try requiredDestination(
                    toolName: toolName
                ),
                rootIdentifier: rootID,
                createParentDirectories:
                    createParentDirectories ?? true
            )

        case .delete:
            return .delete(
                at: path,
                rootIdentifier: rootID,
                policy: deletePolicy ?? .existing,
                type: .file
            )
        }
    }

    func requiredDestination(
        toolName: String
    ) throws -> String {
        guard let destination,
              !destination.trimmingCharacters(
                    in: .whitespacesAndNewlines
              ).isEmpty
        else {
            throw PredefinedFileToolError.missingField(
                tool: toolName,
                field: "destination"
            )
        }

        return destination
    }

    func requiredContent(
        toolName: String
    ) throws -> String {
        guard let content else {
            throw PredefinedFileToolError.missingField(
                tool: toolName,
                field: "content"
            )
        }

        return content
    }

    func requiredOperations(
        toolName: String
    ) throws -> [EditFileToolOperation] {
        guard let operations else {
            throw PredefinedFileToolError.missingField(
                tool: toolName,
                field: "operations"
            )
        }

        guard !operations.isEmpty else {
            throw PredefinedFileToolError.invalidValue(
                tool: toolName,
                field: "operations",
                reason: "edit_text requires at least one edit operation"
            )
        }

        return operations
    }
}

private extension EditFileToolOperation {
    func standardEditOperation() throws -> StandardEditOperation {
        switch self {
        case .replace_entire_file(let operation):
            return StandardEditOperation.file.replace(
                with: operation.content
            )

        case .append(let operation):
            return StandardEditOperation.text.append(
                operation.content,
                separator: operation.separator
            )

        case .prepend(let operation):
            return StandardEditOperation.text.prepend(
                operation.content,
                separator: operation.separator
            )

        case .replace_first(let operation):
            return StandardEditOperation.text.replaceFirst(
                operation.target,
                with: operation.replacement
            )

        case .replace_all(let operation):
            return StandardEditOperation.text.replaceAll(
                operation.target,
                with: operation.replacement
            )

        case .replace_unique(let operation):
            return StandardEditOperation.text.replaceUnique(
                operation.target,
                with: operation.replacement
            )

        case .replace_line(let operation):
            return StandardEditOperation.line.replace(
                operation.line,
                with: operation.content
            )

        case .insert_lines(let operation):
            return StandardEditOperation.lines.insert(
                operation.lines,
                at: operation.position
            )

        case .replace_lines(let operation):
            return StandardEditOperation.lines.replace(
                try operation.range.lineRange(),
                with: operation.lines
            )

        case .delete_lines(let operation):
            return StandardEditOperation.lines.delete(
                try operation.range.lineRange()
            )
        }
    }
}

private extension Array {
    subscript(
        safe index: Int
    ) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
