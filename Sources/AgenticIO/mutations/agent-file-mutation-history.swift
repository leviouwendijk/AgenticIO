import Agentic
import Foundation
import Path
import Writers

public enum AgentFileMutationHistoryError: Error, Sendable, LocalizedError {
    case invalidMutationID(String)
    case mutationNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMutationID(let id):
            return "Invalid file mutation id '\(id)'."

        case .mutationNotFound(let id):
            return "No recorded file mutation exists for id '\(id)'."
        }
    }
}

public struct AgentFileMutationHistoryQuery: Sendable, Codable, Hashable {
    public var path: String?
    public var preparedIntentID: PreparedIntentIdentifier?
    public var rollbackableOnly: Bool
    public var includeUnchanged: Bool
    public var latestFirst: Bool
    public var limit: Int?

    public init(
        path: String? = nil,
        preparedIntentID: PreparedIntentIdentifier? = nil,
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

public struct AgentWriteStoredRecordSummary: Sendable, Codable, Hashable {
    public let id: UUID
    public let kind: WriteStoredRecordKind
    public let targetPath: String
    public let createdAt: Date
    public let storageKind: WriteStorageLocationKind?
    public let storageValue: String?
    public let metadata: [String: String]

    public init(
        id: UUID,
        kind: WriteStoredRecordKind,
        targetPath: String,
        createdAt: Date,
        storageKind: WriteStorageLocationKind?,
        storageValue: String?,
        metadata: [String: String]
    ) {
        self.id = id
        self.kind = kind
        self.targetPath = targetPath
        self.createdAt = createdAt
        self.storageKind = storageKind
        self.storageValue = storageValue
        self.metadata = metadata
    }

    public init(
        _ record: WriteStoredRecord
    ) {
        self.init(
            id: record.id,
            kind: record.kind,
            targetPath: record.target.standardizedFileURL.path,
            createdAt: record.createdAt,
            storageKind: record.storage?.kind,
            storageValue: record.storage?.value,
            metadata: record.metadata
        )
    }
}

public struct AgentFileMutationSummary: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let sessionID: String
    public let toolCallID: String?
    public let preparedIntentID: PreparedIntentIdentifier?
    public let createdAt: Date
    public let rootID: String?
    public let path: String
    public let targetPath: String
    public let operationKind: WriteMutationOperationKind
    public let resource: WriteResourceChangeKind
    public let delta: WriteDeltaKind
    public let rollbackable: Bool
    public let hasChanges: Bool
    public let artifactIDs: [String]
    public let writerRecordID: UUID
    public let writerRecordKind: WriteStoredRecordKind
    public let writerRecordStorageKind: WriteStorageLocationKind?

    public init(
        id: UUID,
        sessionID: String,
        toolCallID: String?,
        preparedIntentID: PreparedIntentIdentifier?,
        createdAt: Date,
        rootID: String?,
        path: String,
        targetPath: String,
        operationKind: WriteMutationOperationKind,
        resource: WriteResourceChangeKind,
        delta: WriteDeltaKind,
        rollbackable: Bool,
        hasChanges: Bool,
        artifactIDs: [String],
        writerRecordID: UUID,
        writerRecordKind: WriteStoredRecordKind,
        writerRecordStorageKind: WriteStorageLocationKind?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.toolCallID = toolCallID
        self.preparedIntentID = preparedIntentID
        self.createdAt = createdAt
        self.rootID = rootID
        self.path = path
        self.targetPath = targetPath
        self.operationKind = operationKind
        self.resource = resource
        self.delta = delta
        self.rollbackable = rollbackable
        self.hasChanges = hasChanges
        self.artifactIDs = artifactIDs
        self.writerRecordID = writerRecordID
        self.writerRecordKind = writerRecordKind
        self.writerRecordStorageKind = writerRecordStorageKind
    }

    public init(
        _ mutation: AgentFileMutationRecord
    ) {
        self.init(
            id: mutation.id,
            sessionID: mutation.sessionID,
            toolCallID: mutation.toolCallID,
            preparedIntentID: mutation.preparedIntentID,
            createdAt: mutation.createdAt,
            rootID: mutation.rootID?.rawValue,
            path: mutation.relativePath ?? mutation.target.lastPathComponent,
            targetPath: mutation.target.standardizedFileURL.path,
            operationKind: mutation.operationKind,
            resource: mutation.resource,
            delta: mutation.delta,
            rollbackable: mutation.rollbackable,
            hasChanges: mutation.hasChanges,
            artifactIDs: mutation.artifactIDs,
            writerRecordID: mutation.writerRecordID,
            writerRecordKind: mutation.writerRecord.kind,
            writerRecordStorageKind: mutation.writerRecord.storage?.kind
        )
    }
}

public struct AgentFileMutationHistoryList: Sendable, Codable, Hashable {
    public let mutations: [AgentFileMutationSummary]
    public let totalCount: Int
    public let returnedCount: Int
    public let truncated: Bool

