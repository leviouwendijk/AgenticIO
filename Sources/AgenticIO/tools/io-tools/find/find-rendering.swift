import Agentic
import Path

public extension SystemIO.Tools.Find {
    /// How a listing reads to the model. The output always lists every entry;
    /// only the text the model reads is summarized.
    struct Projection: Sendable, Hashable {
        /// A listing with more entries than this shows the deepest levels
        /// that fit in as many lines; directories below them read as counts
        /// (`Sources/ (3 dirs, 41 files)`). `expand: true` lists everything.
        public var collapseAbove: Int
        /// Indentation per tree level.
        public var indentation: String

        public init(
            collapseAbove: Int = 150,
            indentation: String = "  "
        ) {
            self.collapseAbove = max(1, collapseAbove)
            self.indentation = indentation
        }
    }

    /// A listing as an indented tree, matches as one ranked line each.
    func render(
        _ output: Output,
        input: Input
    ) -> String? {
        output.isListing
            ? renderListing(output, input: input)
            : renderMatches(output)
    }
}

private extension SystemIO.Tools.Find {
    /// The listing as an indented tree under a one-line header.
    func renderListing(
        _ output: Output,
        input: Input
    ) -> String? {
        let prefix = output.directory.map { $0 + "/" }
        let paths = output.entries.map { entry in
            var path = entry.path
            if let prefix, path.hasPrefix(prefix) {
                path.removeFirst(prefix.count)
            }
            return (path: path, isDirectory: entry.isDirectory)
        }

        var tree = PathTree(
            root: StandardPath(
                rawPath: output.directory ?? output.rootID
            )
        )
        do {
            for entry in paths {
                try tree.appendPath(
                    rawPath: entry.path,
                    type: entry.isDirectory ? .directory : .file
                )
            }
        } catch {
            return nil
        }

        // Lines shown down to each depth; keep the deepest that fits.
        let depths = paths.map { $0.path.split(separator: "/").count - 1 }
        var collapse: Int?
        if !input.expand,
           paths.count > projection.collapseAbove,
           let deepest = depths.max() {
            collapse = (0..<deepest).reversed().first { depth in
                depths.filter { $0 <= depth }.count <= projection.collapseAbove
            } ?? 0
        }

        let directories = paths.filter(\.isDirectory).count
        var header = "\(output.directory ?? "."): \(paths.count) entries "
            + "(\(directories) dirs, \(paths.count - directories) files)"
        if output.truncated {
            header += ", stopped at maxEntries"
        }

        var lines = [header]
        if !paths.isEmpty {
            lines.append(
                tree.render(
                    .init(
                        indentation: projection.indentation,
                        includeRoot: false,
                        sortChildren: true,
                        collapseDepth: collapse
                    )
                )
            )
        }
        if collapse != nil {
            lines.append(
                "[Directories with counts are not expanded. Find one by path, or pass expand: true, to list everything.]"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Matches as one ranked line each: path, score, the probes it matched.
    func renderMatches(
        _ output: Output
    ) -> String {
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
