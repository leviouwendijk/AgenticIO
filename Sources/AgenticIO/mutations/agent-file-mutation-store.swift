import Agentic
import Foundation
import Writers

public struct AgentFileMutationQuery: Sendable, Codable, Hashable {
    public var target: URL?
    public var toolCallID: String?
    public var preparedIntentID: PreparedIntentIdentifier?
    public var latestFirst: Bool
    public var limit: Int?

    public init(
        target: URL? = nil,
        toolCallID: String? = nil,
        preparedIntentID: PreparedIntentIdentifier? = nil,
        latestFirst: Bool = true,
        limit: Int? = nil
    ) {
        self.target = target?.standardizedFileURL
        self.toolCallID = toolCallID
        self.preparedIntentID = preparedIntentID
        self.latestFirst = latestFirst
        self.limit = limit
    }

    public static let all = Self()
}

public protocol AgentFileMutationStore: Sendable {
    @discardableResult
    func save(
        _ draft: AgentFileMutationDraft,
        payloadPolicy: WriteMutationPayloadPolicy
    ) async throws -> AgentFileMutationRecord

    func load(
        id: UUID
    ) async throws -> AgentFileMutationRecord?

    func loadWriterRecord(
        for mutation: AgentFileMutationRecord
    ) async throws -> WriteMutationRecord?

    func list(
        _ query: AgentFileMutationQuery
    ) async throws -> [AgentFileMutationRecord]

    func delete(
        id: UUID
    ) async throws
}
