import Agentic
import Schema
import Macros
import Clipboard

extension SystemIO.Tools {
    @Tool
    public struct ClipboardRead: Tool {
        public init() {}

        @JSONSchema
        public struct Input: Source {
            // Optionally target a named register (defaults to system)
            public let register: String?
            
            public init(
                register: String? = nil
            ) {
                self.register = register
            }
        }

        @JSONSchema
        public struct Output: Result {
            public let contents: String?
            
            public init(
                contents: String?
            ) {
                self.contents = contents
            }
        }

        public static let purpose = """
        Read from an optionally named or system clipboard register.
        """

        // for now keeping clipboard reads approval gated 
        public static let risk: ActionRisk = .boundedmutate

        public func preflight(
            _ input: Input,
            in context: ToolContext
        ) async throws -> ToolPreflight {
            ToolPreflight(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "Read from an optionally named or system clipboard register.",
                access: .init(
                    capabilities: [.read]
                ),
                estimates: .init(
                    read: .init(
                        bytes: nil,
                        lines: nil,
                        files: 1
                    ),
                    runtime: 0.1
                ),
                preview: .none,
                sideEffects: [],
                policyChecks: [
                    "clipboard_access_authorized"
                ],
                warnings: []
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            let register: Clipboard.Channel

            if let name = input.register {
                register = Clipboard.register(name) 
            } else {
                register = Clipboard.system
            }

            let possible_contents = register.read()

            return Output(
                contents: possible_contents
            )
        }
    }
}
