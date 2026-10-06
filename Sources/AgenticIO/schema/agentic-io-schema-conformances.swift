import Path
import Workspace
import Schema
import Writers

// move into native libraries
// remove from here, remove retroactive conformances
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


extension PathSegmentType:
    @retroactive JSONSchemaProviding
{
    public static var jsonschema: JSONSchema {
        .string(cases: ["directory", "file"])
    }
}
