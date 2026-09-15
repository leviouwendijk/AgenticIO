import TestFlows

@main
enum AgenticIOFlowTestMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: AgenticIOFlowSuite.self
        )
    }
}

enum AgenticIOFlowSuite: TestFlowRegistry {
    static let title = "AgenticIO flow tests"

    static let flows: [TestFlow] = [
        TestFlow(
            "prepared-operation-authoring",
            tags: [
                "agentic-io",
                "prepared-operation",
                "prepared-intent",
                "mutation",
                "path-grant",
                "persistence",
                "version",
            ]
        ) {
            try await AgenticIOFlowTesting
                .runPreparedOperationAuthoring()
        },
        TestFlow(
            "workspace-access-overlay",
            tags: [
                "agentic-io",
                "agentic-workspace",
                "path-grant",
                "overlay",
                "authorization",
                "persistence",
            ]
        ) {
            try await AgenticIOFlowTesting
                .runWorkspaceAccessOverlay()
        },
        TestFlow(
            "prepared-file-mutation-execution",
            tags: [
                "agentic-io",
                "prepared-operation",
                "execution",
                "mutation",
                "rollback",
                "persistence",
            ]
        ) {
            try await AgenticIOFlowTesting
                .runPreparedFileMutationExecution()
        },
        TestFlow(
            "mutate-files-workspace-targeting",
            tags: [
                "agentic-io",
                "mutation",
                "workspace-targeting",
                "authorization",
            ]
        ) {
            try await AgenticIOFlowTesting
                .runMutateFilesWorkspaceTargeting()
        },
        TestFlow(
            "mutate-files-relative-insertion",
            tags: [
                "agentic-io",
                "mutation",
                "edit",
                "insertion",
                "snapshot",
            ]
        ) {
            try await AgenticIOFlowTesting
                .runMutateFilesRelativeInsertion()
        },
        TestFlow(
            "path-search",
            tags: [
                "agentic-io",
                "search",
                "path",
                "authorization",
            ]
        ) {
            try await AgenticIOFlowTesting.runPathSearch()
        },
        TestFlow(
            "source-search",
            tags: [
                "agentic-io",
                "search",
                "concatenation",
                "authorization",
            ]
        ) {
            try await AgenticIOFlowTesting.runSourceSearch()
        },
        TestFlow(
            "search-proof",
            tags: [
                "agentic-io",
                "search",
                "parsing",
                "proof",
                "freshness",
            ]
        ) {
            try await AgenticIOFlowTesting.runSearchProof()
        },
        TestFlow(
            "search-context",
            tags: [
                "agentic-io",
                "search",
                "selection",
                "authorization",
                "freshness",
            ]
        ) {
            try await AgenticIOFlowTesting.runSearchContext()
        },
        TestFlow(
            "read-file-policy",
            tags: [
                "agentic-io",
                "read-file",
                "policy",
                "sensitivity",
                "approval",
            ]
        ) {
            try await AgenticIOFlowTesting.runReadFilePolicy()
        },
    ]
}
