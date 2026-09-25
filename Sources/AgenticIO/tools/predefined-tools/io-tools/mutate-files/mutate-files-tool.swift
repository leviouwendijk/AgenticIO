import Agentic
import AgenticExecution
import Workspace
import Difference
import Foundation
import Path
import Primitives
import Schema
import Macros
import Writers

@JSONSchema
public enum MutateFilesToolEntryKind: String, Sendable, Codable, Hashable, CaseIterable {
    case create_text
    case replace_text
    case edit_text
    case copy
    case move
    case delete
}

/// One file mutation entry.
/// create_text requires path and content and fails if the file exists.
/// replace_text requires path and content and defaults replacePolicy to upsert.
/// edit_text requires path and operations using the shared FileEditOperation schema.
/// copy requires path as the source and destination as the destination path.
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
    public let operations: [FileEditOperation]?

    /// Destination path for copy or move.
    public let destination: String?

    /// For copy or move, create missing destination parent directories. Defaults to true.
    public let createParentDirectories: Bool?

    public init(
        kind: MutateFilesToolEntryKind,
        rootID: PathAccessRootIdentifier? = nil,
        path: String,
        content: String? = nil,
        replacePolicy: StandardReplacePolicy? = nil,
        deletePolicy: StandardDeletePolicy? = nil,
        operations: [FileEditOperation]? = nil,
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


private extension SystemIO.Tools.MutateFiles.Input {
    enum CodingKeys: String, CodingKey {
        case reason
        case rootID
        case failurePolicy
        case entries
    }
}

public extension SystemIO.Tools.MutateFiles.Input {
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


public struct MutateFilesToolPreparation: Sendable {
    public let plan: StandardMutationPlan
    public let preflight: ToolPreflight

    public init(
        plan: StandardMutationPlan,
        preflight: ToolPreflight
    ) {
        self.plan = plan
        self.preflight = preflight
    }
}

public extension SystemIO.Tools {
    @Tool
    struct MutateFiles: Tool {
        @JSONSchema
        public struct Input: HashableSource {
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

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

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


        public static let purpose = "Apply one coherent pass of file mutations in the workspace."
        public static let risk: ActionRisk = .boundedmutate

        public let context: AgentFileMutationContext
        public let fileEditPolicy: FileEditPolicy

        public init(
            context: AgentFileMutationContext = .empty,
            fileEditPolicy: FileEditPolicy = .unrestricted
        ) {
            self.context = context
            self.fileEditPolicy = fileEditPolicy
        }


        private func prepareInternal(
            _ input: Input,
            workspace: WorkspaceContext?,
            writeOptions: SafeWriteOptions = .overwriteWithoutBackup
        ) async throws -> MutateFilesToolPreparation {
            let workspace = try FileToolSupport.requireWorkspace(
                workspace,
                toolName: Self.identifier.rawValue
            )
            let authorized = try authorizeEntries(
                input,
                workspace: workspace
            )
            let plan = try workspaceWriter(
                workspace
            ).mutations.plan(
                workspaceEntries(
                    input,
                    workspace: workspace,
                    writeOptions: writeOptions
                ),
                metadata: mutationMetadata(
                    input: input,
                    context: context
                )
            )
            let preflight = ToolPreflight(
                tool: Self.definition.identifier,
                risk: risk,
                summary: preflightSummary(
                    input: input,
                    plan: plan
                ),
                access: .init(
                    targets: authorized
                        .flatMap { $0 }
                        .map(\.presentationPath),
                    roots: Array(
                        Set(
                            authorized
                                .flatMap { $0 }
                                .map {
                                    $0.rootIdentifier.rawValue
                                }
                        )
                    ).sorted(),
                    capabilities: input.entries.contains {
                        $0.kind == .copy
                    }
                        ? [
                            .read,
                            .write,
                        ]
                        : [
                            .write,
                        ]
                ),
                estimates: .init(
                    write: .init(
                        count: plan.entries.count,
                        bytes: estimatedByteCount(
                            input: input
                        ),
                        changedLines: estimatedChangedLineCount(
                            plan: plan
                        )
                    ),
                    bytes: estimatedByteCount(
                        input: input
                    )
                ),
                preview: .init(
                    difference: makeDiffPreview(
                        plan: plan,
                        authorized: authorized
                    )
                ),
                sideEffects: risk.defaultSideEffects,
                policyChecks: [
                    "workspace_required",
                    "agentic_path_grants_authorized",
                    "workspace_paths_authorized",
                    "workspace_mutation_entries_resolved",
                    "standard_mutation_plan_created"
                ],
                warnings: plan.entries.flatMap {
                    $0.warnings.map(\.rawValue)
                }
            )

            return .init(
                plan: plan,
                preflight: preflight
            )
        }

        private func preflightInternal(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            try await prepareInternal(
                input,
                workspace: workspace
            ).preflight
        }

        public func prepare(
            _ input: Input,
            workspace: WorkspaceContext?,
            writeOptions: SafeWriteOptions = .overwriteWithoutBackup
        ) async throws -> MutateFilesToolPreparation {
            let targetedInput = try workspaceTargetedInput(
                input,
                workspace: workspace
            )

            return try await Self(
                context: mergedMutationContext()
            ).prepareInternal(
                targetedInput,
                workspace: workspace,
                writeOptions: writeOptions
            )
        }

        public func preflight(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> ToolPreflight {
            try await prepare(
                input,
                workspace: workspace
            ).preflight
        }

        private func callInternal(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> Output {
            let workspace = try FileToolSupport.requireWorkspace(
                workspace,
                toolName: Self.identifier.rawValue
            )

            _ = try authorizeEntries(
                input,
                workspace: workspace
            )

            let plan = try workspaceWriter(
                workspace
            ).mutations.plan(
                workspaceEntries(
                    input,
                    workspace: workspace
                ),
                metadata: mutationMetadata(
                    input: input,
                    context: context
                )
            )

            let result = try workspaceWriter(
                workspace
            ).mutations.apply(
                plan,
                options: .init(
                    failure: input.failurePolicy
                )
            )

            return output(
                plan: plan,
                result: result
            )
            
        }

        public func call(
            _ input: Input,
            workspace: WorkspaceContext?
        ) async throws -> Output {
            let targetedInput = try workspaceTargetedInput(
                input,
                workspace: workspace
            )

            return try await Self(
                context: mergedMutationContext()
            ).callInternal(
                targetedInput,
                workspace: workspace
            )
        }

        public func process(
            _ output: Output,
            input _: Input
        ) -> ToolCall.ResultProjection? {
            let result = output

            let changedEntries = result.entries.filter {
                $0.changeCount > 0
                    || $0.resource != "unchanged"
            }

            // Canonical Tool projection is independent of invocation workspace.
            let rootPath: String? = nil

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
        }
    }
}

private extension SystemIO.Tools.MutateFiles {
    func workspaceTargetedInput(
        _ input: SystemIO.Tools.MutateFiles.Input,
        workspace _: WorkspaceContext?
    ) throws -> SystemIO.Tools.MutateFiles.Input {
        input
    }

    func workspaceWriter(
        _ workspace: WorkspaceContext
    ) throws -> WorkspaceWriter {
        try WorkspaceWriter(
            root: workspace.absoluteURL,
            rootIdentifier: workspace.rootIdentifier
        )
    }

    func authorizeEntries(
        _ input: SystemIO.Tools.MutateFiles.Input,
        workspace: WorkspaceContext
    ) throws -> [[AuthorizedPath]] {
        try input.entries.map { entry in
            let rootID = entry.rootID ?? input.rootID

            switch entry.kind {
            case .copy:
                let source = try FileToolAccess.authorize(
                    workspace: workspace,
                    rootID: rootID,
                    path: entry.path,
                    capability: .read,
                    toolName: Self.identifier.rawValue,
                    type: nil
                )
                let destination = try FileToolAccess.authorize(
                    workspace: workspace,
                    rootID: rootID,
                    path: try entry.requiredDestination(
                        toolName: Self.identifier.rawValue
                    ),
                    capability: .write,
                    toolName: Self.identifier.rawValue,
                    type: nil
                )

                return [
                    source,
                    destination,
                ]

            case .move:
                let source = try FileToolAccess.authorize(
                    workspace: workspace,
                    rootID: rootID,
                    path: entry.path,
                    capability: .write,
                    toolName: Self.identifier.rawValue,
                    type: nil
                )
                let destination = try FileToolAccess.authorize(
                    workspace: workspace,
                    rootID: rootID,
                    path: try entry.requiredDestination(
                        toolName: Self.identifier.rawValue
                    ),
                    capability: .write,
                    toolName: Self.identifier.rawValue,
                    type: nil
                )

                return [
                    source,
                    destination,
                ]

            case .create_text,
                 .replace_text,
                 .edit_text,
                 .delete:
                let source = try FileToolAccess.authorize(
                    workspace: workspace,
                    rootID: rootID,
                    path: entry.path,
                    capability: .write,
                    toolName: Self.identifier.rawValue,
                    type: .file
                )

                return [
                    source,
                ]
            }
        }
    }

    func workspaceEntries(
        _ input: SystemIO.Tools.MutateFiles.Input,
        workspace: WorkspaceContext,
        writeOptions: SafeWriteOptions = .overwriteWithoutBackup
    ) throws -> [WorkspaceMutationEntry] {
        try input.entries.map { entry in
            try entry.workspaceEntry(
                defaultRootID: input.rootID,
                toolName: Self.identifier.rawValue,
                workspace: workspace,
                fileEditPolicy: fileEditPolicy,
                writeOptions: writeOptions
            )
        }
    }

    func preflightSummary(
        input: SystemIO.Tools.MutateFiles.Input,
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
        input: SystemIO.Tools.MutateFiles.Input
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
        authorized: [[AuthorizedPath]]
    ) -> ToolPreflight.Preview.Difference? {
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

        guard let layout = preview.layout else {
            return nil
        }

        return .init(
            title: preview.title,
            layout: layout
        )
    }

    func output(
        plan: StandardMutationPlan,
        result: StandardMutationResult
    ) -> SystemIO.Tools.MutateFiles.Output {
        SystemIO.Tools.MutateFiles.Output(
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
        input: SystemIO.Tools.MutateFiles.Input,
        context: AgentFileMutationContext
    ) -> [String: String] {
        var metadata = context.metadata
        metadata["tool_name"] = Self.identifier.rawValue
        metadata["intent_action"] = "mutate"
        metadata["intent_action_type"] = "file_mutation_pass"
        metadata["root_id"] = input.rootID.rawValue

        if let reason = input.reason,
           !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["reason"] = reason
        }

        return metadata
    }

    func mergedMutationContext() -> AgentFileMutationContext {
        var mutationContext = context
        mutationContext.metadata["toolName"] = Self.identifier.rawValue
        mutationContext.metadata["intent_action"] = "mutate"
        mutationContext.metadata["intent_action_type"] = "file_mutation_pass"
        return mutationContext
    }
}

private extension MutateFilesToolEntry {
    func workspaceEntry(
        defaultRootID: PathAccessRootIdentifier,
        toolName: String,
        workspace: WorkspaceContext,
        fileEditPolicy: FileEditPolicy,
        writeOptions: SafeWriteOptions
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
                options: writeOptions
            )

        case .replace_text:
            return .replaceText(
                at: path,
                rootIdentifier: rootID,
                content: try requiredContent(
                    toolName: toolName
                ),
                policy: replacePolicy ?? .upsert,
                options: writeOptions
            )

        case .edit_text:
            let input = FileEditRequest(
                rootID: rootID,
                path: path,
                operations: try requiredOperations(
                    toolName: toolName
                )
            )
            let resolved = try FileEditResolver(
                toolName: toolName
            ).resolve(
                input,
                workspace: workspace
            )

            let constraint = try fileEditPolicy.constraint(
                for: input,
                authorized: resolved.authorized,
                operations: resolved.operations
            )

            return .editText(
                at: path,
                rootIdentifier: rootID,
                operations: resolved.operations,
                mode: resolved.editMode,
                constraint: constraint,
                options: .init(
                    write: writeOptions
                )
            )

        case .copy:
            return .copy(
                from: path,
                to: try requiredDestination(
                    toolName: toolName
                ),
                rootIdentifier: rootID,
                createParentDirectories:
                    createParentDirectories ?? true
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
    ) throws -> [FileEditOperation] {
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
