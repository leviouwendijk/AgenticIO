import Path
import AgenticWorkspace
import Schema
import Writers

extension PathAccessRootIdentifier:
    @retroactive JSONSchemaProviding
{
    public static var jsonschema: JSONSchema {
        .string()
    }
}

extension PathDirectoryState:
    @retroactive JSONSchemaProviding
{
    public static var jsonschema: JSONSchema {
        .string()
    }
}

extension StandardMutationFailurePolicy:
    @retroactive JSONSchemaProviding
{
    public static var jsonschema: JSONSchema {
        .string(
            cases: allCases.map(\.rawValue)
        )
    }
}

extension StandardReplacePolicy:
    @retroactive JSONSchemaProviding
{
    public static var jsonschema: JSONSchema {
        .string(
            cases: allCases.map(\.rawValue)
        )
    }
}

extension StandardDeletePolicy:
    @retroactive JSONSchemaProviding
{
    public static var jsonschema: JSONSchema {
        .string(
            cases: allCases.map(\.rawValue)
        )
    }
}

extension PathCapability:
    @retroactive JSONSchemaProviding
{
    public static var jsonschema: JSONSchema {
        .string(cases: allCases.map(\.rawValue))
    }
}

extension PathGrantMode:
    @retroactive JSONSchemaProviding
{
    public static var jsonschema: JSONSchema {
        .string(cases: allCases.map(\.rawValue))
    }
}

extension PathSegmentType:
    @retroactive JSONSchemaProviding
{
    public static var jsonschema: JSONSchema {
        .string(cases: ["directory", "file"])
    }
}
