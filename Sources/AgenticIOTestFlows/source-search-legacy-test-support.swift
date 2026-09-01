import AgenticIO
import Path

/// Test-target-only adapter that keeps older source-search fixtures concise while
/// production SearchSourcesToolInput exposes only the canonical probes API.
extension SearchSourcesToolInput {
    init(
        rootID: PathAccessRootIdentifier = .project,
        includes: [String] = ["**"],
        excludes: [String] = [],
        selections: [String] = [],
        queries: [SourceSearchQueryInput],
        mode: SourceSearchMode = .ranked,
        strategy: SourceSearchStrategy = .fuzzy,
        caseSensitive: Bool = false,
        minimumScore: Int = 1,
        offset: Int = 0,
        expectedCorpusFingerprint: SourceFingerprintInput? = nil,
        mergeDistanceLines: Int = 3,
        maximumCandidates: Int = 16,
        maximumCandidatesPerDocument: Int = 2
    ) {
        self.init(
            rootID: rootID,
            includes: includes,
            excludes: excludes,
            selections: selections,
            probes: queries.map { query in
                SourceSearchProbeInput(
                    text: query.text,
                    id: query.id,
                    weight: query.weight,
                    role: .preferred,
                    strategy: strategy
                )
            },
            mode: mode,
            caseSensitive: caseSensitive,
            minimumScore: minimumScore,
            offset: offset,
            expectedCorpusFingerprint: expectedCorpusFingerprint,
            mergeDistanceLines: mergeDistanceLines,
            maximumCandidates: maximumCandidates,
            maximumCandidatesPerDocument: maximumCandidatesPerDocument
        )
    }
}
