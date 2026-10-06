import Foundation
import Macros
import Parsing
import Schema
import Search

@JSONSchema
public enum SourceLexicalPatternNodeInput:
    Sendable,
    Codable,
    Hashable
{
    case identifier(value: String)
    case symbol(value: String)
    case token(value: String)
    case any
    case sequence(children: [Int])
    case gap(
        minimum: Int,
        maximum: Int
    )
    case capture(
        name: String,
        child: Int
    )
    case optional(child: Int)
}

@JSONSchema
public struct SourceLexicalPatternInput:
    Sendable,
    Codable,
    Hashable
{
    /// Flat bounded lexical-pattern graph. Node references are zero-based
    /// indices and may refer only to earlier nodes.
    public let nodes: [SourceLexicalPatternNodeInput]

    /// Zero-based index of the final lexical pattern node.
    public let root: Int

    public init(
        nodes: [SourceLexicalPatternNodeInput],
        root: Int
    ) {
        self.nodes = nodes
        self.root = root
    }

    func lexicalPattern() throws -> LexicalPattern {
        guard !nodes.isEmpty else {
            throw SourceLexicalPatternInputError.emptyNodes
        }

        guard nodes.indices.contains(root) else {
            throw SourceLexicalPatternInputError.invalidRoot(
                root
            )
        }

        var patterns: [LexicalPattern] = []
        patterns.reserveCapacity(
            nodes.count
        )

        for (
            index,
            node
        ) in nodes.enumerated() {
            patterns.append(
                try node.lexicalPattern(
                    index: index,
                    prior: patterns
                )
            )
        }

        return patterns[root]
    }
}

public enum SourceLexicalPatternInputError:
    Error,
    Sendable,
    LocalizedError
{
    case emptyNodes
    case invalidRoot(Int)
    case invalidReference(
        node: Int,
        referenced: Int
    )
    case emptySequence(
        node: Int
    )
    case invalidGap(
        node: Int,
        minimum: Int,
        maximum: Int
    )
    case emptyCaptureName(
        node: Int
    )
    case invalidToken(
        node: Int,
        value: String
    )

    public var errorDescription: String? {
        switch self {
        case .emptyNodes:
            "Source lexical pattern requires at least one node."

        case .invalidRoot(let root):
            "Source lexical pattern root index \(root) is outside the node array."

        case .invalidReference(
            let node,
            let referenced
        ):
            "Source lexical node \(node) references node \(referenced). Nodes may reference only earlier nodes."

        case .emptySequence(let node):
            "Source lexical sequence node \(node) requires at least one child."

        case .invalidGap(
            let node,
            let minimum,
            let maximum
        ):
            "Source lexical gap node \(node) requires 0 <= minimum <= maximum; received \(minimum)...\(maximum)."

        case .emptyCaptureName(let node):
            "Source lexical capture node \(node) requires a non-empty capture name."

        case .invalidToken(
            let node,
            let value
        ):
            "Source lexical token node \(node) must contain exactly one non-trivia token; received '\(value)'."
        }
    }
}

private extension SourceLexicalPatternNodeInput {
    func lexicalPattern(
        index: Int,
        prior: [LexicalPattern]
    ) throws -> LexicalPattern {
        func resolve(
            _ reference: Int
        ) throws -> LexicalPattern {
            guard prior.indices.contains(reference) else {
                throw SourceLexicalPatternInputError.invalidReference(
                    node: index,
                    referenced: reference
                )
            }

            return prior[reference]
        }

        switch self {
        case .identifier(let value):
            return .identifier(
                value
            )

        case .symbol(let value):
            return .symbol(
                value
            )

        case .token(let value):
            return .token(
                try exactToken(
                    value,
                    node: index
                )
            )

        case .any:
            return .any

        case .sequence(let children):
            guard !children.isEmpty else {
                throw SourceLexicalPatternInputError.emptySequence(
                    node: index
                )
            }

            return .sequence(
                try children.map(resolve)
            )

        case .gap(
            let minimum,
            let maximum
        ):
            guard minimum >= 0,
                  maximum >= minimum else {
                throw SourceLexicalPatternInputError.invalidGap(
                    node: index,
                    minimum: minimum,
                    maximum: maximum
                )
            }

            return .gap(
                minimum: minimum,
                maximum: maximum
            )

        case .capture(
            let name,
            let child
        ):
            guard !name.isEmpty else {
                throw SourceLexicalPatternInputError.emptyCaptureName(
                    node: index
                )
            }

            return .capture(
                name: name,
                pattern: try resolve(child)
            )

        case .optional(let child):
            return .optional(
                try resolve(child)
            )
        }
    }

    func exactToken(
        _ value: String,
        node: Int
    ) throws -> Token {
        var options = LexerOptions()
        options.identifier_continuation = .punctuation_delimited
        options.emit_whitespace = false
        options.emit_newlines = false
        options.emit_comments = false

        var lexer = Lexer(
            source: value,
            sets: LexingSets(
                keywords: []
            ),
            options: options
        )
        let tokens = lexer.lexedTokens().filter { lexed in
            lexed.token != .eof
                && !lexed.token.is_trivia
        }

        guard tokens.count == 1,
              let token = tokens.first?.token else {
            throw SourceLexicalPatternInputError.invalidToken(
                node: node,
                value: value
            )
        }

        return token
    }
}

enum ResolvedSourceSearchQuery {
    case text([SearchProbe])
    case lexical(LexicalPattern)

    var summary: String {
        switch self {
        case .text(let probes):
            "\(probes.count) source probe(s)"

        case .lexical:
            "one lexical pattern"
        }
    }
}

extension SystemIO.Tools.SearchSources.Input {
    func resolvedSourceSearchQuery(
        toolName: String
    ) throws -> ResolvedSourceSearchQuery {
        let resolvedProbes = probes
            .map(\.searchProbe)
            .filter {
                !$0.isEmpty
            }

        switch (
            resolvedProbes.isEmpty,
            lexicalPattern
        ) {
        case (false, nil):
            return .text(
                resolvedProbes
            )

        case (true, .some(let lexicalPattern)):
            return .lexical(
                try lexicalPattern.lexicalPattern()
            )

        case (true, nil):
            throw PredefinedFileToolError.invalidValue(
                tool: toolName,
                field: "probes/lexicalPattern",
                reason: "must provide at least one non-empty search probe or one lexical pattern"
            )

        case (false, .some):
            throw PredefinedFileToolError.invalidValue(
                tool: toolName,
                field: "lexicalPattern",
                reason: "cannot be combined with text probes in one search request"
            )
        }
    }
}
