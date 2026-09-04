import Agentic
import AgenticExecution
import AgenticWorkspace
import Foundation
import Primitives
import Schema
import SchemaMacros

/// Model-facing input for List fileMutations.
@JSONSchema
public struct ListFileMutationsToolInput: Sendable, Codable, Hashable {
    /// Optional workspace path used to filter mutation history.
    public let path: String?
    /// Optional prepared intent identifier used to filter mutation history.
    public let preparedIntentID: String?
    /// Whether to return only rollbackable mutations.
    public let rollbackableOnly: Bool
    /// Whether to include recorded mutations that produced no content change.
    public let includeUnchanged: Bool
    /// Whether to return newest mutations first.
    public let latestFirst: Bool
    /// Optional maximum number of mutation records to return.
    public let limit: Int?

    public init(
        path: String? = nil,
        preparedIntentID: String? = nil,
        rollbackableOnly: Bool = false,
        includeUnchanged: Bool = true,
        latestFirst: Bool = true,
        limit: Int? = nil
    ) {
        self.path = path
        self.preparedIntentID = preparedIntentID
        self.rollbackableOnly = rollbackableOnly
        self.includeUnchanged = includeUnchanged
        self.latestFirst = latestFirst
        self.limit = limit
    }
}

public struct ListFileMutationsTool: AgentTool {
    public typealias Input = ListFileMutationsToolInput
    public typealias Output = AgentFileMutationHistoryList

    public static let identifier: AgentToolIdentifier = .list_file_mutations
    public static let description = "List recorded file mutations for the current Agentic session mutation store."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier {
        Self.identifier
    }

    public var description: String {
        Self.description
    }


    public var risk: ActionRisk {
        Self.risk
    }

    public let store: any AgentFileMutationStore

    public init(
        store: any AgentFileMutationStore
    ) {
        self.store = store
    }

    public func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            summary: summary(
                for: input
            ),
            estimatedRuntimeSeconds: 1,
            sideEffects: []
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {
        let history = AgentFileMutationHistory(
            store: store
        )
        let result = try await history.list(
            .init(
                path: input.normalizedPath,
                preparedIntentID: input.normalizedPreparedIntentID,
                rollbackableOnly: input.rollbackableOnly,
                includeUnchanged: input.includeUnchanged,
                latestFirst: input.latestFirst,
                limit: input.clampedLimit
            )
        )

        return result
        
    }
}

private extension ListFileMutationsTool {
    func summary(
        for input: ListFileMutationsToolInput
    ) -> String {
        var parts = [
            "List recorded file mutations."
        ]

        if let path = input.normalizedPath {
            parts.append(
                "path: \(path)"
            )
        }

        if let preparedIntentID = input.normalizedPreparedIntentID {
            parts.append(
                "preparedIntentID: \(preparedIntentID.rawValue)"
            )
        }

        if input.rollbackableOnly {
            parts.append(
                "rollbackable only"
            )
        }

        if !input.includeUnchanged {
            parts.append(
                "exclude unchanged"
            )
        }

        parts.append(
            "limit: \(input.clampedLimit)"
        )

        return parts.joined(
            separator: "\n"
        )
    }
}

private extension ListFileMutationsToolInput {
    var normalizedPath: String? {
        normalized(
            path
        )
    }

    var normalizedPreparedIntentID: PreparedIntentIdentifier? {
        normalized(
            preparedIntentID
        ).map {
            .init($0)
        }
    }

    var clampedLimit: Int {
        let value = limit ?? 50

        return min(
            max(
                1,
                value
            ),
            200
        )
    }

    func normalized(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? nil : trimmed
    }
}