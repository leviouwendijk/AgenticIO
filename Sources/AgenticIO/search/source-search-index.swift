import Concatenation
import Foundation
import IO
import Search

/// Stable per-source identity. Content changes are carried by the index revision,
/// not by its document identity.
struct SourceSearchIndexedSourceID: Hashable, Sendable {
    let file: URL
    let transformation: ContentFingerprint

    init(_ record: ConcatenationSourceRecord) {
        self.file = record.file
        self.transformation = record.transformationFingerprint
    }
}

struct SourceSearchIndexedSliceID: Hashable, Sendable {
    let source: SourceSearchIndexedSourceID
    let sliceIndex: Int
}

/// The retained source index has an independent revision baseline from the
/// Concatenation disk cache. A full materialization is needed only on initial
/// attachment or when those two baselines cannot safely be reconciled.
struct SourceSearchIndexedCorpus {
    typealias Index = SearchIndex<SourceSearchIndexedSliceID, String>

    private var index = Index()
    private var metadata: [SourceSearchIndexedSliceID: SourceSearchDocumentID] = [:]
    private var revisions: [SourceSearchIndexedSourceID: String] = [:]

    var corpus: SearchCorpus<SourceSearchDocumentID> {
        SearchCorpus(
            documents: index.corpus.documents.compactMap { document in
                guard let publicID = metadata[document.id] else {
                    return nil
                }
                return SearchDocument(
                    id: publicID,
                    text: document.text
                )
            }
        )
    }

    mutating func update(
        snapshot: ConcatenationSourceSnapshot,
        materialization: ConcatenationCorpusMaterialization
    ) throws -> Index.UpdateStatistics {
        var sources: [SourceSearchIndexedSourceID: ConcatenationCorpusSource] = [:]
        for source in materialization.sources {
            sources[SourceSearchIndexedSourceID(source.record)] = source
        }

        let previous = index.descriptors
        var requested: [Index.Descriptor] = []
        var materialized: [SearchDocument<SourceSearchIndexedSliceID>] = []
        var nextMetadata: [SourceSearchIndexedSliceID: SourceSearchDocumentID] = [:]
        var nextRevisions: [SourceSearchIndexedSourceID: String] = [:]

        for record in snapshot.sources {
            let sourceID = SourceSearchIndexedSourceID(record)
            nextRevisions[sourceID] = record.sectionKey

            if let source = sources[sourceID] {
                for (sliceIndex, slice) in source.section.slices.enumerated()
                    where !slice.isEmpty
                {
                    let id = SourceSearchIndexedSliceID(
                        source: sourceID,
                        sliceIndex: sliceIndex
                    )
                    requested.append(
                        .init(id: id, revision: record.sectionKey)
                    )
                    materialized.append(
                        SearchDocument(
                            id: id,
                            text: slice.lines.joined(separator: "\n")
                        )
                    )
                    nextMetadata[id] = SourceSearchDocumentID(
                        path: source.section.presentedPath,
                        sectionKey: record.sectionKey,
                        sliceIndex: sliceIndex,
                        sourceStartLine: slice.startLine,
                        sourceFingerprint: record.contentFingerprint
                    )
                }
            } else {
                // Reusing tokens and text is sound only at the exact same
                // transformed-source revision. No implicit fallback to stale data.
                guard revisions[sourceID] == record.sectionKey else {
                    throw SourceSearchIndexError.missingSourceRevision(
                        record.file
                    )
                }
                for descriptor in previous where descriptor.id.source == sourceID {
                    requested.append(descriptor)
                    guard let publicID = metadata[descriptor.id] else {
                        throw SourceSearchIndexError.missingDocumentMetadata
                    }
                    nextMetadata[descriptor.id] = publicID
                }
            }
        }

        let plan = try index.plan(current: requested)
        // Only changed/added documents are supplied. An unchanged source may
        // be present in a materialization when another consumer refreshed the
        // Concatenation cache; it must not force retokenization.
        let required = Set(plan.requiresMaterialization.map(\.id))
        let changedDocuments = materialized.filter {
            required.contains($0.id)
        }
        let statistics = try index.apply(
            plan,
            materialized: changedDocuments
        )
        metadata = nextMetadata
        revisions = nextRevisions
        return statistics
    }

    func lexicalSearch(
        _ pattern: LexicalPattern,
        caseSensitive: Bool
    ) -> LexicalSearchResult<SourceSearchDocumentID> {
        let result = index.search(
            pattern,
            caseSensitive: caseSensitive
        )
        return LexicalSearchResult(
            searchedDocumentCount: result.searchedDocumentCount,
            matchedDocumentCount: result.matchedDocumentCount,
            matches: result.matches.compactMap { match in
                guard let publicID = metadata[match.documentID] else {
                    return nil
                }
                return LexicalMatch(
                    documentID: publicID,
                    range: match.range,
                    lineRange: match.lineRange,
                    captures: match.captures
                )
            }
        )
    }
}

enum SourceSearchIndexError: Error {
    case missingSourceRevision(URL)
    case missingDocumentMetadata
}

/// Last successful broad search. Refined `within` searches deliberately do not
/// overwrite these corpus-index diagnostics.
public struct SourceSearchCacheStatistics: Sendable, Equatable {
    public let sourceReads: Int
    public let sectionLoads: Int
    public let rebuilds: Int
    public let materializedSources: Int
    public let indexedDocuments: Int
    public let reusedDocuments: Int
    public let tokenizations: Int
    public let reusedTokenizations: Int

    init(
        reconciliation: ConcatenationStatistics.Cache,
        materialization: ConcatenationCorpusMaterialization,
        index: SearchIndex<SourceSearchIndexedSliceID, String>.UpdateStatistics
    ) {
        self.sourceReads = reconciliation.sourceReads
        self.sectionLoads = reconciliation.sectionLoads
        self.rebuilds = reconciliation.rebuilds
        self.materializedSources = materialization.count
        self.indexedDocuments = index.indexedDocuments
        self.reusedDocuments = index.reusedDocuments
        self.tokenizations = index.tokenizations
        self.reusedTokenizations = index.reusedTokenizations
    }
}
