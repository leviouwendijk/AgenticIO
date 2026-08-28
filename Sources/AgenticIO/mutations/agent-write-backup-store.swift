import Foundation
import Writers

public struct AgentWriteBackupStore: WriteBackupStore {
    public let mutationdir: URL

    public init(
        mutationdir: URL
    ) {
        self.mutationdir = mutationdir.standardizedFileURL
    }

    public func storeBackup(
        _ request: WriteBackupRequest
    ) throws -> WriteBackupRecord {
        let backupdir = backupdir(
            id: request.id
        )

        try FileManager.default.createDirectory(
            at: backupdir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let datafile = backupdir.appendingPathComponent(
            "backup.data",
            isDirectory: false
        )

        try request.data.write(
            to: datafile,
            options: .atomic
        )

        let record = WriteBackupRecord(
            id: request.id,
            target: request.target,
            storage: .local(datafile),
            createdAt: request.createdAt,
            originalFingerprint: request.snapshot.fingerprint,
            byteCount: request.snapshot.byteCount,
            policy: request.policy,
            metadata: [
                "store": "agentic_session_store"
            ]
        )

        let data = try encoder.encode(
            record
        )

        try data.write(
            to: metafile(
                id: request.id
            ),
            options: .atomic
        )

        return record
    }

    public func loadBackup(
        _ record: WriteBackupRecord
    ) throws -> Data? {
        guard let url = record.storage?.localURL else {
            return nil
        }

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return nil
        }

        return try Data(
            contentsOf: url
        )
    }
}

private extension AgentWriteBackupStore {
    var backupsdir: URL {
        mutationdir.appendingPathComponent(
            "backups",
            isDirectory: true
        )
    }

    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        return encoder
    }

    func backupdir(
        id: UUID
    ) -> URL {
        backupsdir.appendingPathComponent(
            id.uuidString.lowercased(),
            isDirectory: true
        )
    }

    func metafile(
        id: UUID
    ) -> URL {
        backupdir(
            id: id
        ).appendingPathComponent(
            "backup.json",
            isDirectory: false
        )
    }
}
