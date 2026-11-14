import Agentic

public extension SystemIO.Tools.ReadFile {
    /// The file text once, under a one-line header. The output keeps
    /// `content`, `lines` and `display` for programs; the model reads the
    /// numbered display when it asked for line numbers, the raw text
    /// otherwise.
    func render(
        _ output: Output,
        input: Input
    ) -> String? {
        var header = output.path
        if let range = output.lineRange {
            if range.start == 1, output.lineCount == output.totalLineCount {
                header += " · \(output.totalLineCount) lines"
            } else {
                header += " · lines \(range.start)–\(range.end) of \(output.totalLineCount)"
            }
        } else {
            header += output.totalLineCount == 0 ? " · empty" : " · no lines selected"
        }
        if output.truncated, let range = output.lineRange {
            header += " · more follow: startLine \(range.end + 1) continues"
        }

        let body = input.includeLineNumbers
            ? output.display ?? output.content
            : output.content
        return body.isEmpty ? header : header + "\n" + body
    }
}
