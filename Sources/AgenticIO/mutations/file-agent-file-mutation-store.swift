import Foundation
import Writers

public actor FileAgentFileMutationStore: AgentFileMutationStore {
    public let sessionID: String
    public let mutationdir: URL

    public init(
        sessionID: String,
        mutationdir: URL
    ) {
        self.sessionID = sessionID
        self.mutationdir = mutationdir.standardizedFileURL
    }

    @discardableResult
    public func save(
        _ draft: AgentFileMutationDraft,
        payloadPolicy: WriteMutationPayloadPolicy = .external_content
    ) async throws -> AgentFileMutationRecord {
        try createDirs()

        let storedWriterRecord = try writerStore.store(
            draft.writerRecord,
            payloadPolicy: payloadPolicy
        )

        let record = AgentFileMutationRecord(
            id: draft.id,
            sessionID: draft.sessionID,
            toolCallID: draft.toolCallID,
            preparedIntentID: draft.preparedIntentID,
            createdAt: draft.createdAt,
            rootID: draft.rootID,
            scopedPath: draft.scopedPath,
            writerRecord: storedWriterRecord,
            operationKind: draft.writerRecord.operationKind,
            resource: draft.writerRecord.surface.resource,
            delta: draft.writerRecord.surface.delta,
            rollbackable: draft.writerRecord.surface.rollback.available,
            artifactIDs: draft.artifactIDs,
            metadata: draft.metadata
        )

        let data = try encoder.encode(
            record
        )

        try data.write(
            to: recordfile(
                id: record.id
            ),
            options: .atomic
        )

        return record
    }

    public func load(
        id: UUID
    ) async throws -> AgentFileMutationRecord? {
        let url = recordfile(
            id: id
        )

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return nil
        }

        let data = try Data(
            contentsOf: url
        )

        guard !data.isEmpty else {
            return nil
        }

        return try decoder.decode(
            AgentFileMutationRecord.self,
            from: data
        )
    }

    public func loadWriterRecord(
        for mutation: AgentFileMutationRecord
    ) async throws -> WriteMutationRecord? {
        try writerStore.load(
            mutation.writerRecord
        )
    }

    public func list(
        _ query: AgentFileMutationQuery = .all
    ) async throws -> [AgentFileMutationRecord] {
        guard FileManager.default.fileExists(
            atPath: recordsdir.path
        ) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: recordsdir,
            includingPropertiesForKeys: nil,
            options: [
                .skipsHiddenFiles
            ]
        )
        .filter {
            $0.pathExtension == "json"
        }

        var records = try urls.compactMap { url -> AgentFileMutationRecord? in
            let data = try Data(
                contentsOf: url
            )

            guard !data.isEmpty else {
                return nil
            }

            return try decoder.decode(
                AgentFileMutationRecord.self,
                from: data
            )
        }

        if let target = query.target {
            let path = target.standardizedFileURL.path

            records = records.filter {
                $0.target.standardizedFileURL.path == path
            }
        }

        if let toolCallID = query.toolCallID {
            records = records.filter {
                $0.toolCallID == toolCallID
            }
        }

        if let preparedIntentID = query.preparedIntentID {
            records = records.filter {
                $0.preparedIntentID == preparedIntentID
            }
        }

        records.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return query.latestFirst
                ? lhs.createdAt > rhs.createdAt
                : lhs.createdAt < rhs.createdAt
        }

        if let limit = query.limit {
            return Array(
                records.prefix(
                    max(
                        0,
                        limit
                    )
                )
            )
        }

        return records
    }

    public func delete(
        id: UUID
    ) async throws {
        let mutation = try await load(
            id: id
        )

        if let mutation {
            try writerStore.delete(
                mutation.writerRecord
            )
        }

        let url = recordfile(
            id: id
        )

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return
        }

        try FileManager.default.removeItem(
            at: url
        )
    }
}

public extension FileAgentFileMutationStore {
    var recordsdir: URL {
        mutationdir.appendingPathComponent(
            "records",
            isDirectory: true
        )
    }

    var writerRecordsdir: URL {
        mutationdir.appendingPathComponent(
            "writer-records",
            isDirectory: true
        )
    }

    var backupsdir: URL {
        mutationdir.appendingPathComponent(
            "backups",
            isDirectory: true
        )
    }

    nonisolated func backupStore() -> AgentWriteBackupStore {
        .init(
            mutationdir: mutationdir
        )
    }
}

private extension FileAgentFileMutationStore {
    var writerStore: StandardMutationRecordStore {
        WriteRecords.local.mutations(
            directory: writerRecordsdir
        )
    }

    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        return encoder
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return decoder
    }

    func createDirs() throws {
        for directory in [
            recordsdir,
            writerRecordsdir,
            backupsdir
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    func recordfile(
        id: UUID
    ) -> URL {
        recordsdir.appendingPathComponent(
            "\(id.uuidString.lowercased()).json",
            isDirectory: false
        )
    }
}
