import Testing

private enum AgenticIOTestingMainError: Error {
    case failed
}

@main
struct AgenticIOTestingMain {
    static func main() async throws {
        let reporter = PlainTextTestReporter()
        let result = await TestRunner.run(
            AgenticIOFlowSuite.testSuite,
            sink: reporter
        )
        let rendered = await reporter.rendered()

        if !rendered.isEmpty {
            print(
                rendered
            )
        }

        if result.isFailure {
            throw AgenticIOTestingMainError.failed
        }
    }
}

enum AgenticIOFlowSuite: TestFlowRegistry {
    static let title = "AgenticIO flow tests"

    static let flows: [TestFlow] = [
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
