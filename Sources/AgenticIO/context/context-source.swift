import Agentic

public enum ContextSource: Sendable, Codable, Hashable {
    case text(String)
    case message(Message)
    case transcriptEvent(TranscriptEvent)
    case files(ContextFileSource)
    case instruction(InstructionDefinition)
}
