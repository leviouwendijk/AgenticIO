import AgenticIO
import Workspace
import Concatenation
import Foundation
import Path
import Search
import Testing

extension AgenticIOFlowTesting {
    static func runSourceSearchIndex() async throws -> [TestDiagnostic] {
        try proveSearchIndexContract()
        try await proveRetainedSourceSearchIndex()
        return [
            .message(
                "SearchIndex preserves revision reuse, stale-plan rejection, and lexical equivalence; SourceSearcher incrementally indexes authorized Concatenation sources"
            ),
        ]
    }

    private static func proveSearchIndexContract() throws {
        typealias Index = SearchIndex<String, Int>
        var index = Index()
        let first = [
            Index.Descriptor(id: "A", revision: 1),
            Index.Descriptor(id: "B", revision: 1),
            Index.Descriptor(id: "C", revision: 1),
        ]
        let initial = try index.plan(current: first)
        let initialStatistics = try index.apply(
            initial,
            materialized: [
                SearchDocument(id: "A", text: "needle alpha"),
                SearchDocument(id: "B", text: "needle beta"),
                SearchDocument(id: "C", text: "other gamma"),
            ]
        )
        try Expect.equal(initialStatistics.tokenizations, 3, "cold index tokenizes three documents")
        try Expect.equal(index.search(.identifier("needle")).matchedDocumentCount, 2, "indexed lexical search finds both retained needle documents")

        let repeated = try index.plan(current: first)
        let repeatedStats = try index.apply(repeated, materialized: [])
        try Expect.equal(repeatedStats.tokenizations, 0, "warm index does not tokenize")
        try Expect.equal(repeatedStats.reusedTokenizations, 3, "warm index reuses all token streams")
        try Expect.equal(
            index.search(.identifier("needle")).matches,
            LexicalSearch.search(.identifier("needle"), in: index.corpus).matches,
            "cached lexical matches and stateless lexical matches are identical"
        )

        let changed = [
            Index.Descriptor(id: "A", revision: 1),
            Index.Descriptor(id: "B", revision: 2),
        ]
        let changedPlan = try index.plan(current: changed)
        try Expect.equal(changedPlan.removed, ["C"], "removed document is planned for removal")
        let changedStats = try index.apply(
            changedPlan,
            materialized: [SearchDocument(id: "B", text: "delta beta")]
        )
        try Expect.equal(changedStats.tokenizations, 1, "changing one revision tokenizes one document")
        try Expect.equal(changedStats.removedDocuments, 1, "removed document is discarded")
        try Expect.equal(index.corpus.documents.map(\.id), ["A", "B"], "index preserves requested order")
        try Expect.equal(index.search(.identifier("needle")).matchedDocumentCount, 1, "stale matches disappear after revision change")

        var staleRejected = false
        do {
            _ = try index.apply(repeated, materialized: [])
        } catch Index.IndexError.stalePlan {
            staleRejected = true
        }
        try Expect.equal(staleRejected, true, "stale update plan is rejected")

        var duplicateRejected = false
        do {
            _ = try index.plan(current: [first[0], first[0]])
        } catch Index.IndexError.duplicateDescriptor {
            duplicateRejected = true
        }
        try Expect.equal(duplicateRejected, true, "duplicate document identities are rejected")
    }

    private static func proveRetainedSourceSearchIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "agentic-io-index-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let a = sources.appendingPathComponent("A.swift")
        let b = sources.appendingPathComponent("B.swift")
        try "header\nneedle alpha\nfooter".write(to: a, atomically: true, encoding: .utf8)
        try "needle beta".write(to: b, atomically: true, encoding: .utf8)
        let workspace = try makeAgenticIOTestingWorkspace(root: root)
        let searcher = SourceSearcher()
        let definition = try ConcatenationCorpusDefinition.parsing(includes: ["Sources/**"])
        let request = SourceSearchRequest(
            definition: definition,
            lexicalPattern: .identifier("needle")
        )

        let first = try await searcher.search(request, workspace: workspace)
        let firstStatistics = try Expect.notNil(
            await searcher.lastCacheStatistics,
            "cold source search reports index statistics"
        )
        try Expect.equal(first.matchedDocumentCount, 2, "cold lexical search sees both files")
        try Expect.equal(firstStatistics.tokenizations, 2, "cold lexical index tokenizes two source slices")

        let warm = try await searcher.search(request, workspace: workspace)
        let warmStatistics = try Expect.notNil(
            await searcher.lastCacheStatistics,
            "warm source search reports statistics"
        )
        try Expect.equal(warm.candidates, first.candidates, "warm search preserves exact source candidates")
        try Expect.equal(warmStatistics.tokenizations, 0, "warm search performs no tokenizations")
        try Expect.equal(warmStatistics.materializedSources, 0, "warm search loads no source sections")
        try Expect.equal(warmStatistics.sourceReads, 0, "warm reconcile does not read source text")
        try Expect.equal(warmStatistics.sectionLoads, 0, "warm reconcile does not load cache sections")

        try "header\nneedle gamma\nfooter\nnew tail".write(to: a, atomically: true, encoding: .utf8)
        let changed = try await searcher.search(request, workspace: workspace)
        let changedStatistics = try Expect.notNil(
            await searcher.lastCacheStatistics,
            "changed source search reports statistics"
        )
        try Expect.equal(changedStatistics.tokenizations, 1, "one changed source retokenizes one slice")
        try Expect.equal(changedStatistics.materializedSources, 1, "one changed source materializes one source section")
        try Expect.equal(changed.matchedDocumentCount, 2, "changed source retains unaffected search results")

        try FileManager.default.removeItem(at: b)
        let removed = try await searcher.search(request, workspace: workspace)
        let removedStatistics = try Expect.notNil(
            await searcher.lastCacheStatistics,
            "removed source search reports statistics"
        )
        try Expect.equal(removedStatistics.tokenizations, 0, "removal requires no tokenization")
        try Expect.equal(removedStatistics.indexedDocuments, 1, "removed source is pruned from index")
        try Expect.equal(removed.matchedDocumentCount, 1, "removed source produces no search matches")
    }
}
