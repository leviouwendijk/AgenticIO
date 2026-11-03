import Agentic
import Path

/// Shared agent-facing read policy. Workspace authorization remains the
/// responsibility of Workspace and FileToolAccess.
public struct FileReadSensitivityAssessment: Sendable {
    public let risk: ActionRisk
    public let policyChecks: [String]
    public let warnings: [String]
    public let summaryReason: String?

    public init(
        risk: ActionRisk,
        policyChecks: [String],
        warnings: [String],
        summaryReason: String?
    ) {
        self.risk = risk
        self.policyChecks = policyChecks
        self.warnings = warnings
        self.summaryReason = summaryReason
    }
}

public enum FileReadSensitivity {
    public static func assess(_ authorized: AuthorizedPath) -> FileReadSensitivityAssessment {
        let rules = PathSensitivityProfile.agenticConservative.matchedRules(
            for: authorized.path,
            type: .file
        )
        let strongest = PathSensitivityAction.strongest(rules.map(\.action))
        let risk: ActionRisk

        switch strongest {
        case .warn_only:
            risk = .observe
        case .suggest_deny:
            risk = .privileged
        case .require_deny:
            risk = .forbidden
        }

        let primaryRule = rules.max { $0.action.priority < $1.action.priority }
        return .init(
            risk: risk,
            policyChecks: rules.map { "path_sensitivity_rule:\($0.id)" },
            warnings: rules.map { "Path sensitivity: \($0.reason)" },
            summaryReason: strongest == .warn_only ? nil : primaryRule?.reason
        )
    }
}
