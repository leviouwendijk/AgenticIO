import Schema

public struct ContextCompositionPlan:
    Sendable,
    Codable,
    Hashable,
    JSONSchemaProviding
{
    public var metadata: ContextMetadata
    public var sources: [ContextSource]

    public init(
        metadata: ContextMetadata = .init(),
        sources: [ContextSource] = []
    ) {
        self.metadata = metadata
        self.sources = sources
    }

    public static var jsonschema: JSONSchema {
        .any
    }
}
