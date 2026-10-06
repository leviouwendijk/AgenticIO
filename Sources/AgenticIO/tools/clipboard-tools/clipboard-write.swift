import Agentic
import Schema
import Macros
import Clipboard

extension SystemIO.Tools {
    @Tool
    public struct ClipboardWrite: Tool {
        public init() {}

        @JSONSchema
        public struct Input: Source {
            // The string text contents to paste into the register
            public let contents: String
            // Optionally target a named register (defaults to system)
            public let register: String?
            
            public init(
                contents: String,
                register: String? = nil
            ) {
                self.contents = contents
                self.register = register
            }
        }

        @JSONSchema
        public struct Output: Result {
            //// Whether or not the write operation succeeded
            public let success: Bool
            
            public init(
                success: Bool
            ) {
                self.success = success
            }
        }

        public static let purpose = """
        Write to an optionally named or system clipboard register.
        """
        public static let risk: ActionRisk = .boundedmutate

        public func preflight(
            _ input: Input,
            in context: ToolContext
        ) async throws -> ToolPreflight {
            ToolPreflight(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "Write to an optionally named or system clipboard register.",
                access: .init(
                    capabilities: [.write]
                ),
                estimates: .init(
                    write: .init(
                        count: 1,
                        bytes: input.contents.utf8.count,
                        changedLines: nil
                    ),
                    runtime: 0.1,
                    bytes: input.contents.utf8.count
                ),
                preview: .init(
                    command: "clipboard write \(input.contents.prefix(20))\(input.contents.count > 20 ? "..." : "")"
                ),
                sideEffects: ["clipboard_content_overwritten"],
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

            let outcome = register.write(
                input.contents
            )

            return Output(
                success: outcome
            )
        }
    }
}
