import Agentic
import Difference
import Foundation
import Path
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
        presentationPaths: [[String]],
        title: String = "File mutation preview"
    ) throws -> ToolPreflight.Preview.Difference? {
        guard plan.entries.count == presentationPaths.count else {
            throw PreparedMutationDifferenceProjectionError.inconsistentEntries
        }

        let difference = try plan.difference(root: root)
        let options = DifferenceRenderOptions(
            showHeader: true,
            showUnchangedLines: false,
            contextLineCount: 3
        )

        // Only approved presentation paths enter header text. Canonical
        // identities and original contents remain in the Writers plan.
        var namesByID: [String: String] = [:]
        var movesByID: [String: TreeDifferenceLayout.Line.Relocation] = [:]
        for (index, planned) in plan.entries.enumerated() {
            let paths = presentationPaths[index]
            guard paths.count == planned.entry.targets.count,
                  let name = paths.last else {
                throw PreparedMutationDifferenceProjectionError.inconsistentEntries
            }
            let id = planned.id.uuidString
            guard namesByID[id] == nil else {
                throw PreparedMutationDifferenceProjectionError.inconsistentEntries
            }
            namesByID[id] = name

            if case .move(let move) = planned.entry {
                let sourceID = StandardPath(rawPath: move.source.standardizedFileURL.path)
                    .render(as: .relative, filetype: true)
                guard movesByID[sourceID] == nil else {
                    throw PreparedMutationDifferenceProjectionError.inconsistentEntries
                }
                movesByID[sourceID] = .init(from: paths[0], to: paths[1])
            }
        }

        let tree = difference.make_tree_layout(presenting: { entry in
            .init(label: entry.label, relocation: movesByID[entry.id])
        })
        let represented = Set(tree.lines.compactMap { line in
            line.relocation == nil ? nil : line.id
        })
        guard represented == Set(movesByID.keys) else {
            throw PreparedMutationDifferenceProjectionError.inconsistentEntries
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
