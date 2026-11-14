import Agentic

public extension SystemIO.Tools.SearchSources {
    /// Candidate regions grouped by file. Each file names its section and
    /// fingerprint once, as `load_search_context` takes them; fingerprints
    /// read `algorithm:value`.
    func render(
        _ output: Output,
        input: Input
    ) -> String? {
        var lines = [
            "\(output.kind.rawValue) search (\(output.mode.rawValue)): "
                + "\(output.returnedCandidateCount) of \(output.totalCandidateCount) regions from offset \(output.offset)"
                + " · \(output.searchedDocumentCount) slices searched, \(output.matchedDocumentCount) matched",
            "corpus \(output.corpusFingerprint)",
        ]
        if output.hasMore, let next = output.nextOffset {
            lines.append(
                "more: offset \(next) with expectedCorpusFingerprint {\"algorithm\": \"\(output.corpusFingerprint.algorithm)\", \"value\": \"\(output.corpusFingerprint.value)\"}"
            )
        }

        var files: [String] = []
        var grouped: [String: [SourceSearchCandidate]] = [:]
        for candidate in output.candidates {
            let key = candidate.path + "\u{0}" + candidate.sectionKey + "\u{0}" + candidate.sourceFingerprint.description
            if grouped[key] == nil {
                files.append(key)
            }
            grouped[key, default: []].append(candidate)
        }

        for key in files {
            guard let candidates = grouped[key], let first = candidates.first else {
                continue
            }
            var file = first.path
            if !first.sectionKey.isEmpty, first.sectionKey != first.path {
                file += "  section \(first.sectionKey)"
            }
            lines.append("")
            lines.append(file + "  \(first.sourceFingerprint)")
            for candidate in candidates {
                var line = "  \(candidate.lineRange.start)–\(candidate.lineRange.end)  score \(candidate.score)"
                let evidence = candidate.evidence.map { evidence in
                    let ranges = evidence.lineRanges
                        .map { $0.start == $0.end ? "\($0.start)" : "\($0.start)–\($0.end)" }
                        .joined(separator: ",")
                    return "\"\(evidence.query)\"" + (ranges.isEmpty ? "" : " " + ranges)
                }
                if !evidence.isEmpty {
                    line += "  [" + evidence.joined(separator: "; ") + "]"
                }
                for capture in candidate.captures {
                    line += "  \(capture.name)=\(capture.tokens.joined(separator: " "))"
                }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }
}
