public enum PathGrantLifetime:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case turn
    case session
}
