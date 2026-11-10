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
        let sections = difference.text_sections(options: options)
        for section in sections {
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

        // Only promote a single complete, bounded text section. The original
        // three-line-context layout must already contain every source line;
        // otherwise source transport would disclose additional unchanged text.
        if difference.contents.count == 1,
           let content = difference.contents.first,
           let section = sections.first,
           content.id == section.id,
           let name = namesByID[content.id],
           content.difference.hasChanges,
           content.difference.lines.count <= 1_024 {
            let source = content.difference
            var remainingBytes = 65_536
            for line in source.lines {
                let bytes = line.text.utf8.count
                if bytes > remainingBytes {
                    remainingBytes = -1
                    break
                }
                remainingBytes -= bytes
            }

            if remainingBytes >= 0,
               DifferenceLayout.make(source, options: .full) == section.layout {
                let presented = TextDifference(
                    oldName: "a/\(name)",
                    newName: "b/\(name)",
                    lines: source.lines,
                    quality: source.quality
                )
                return .init(title: title, source: presented, tree: tree)
            }
        }

        // Build per-file semantic projections from the same prepared content.
        // They contain visible rows only, not complete source snapshots.
        let changed = difference.contents.filter { $0.difference.hasChanges }
        if !changed.isEmpty && changed.count <= 32 {
            var semanticSections: [ToolPreflight.Preview.Difference.Section] = []
            var totalBytes = 0
            let reviewOptions = DifferenceRenderOptions(
                showHeader: true,
                showUnchangedLines: false,
                contextLineCount: 3,
                collapseSeparator: " ... {count} unchanged lines",
                showHunkHeaders: true
            )

            for content in changed {
                guard let name = namesByID[content.id] else {
                    throw PreparedMutationDifferenceProjectionError.inconsistentEntries
                }
                let source = content.difference
                let visibleCount = source.hunks(context: 3).reduce(0) {
                    $0 + $1.indices.count
                }
                guard visibleCount <= 1_024 else { break }

                // Replace all original names with authorized presentation paths.
                let named = TextDifference(
                    oldName: "a/\(name)",
                    newName: "b/\(name)",
                    lines: source.lines,
                    quality: source.quality
                )
                let projection = DifferenceLayout.project(
                    named.analyze(), mode: .split, options: reviewOptions
                )
                guard projection.rows.count <= 1_024 else { break }

                let section = ToolPreflight.Preview.Difference.Section(
                    id: content.id,
                    nodeID: content.node_id,
                    path: name,
                    projection: projection
                )
                let bytes = try JSONEncoder().encode(section).count
                guard bytes <= 65_536,
                      bytes <= 262_144 - totalBytes else { break }
                totalBytes += bytes
                semanticSections.append(section)
            }

            // An incomplete collection must never masquerade as a full review.
            if semanticSections.count == changed.count {
                return .init(
                    title: title,
                    layout: text,
                    sections: semanticSections,
                    tree: tree
                )
            }
        }

        // Oversized, unsupported and structural-only mutations retain the
        // complete existing layout rather than silently dropping changes.
        return .init(title: title, layout: text, tree: tree)
    }
}
