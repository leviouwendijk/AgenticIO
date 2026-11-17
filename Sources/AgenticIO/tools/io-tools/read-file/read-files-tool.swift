import Agentic
import Macros
import Schema

public extension SystemIO.Tools {
    /// Several reads in one call, each as `read_file` would make it: what
    /// `cat a b` or a few `sed -n` ranges do in a shell.
    @Tool
    struct ReadFiles: Tool {
        @JSONSchema
        public struct Input: HashableSource {
            /// The reads, in order: each a path with an optional line window, as read_file takes them. At most 20.
            public let reads: [ReadFile.Input]

            public init(
                reads: [ReadFile.Input]
            ) {
                self.reads = reads
            }
        }

        public struct Output: HashableResult {
            public static var jsonschema: JSONSchema {
                .object()
            }

            public let files: [ReadFile.Output]

            public init(
                files: [ReadFile.Output]
            ) {
                self.files = files
            }
        }

        public static let purpose = "Read several files, or several line windows, in one call; each as read_file reads it."
        public static let risk: ActionRisk = .observe
        public static let maximumReads = 20

        let file = ReadFile()

        public init() {}

        public func preflight(
            _ input: Input,
            in context: ToolContext
        ) async throws -> ToolPreflight {
            try validate(input)
            var preflights: [ToolPreflight] = []
            for read in input.reads {
                preflights.append(try await file.preflight(read, in: context))
            }
            let risk = ActionRisk.allCases.last { candidate in
                preflights.contains { $0.risk == candidate }
            } ?? Self.risk
            let targets: [String] = preflights.flatMap(\.access.targets)
            let roots: [String] = Array(Set(preflights.flatMap(\.access.roots))).sorted()
            let lines: Int = preflights.compactMap { $0.estimates.read.lines }.reduce(0, +)
            let noun = input.reads.count == 1 ? "window" : "windows"

            return .init(
                tool: Self.definition.identifier,
                risk: risk,
                summary: "Read \(input.reads.count) file \(noun): \(targets.joined(separator: ", "))",
                access: .init(
                    targets: targets,
                    roots: roots,
                    capabilities: [.read]
                ),
                estimates: .init(
                    read: .init(
                        lines: lines,
                        files: Set(targets).count
                    )
                ),
                policyChecks: Array(Set(preflights.flatMap(\.policyChecks))).sorted(),
                warnings: preflights.flatMap(\.warnings)
            )
        }

        public func call(
            _ input: Input,
            in context: ToolContext
        ) async throws -> Output {
            try validate(input)
            var files: [ReadFile.Output] = []
            for read in input.reads {
                files.append(try await file.call(read, in: context))
            }
            return .init(files: files)
        }

        /// Each read under its own header, as read_file renders it.
        public func render(
            _ output: Output,
            input: Input
        ) -> String? {
            zip(output.files, input.reads).compactMap { file, read in
                self.file.render(file, input: read)
            }.joined(separator: "\n\n")
        }

        private func validate(
            _ input: Input
        ) throws {
            guard !input.reads.isEmpty, input.reads.count <= Self.maximumReads else {
                throw PredefinedFileToolError.invalidValue(
                    tool: Self.identifier.rawValue,
                    field: "reads",
                    reason: "must hold between 1 and \(Self.maximumReads) reads"
                )
            }
        }
    }
}
