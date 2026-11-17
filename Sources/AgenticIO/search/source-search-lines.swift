import Search

extension SourceSearcher {
    /// At most this many matching lines per candidate; context comes on top.
    static let maximumMatchLines = 12
    /// Longer lines are cut, so one minified line cannot flood a result.
    static let maximumLineCharacters = 240

    /// Each candidate with its matching lines and `contextLines` around
    /// them, read from the slices that were searched: no file is read again.
    func attachingLines(
        to result: SourceSearchResult,
        from corpus: SearchCorpus<SourceSearchDocumentID>,
        contextLines: Int
    ) -> SourceSearchResult {
        let paths = Set(result.candidates.map(\.path))
        guard !paths.isEmpty else { return result }

        var slices: [String: [(start: Int, lines: [Substring])]] = [:]
        for document in corpus.documents where paths.contains(document.id.path) {
            slices[document.id.path, default: []].append((
                document.id.sourceStartLine,
                document.text.split(separator: "\n", omittingEmptySubsequences: false)
            ))
        }

        func line(_ number: Int, in path: String) -> Substring? {
            for slice in slices[path] ?? [] {
                let index = number - slice.start
                if index >= 0, index < slice.lines.count {
                    return slice.lines[index]
                }
            }
            return nil
        }

        return result.with(candidates: result.candidates.map { candidate in
            var matches = candidate.evidence
                .flatMap(\.lineRanges)
                .flatMap { Array($0.start...max($0.start, $0.end)) }
            if matches.isEmpty {
                matches = Array(candidate.lineRange.start...max(candidate.lineRange.start, candidate.lineRange.end))
            }
            let matching = Array(Set(matches)).sorted().prefix(Self.maximumMatchLines)

            var shown: [Int: Bool] = [:]
            for number in matching {
                shown[number] = true
                for offset in stride(from: -contextLines, through: contextLines, by: 1) where offset != 0 {
                    let near = number + offset
                    if shown[near] == nil { shown[near] = false }
                }
            }

            let lines = shown.keys.sorted().compactMap { number -> SourceSearchLine? in
                guard number >= 1, let text = line(number, in: candidate.path) else {
                    return nil
                }
                let cut = text.count > Self.maximumLineCharacters
                    ? text.prefix(Self.maximumLineCharacters) + "…"
                    : text
                return .init(number: number, text: String(cut), isMatch: shown[number] == true)
            }
            return candidate.with(lines: lines)
        })
    }
}
