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
    ]
}
