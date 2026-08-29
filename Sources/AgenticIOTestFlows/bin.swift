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
    ]
}