    public init(
        mutations: [AgentFileMutationSummary],
        totalCount: Int,
        returnedCount: Int,
        truncated: Bool
    ) {
        self.mutations = mutations
        self.totalCount = totalCount
        self.returnedCount = returnedCount
        self.truncated = truncated
    }
}

public struct AgentFileMutationInspection: Sendable, Codable, Hashable {
    public let mutation: AgentFileMutationSummary
    public let metadata: [String: String]
    public let writerRecord: AgentWriteStoredRecordSummary
    public let writerMutationRecord: WriteMutationRecord?
    public let diffArtifactIDs: [String]
    public let diffArtifact: AgentArtifactRecord?

    public init(
        mutation: AgentFileMutationSummary,
        metadata: [String: String],
        writerRecord: AgentWriteStoredRecordSummary,
        writerMutationRecord: WriteMutationRecord?,
        diffArtifactIDs: [String],
        diffArtifact: AgentArtifactRecord?
    ) {
        self.mutation = mutation
        self.metadata = metadata
        self.writerRecord = writerRecord
        self.writerMutationRecord = writerMutationRecord
        self.diffArtifactIDs = diffArtifactIDs
        self.diffArtifact = diffArtifact
    }
}

public struct AgentFileMutationHistory: Sendable {
    public let store: any AgentFileMutationStore
    public let artifactStore: (any AgentArtifactStore)?

    public init(
        store: any AgentFileMutationStore,
        artifactStore: (any AgentArtifactStore)? = nil
    ) {
        self.store = store
        self.artifactStore = artifactStore
    }

    public func list(
        _ query: AgentFileMutationHistoryQuery = .init()
    ) async throws -> AgentFileMutationHistoryList {
        var records = try await store.list(
            .init(
                preparedIntentID: query.preparedIntentID,
                latestFirst: query.latestFirst
            )
        )

        if let path = normalizedPath(
            query.path
        ) {
            records = records.filter {
                $0.matchesPresentationPath(
                    path
                )
            }
        }

        if query.rollbackableOnly {
            records = records.filter(\.rollbackable)
        }

        if !query.includeUnchanged {
            records = records.filter(\.hasChanges)
        }

        let totalCount = records.count
        let limitedRecords: [AgentFileMutationRecord]

        if let limit = query.limit {
            limitedRecords = Array(
                records.prefix(
                    max(
                        0,
                        limit
                    )
                )
            )
        } else {
            limitedRecords = records
        }

        let mutations = limitedRecords.map(
            AgentFileMutationSummary.init
        )

        return .init(
            mutations: mutations,
            totalCount: totalCount,
            returnedCount: mutations.count,
            truncated: mutations.count < totalCount
        )
    }

    public func inspect(
        id: UUID,
        loadDiffArtifact: Bool = true
    ) async throws -> AgentFileMutationInspection {
        guard let record = try await store.load(
            id: id
        ) else {
            throw AgentFileMutationHistoryError.mutationNotFound(
                id.uuidString.lowercased()
            )
        }

        let writerMutationRecord = try await store.loadWriterRecord(
            for: record
        )
        let diffArtifact = loadDiffArtifact
            ? try await loadFirstDiffArtifact(
                ids: record.artifactIDs
            )
            : nil

        return .init(
            mutation: .init(record),
            metadata: record.metadata,
            writerRecord: .init(record.writerRecord),
            writerMutationRecord: writerMutationRecord,
            diffArtifactIDs: record.artifactIDs,
            diffArtifact: diffArtifact
        )
    }

    public func inspect(
        id rawID: String,
        loadDiffArtifact: Bool = true
    ) async throws -> AgentFileMutationInspection {
        let trimmed = rawID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let id = UUID(
            uuidString: trimmed
        ) else {
            throw AgentFileMutationHistoryError.invalidMutationID(
                rawID
            )
        }

        return try await inspect(
            id: id,
            loadDiffArtifact: loadDiffArtifact
        )
    }
}

private extension AgentFileMutationHistory {
    func normalizedPath(
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

    func loadFirstDiffArtifact(
        ids: [String]
    ) async throws -> AgentArtifactRecord? {
        guard let artifactStore else {
            return nil
        }

        for id in ids {
            guard let record = try await artifactStore.load(
                id: id
            ) else {
                continue
            }

            if record.artifact.kind == .diff {
                return record
            }
        }

        return nil
    }
}

private extension AgentFileMutationRecord {
    func matchesPresentationPath(
        _ path: String
    ) -> Bool {
        if relativePath == path {
            return true
        }

        let targetPath = target.standardizedFileURL.path

        if targetPath == path {
            return true
        }

        if targetPath.hasSuffix(
            "/\(path)"
        ) {
            return true
        }

        return target.lastPathComponent == path
    }
}
