import Agentic

public extension SystemIO.Tools.Read {
    /// Each read's text once, under a one-line header, reads separated by a
    /// blank line. The output keeps `content`, `lines` and `display` for
    /// programs; the model reads the numbered display when it asked for line
    /// numbers, the raw text otherwise.
    func render(
        _ output: Output,
        input: Input
    ) -> String? {
        output.files.map { file in
            render(file, includeLineNumbers: input.includeLineNumbers)
        }.joined(separator: "\n\n")
    }

    private func render(
        _ file: File,
        includeLineNumbers: Bool
    ) -> String {
        var header = file.path
        if let range = file.lineRange {
            if range.start == 1, file.lineCount == file.totalLineCount {
                header += " · \(file.totalLineCount) lines"
            } else {
                header += " · lines \(range.start)–\(range.end) of \(file.totalLineCount)"
            }
        } else {
            header += file.totalLineCount == 0 ? " · empty" : " · no lines selected"
        }
        if file.truncated, let range = file.lineRange {
            header += " · more follow: startLine \(range.end + 1) continues"
        }

        let body = includeLineNumbers
            ? file.display ?? file.content
            : file.content
        return body.isEmpty ? header : header + "\n" + body
    }
}
