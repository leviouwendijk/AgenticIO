import Agentic

public extension SystemIO.Tools.SearchFilepaths {
    /// Matches as one ranked line each: path, score, the probes it matched.
    func render(
        _ output: Output,
        input: Input
    ) -> String? {
        var header = "\(output.entries.count) matches"
        if let searched = output.searchedPathCount {
            header += " in \(searched) paths"
        }
        if output.truncated {
            header += ", stopped at maxEntries"
        }

        let lines = output.entries.map { entry -> String in
            var line = entry.path + (entry.isDirectory && !entry.path.hasSuffix("/") ? "/" : "")
            if let score = entry.score {
                line += "  score \(score)"
            }
            let probes = (entry.evidence ?? []).map(\.query)
            if !probes.isEmpty {
                line += "  [" + probes.joined(separator: ", ") + "]"
            }
            return line
        }
        return ([header] + lines).joined(separator: "\n")
    }
}
