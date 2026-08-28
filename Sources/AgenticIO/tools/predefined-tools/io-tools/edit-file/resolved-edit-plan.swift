import AgenticWorkspace
import Foundation
import Readers
import Writers

struct ResolvedEditPlan: Sendable, Hashable {
    let input: EditFileToolInput
    let authorized: AgenticAuthorizedPath
    let snapshot: StandardEditSnapshot
    let operations: [StandardEditOperation]
    let editMode: StandardEditMode

    var operationCount: Int {
        operations.count
    }

    func requireCurrentSnapshot(
        encoding: String.Encoding = .utf8
    ) throws {
        let current = try Self.readContent(
            at: authorized.absoluteURL,
            encoding: encoding
        )
        let currentFingerprint = StandardContentFingerprint.fingerprint(
            for: current
        )

        guard currentFingerprint == snapshot.fingerprint else {
            throw EditFileToolError.snapshotChanged(
                path: authorized.presentationPath,
                expected: snapshot.fingerprint,
                actual: currentFingerprint
            )
        }
    }

    static func readContent(
        at url: URL,
        encoding: String.Encoding = .utf8
    ) throws -> String {
        try IntegratedReader.text(
            at: url,
            encoding: encoding,
            missingFileReturnsEmpty: true,
            normalizeNewlines: false
        )
    }
}
