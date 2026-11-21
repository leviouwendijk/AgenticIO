import Agentic

public extension SystemIO.Tools.Search {
    /// Hits grouped by file, each with its lines as `rg` prints them:
    /// `12:` for a matching line, `11-` for context, `--` between regions.
    /// Which term matched is named only when several were searched.
    func render(
        _ output: Output,
        input: Input
    ) -> String? {
        var lines = [
            "\(output.kind.rawValue) search (\(output.mode.rawValue)): "
                + "\(output.returnedCandidateCount) of \(output.totalCandidateCount) regions from offset \(output.offset)"
                + " · \(output.searchedDocumentCount) slices searched, \(output.matchedDocumentCount) matched",
        ]
        if output.hasMore, let next = output.nextOffset {
            lines.append(
                "more: offset \(next) with expectedCorpusFingerprint {\"algorithm\": \"\(output.corpusFingerprint.algorithm)\", \"value\": \"\(output.corpusFingerprint.value)\"}"
            )
        }

        let terms = Set(output.candidates.flatMap { $0.evidence.map(\.query) })
        var files: [String] = []
        var grouped: [String: [SourceSearchCandidate]] = [:]
        for candidate in output.candidates {
            if grouped[candidate.path] == nil {
                files.append(candidate.path)
            }
            grouped[candidate.path, default: []].append(candidate)
        }

        for path in files {
            guard let candidates = grouped[path] else { continue }
            lines.append("")
            lines.append(path)
            var printed = Set<Int>()
            for (index, candidate) in candidates.enumerated() {
                var label = ""
                if terms.count > 1 {
                    label = candidate.evidence.map { evidence in
                        "\"\(evidence.queryID ?? evidence.query)\""
                    }.joined(separator: ", ")
                }
                for capture in candidate.captures {
                    label += (label.isEmpty ? "" : "  ") + "\(capture.name)=\(capture.tokens.joined(separator: " "))"
                }
                let shown = (candidate.lines ?? []).filter { !printed.contains($0.number) }
                if index > 0, !shown.isEmpty || !label.isEmpty {
                    lines.append("--")
                }
                if !label.isEmpty || shown.isEmpty {
                    let range = candidate.lineRange
                    let span = range.start == range.end ? "\(range.start)" : "\(range.start)–\(range.end)"
                    lines.append("lines \(span)" + (label.isEmpty ? "" : "  [\(label)]"))
                }
                for line in shown {
                    printed.insert(line.number)
                    lines.append("\(line.number)\(line.isMatch ? ":" : "-")\(line.text)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
