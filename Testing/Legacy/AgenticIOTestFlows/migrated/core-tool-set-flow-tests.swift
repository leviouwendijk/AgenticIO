import Agentic
import AgenticIO
import Testing

extension AgenticIOFlowTesting {
    static func runCoreToolSetBuilderRegistration() async throws -> [TestDiagnostic] {
        let fileRegistry = try Agentic.tool.registry {
            CoreFileToolSet()
        }

        try Expect.equal(
            fileRegistry.count,
            4,
            "core file tool set count"
        )

        _ = try Expect.notNil(
            fileRegistry.tool(
                named: "read_file"
            ),
            "core file tool set read_file"
        )

        _ = try Expect.notNil(
            fileRegistry.tool(
                named: "mutate_files"
            ),
            "core file tool set mutate_files"
        )

        _ = try Expect.notNil(
            fileRegistry.tool(
                named: "remove_empty_directories"
            ),
            "core file tool set remove_empty_directories"
        )

        _ = try Expect.notNil(
            fileRegistry.tool(
                named: "scan_paths"
            ),
            "core file tool set scan_paths"
        )

        try Expect.isNil(
            fileRegistry.tool(
                named: "write_file"
            ),
            "core file tool set does not expose write_file by default"
        )

        try Expect.isNil(
            fileRegistry.tool(
                named: "edit_file"
            ),
            "core file tool set does not expose edit_file by default"
        )

        let mutateFilesSchema = String(
            describing: SystemIO.Tools.MutateFiles.inputSchema
        )

        try Expect.contains(
            mutateFilesSchema,
            "create_text",
            "mutate_files schema exposes create_text"
        )

        try Expect.contains(
            mutateFilesSchema,
            "replace_text",
            "mutate_files schema exposes replace_text"
        )

        try Expect.contains(
            mutateFilesSchema,
            "edit_text",
            "mutate_files schema exposes edit_text"
        )

        try Expect.contains(
            mutateFilesSchema,
            "move",
            "mutate_files schema exposes move"
        )

        try Expect.contains(
            mutateFilesSchema,
            "delete",
            "mutate_files schema exposes delete"
        )

        let contextRegistry = try Agentic.tool.registry {
            CoreContextToolSet()
        }

        try Expect.equal(
            contextRegistry.count,
            3,
            "core context tool set count"
        )

        _ = try Expect.notNil(
            contextRegistry.tool(
                named: "compose_context"
            ),
            "core context tool set compose_context"
        )

        _ = try Expect.notNil(
            contextRegistry.tool(
                named: "inspect_context_sources"
            ),
            "core context tool set inspect_context_sources"
        )

        _ = try Expect.notNil(
            contextRegistry.tool(
                named: "estimate_context_size"
            ),
            "core context tool set estimate_context_size"
        )

        let coreRegistry = try Agentic.tool.registry {
            CoreToolSet(
                includeInteractionTools: true
            )
        }

        try Expect.equal(
            coreRegistry.count,
            8,
            "core tool set count"
        )

        _ = try Expect.notNil(
            coreRegistry.tool(
                named: "clarify_with_user"
            ),
            "core tool set clarify_with_user"
        )

        return [
            .field(
                "file_tools",
                "\(fileRegistry.count)"
            ),
            .field(
                "context_tools",
                "\(contextRegistry.count)"
            ),
            .field(
                "core_tools",
                "\(coreRegistry.count)"
            ),
            .field(
                "interaction_tools",
                "included"
            )
        ]
    }
}
