import Schema
import SchemaMacros
import Search

@JSONSchema
public enum SourceSearchProbeRole:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case required
    case preferred
    case excluded

    var searchRole: SearchProbeRole {
        switch self {
        case .required:
            return .required

        case .preferred:
            return .preferred

        case .excluded:
            return .excluded
        }
    }
}

/// One deterministic source-search probe with independent admission role and matching strategy.
@JSONSchema
public struct SourceSearchProbeInput:
    Sendable,
    Codable,
    Hashable
{
    /// Search text for this probe.
    public let text: String

    /// Optional stable identifier used to preserve probe provenance.
    public let id: String?

    /// Positive ranking weight. Defaults to 1.
    @Schema(required: false)
    public let weight: Int

    /// Admission role. Required constrains admission, preferred enriches ranking, and excluded vetoes matching documents. Defaults to preferred.
    @Schema(required: false)
    public let role: SourceSearchProbeRole

    /// Matching strategy used only by this probe. Defaults to fuzzy.
    @Schema(required: false)
    public let strategy: SourceSearchStrategy

    public init(
        text: String,
        id: String? = nil,
        weight: Int = 1,
        role: SourceSearchProbeRole = .preferred,
        strategy: SourceSearchStrategy = .fuzzy
    ) {
        self.text = text
        self.id = id
        self.weight = max(
            1,
            weight
        )
        self.role = role
        self.strategy = strategy
    }

    var searchProbe: SearchProbe {
        SearchProbe(
            text,
            id: id,
            weight: weight,
            role: role.searchRole,
            strategy: strategy.searchStrategy
        )
    }
}

private extension SourceSearchProbeInput {
    enum CodingKeys: String, CodingKey {
        case text
        case id
        case weight
        case role
        case strategy
    }
}

public extension SourceSearchProbeInput {
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        self.init(
            text: try container.decode(
                String.self,
                forKey: .text
            ),
            id: try container.decodeIfPresent(
                String.self,
                forKey: .id
            ),
            weight: try container.decodeIfPresent(
                Int.self,
                forKey: .weight
            ) ?? 1,
            role: try container.decodeIfPresent(
                SourceSearchProbeRole.self,
                forKey: .role
            ) ?? .preferred,
            strategy: try container.decodeIfPresent(
                SourceSearchStrategy.self,
                forKey: .strategy
            ) ?? .fuzzy
        )
    }
}

extension SearchSourcesToolInput {
    func resolvedSearchProbes(
        toolName: String
    ) throws -> [SearchProbe] {
        let rich = probes
            .map(\.searchProbe)
            .filter {
                !$0.isEmpty
            }

        let legacy = queries
            .map { query in
                SearchProbe(
                    SearchQuery(
                        query.text,
                        id: query.id,
                        weight: query.weight
                    ),
                    role: .preferred,
                    strategy: strategy.searchStrategy
                )
            }
            .filter {
                !$0.isEmpty
            }

        guard rich.isEmpty || legacy.isEmpty else {
            throw PredefinedFileToolError.invalidValue(
                tool: toolName,
                field: "probes",
                reason: "cannot be combined with non-empty legacy queries"
            )
        }

        let resolved = rich.isEmpty
            ? legacy
            : rich

        guard !resolved.isEmpty else {
            throw PredefinedFileToolError.invalidValue(
                tool: toolName,
                field: "probes",
                reason: "must contain at least one non-empty rich probe or legacy query"
            )
        }

        return resolved
    }
}
