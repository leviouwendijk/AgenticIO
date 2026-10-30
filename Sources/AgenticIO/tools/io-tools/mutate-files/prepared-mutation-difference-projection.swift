import Agentic
import Difference
import Foundation
import Writers

public enum PreparedMutationDifferenceProjectionError: Error, Sendable {
    case inconsistentEntries
}

/// Projects the exact Writers plan into the native Agentic review diff.
/// No re-planning, filesystem reads, or independent diff algorithm occurs.
public enum PreparedMutationDifferenceProjection {
    public static func project(
        _ plan: StandardMutationPlan,
        root: URL,
        presentationPaths: [String],
        title: String = "File mutation preview"
    ) throws -> ToolPreflight.Preview.Difference? {
        guard plan.entries.count == presentationPaths.count else {
            throw PreparedMutationDifferenceProjectionError.inconsistentEntries
        }

        let difference = try plan.difference(root: root)
        let tree = difference.layout.tree
        let options = DifferenceRenderOptions(
            showHeader: true,
            showUnchangedLines: false,
            contextLineCount: 3
        )

        // Only approved presentation paths enter header text. Canonical
        // identities and original contents remain in the Writers plan.
        var namesByID: [String: String] = [:]
        for (index, entry) in plan.entries.enumerated() {
            let id = entry.id.uuidString
            guard namesByID[id] == nil else {
                throw PreparedMutationDifferenceProjectionError.inconsistentEntries
            }
            namesByID[id] = presentationPaths[index]
        }

        var lines: [DifferenceLayout.Line] = []
        for section in difference.text_sections(options: options) {
            guard let name = namesByID[section.id] else {
                throw PreparedMutationDifferenceProjectionError.inconsistentEntries
            }
            if !lines.isEmpty {
                lines.append(.init(role: .separator, text: ""))
            }
            for line in section.layout.lines {
                let text: String
                switch line.role {
                case .headerOld: text = "a/\(name)"
                case .headerNew: text = "b/\(name)"
                default: text = line.text
                }
                lines.append(.init(
                    role: line.role,
                    text: text,
                    coordinate: line.coordinate
                ))
            }
        }
        let text = DifferenceLayout(lines: lines)
        guard !text.isEmpty || !tree.lines.isEmpty else { return nil }
        return .init(title: title, layout: text, tree: tree)
    }
}
