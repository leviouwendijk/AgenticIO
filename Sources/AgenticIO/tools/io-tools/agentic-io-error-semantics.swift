import Errors
import Foundation
import Writers

// MARK: - Mutation results the agent acts on

extension MutateToolError: SemanticError, ErrorNamespaced, ErrorDispositionProviding {
    public static let errorNamespace = "agentic_io.mutate"

    public var errorCode: String {
        switch self {
        case .publication_failed: return "publication_failed"
        }
    }

    public var errorPresentation: ErrorPresentation {
        switch self {
        case .publication_failed(let status, let applied, let entries, let message, let recoveryRequired):
            var outcome = "\(applied) of \(entries) entries applied"
            switch status {
            case .rolled_back: outcome += ", then rolled back"
            case .failed: outcome += "; no entry completed"
            default: break
            }
            return .init(
                message: "Mutation pass \(status.rawValue): \(outcome).",
                reason: message,
                recoverySuggestion: recoveryRequired
                    ? "The failing change may have stopped halfway, so further changes are blocked. Inspect the failing target, then call io_tool_recover_mutations with what you found."
                    : "Nothing is blocked: fix the failing entry and run the pass again.",
                reasonSensitivity: .potentially_sensitive
            )
        }
    }

    public var errorDiagnosticFields: [ErrorDiagnosticField] {
        switch self {
        case .publication_failed(let status, let applied, let entries, _, let recoveryRequired):
            return [
                .init(key: "mutation.status", value: .string(status.rawValue)),
                .init(key: "mutation.applied", value: .integer(applied)),
                .init(key: "mutation.entries", value: .integer(entries)),
                .init(key: "mutation.recovery_required", value: .boolean(recoveryRequired)),
            ]
        }
    }

    public var errorDisposition: ErrorDisposition? {
        switch self {
        case .publication_failed(_, _, _, _, let recoveryRequired):
            // Blocked: someone must look before anything changes again.
            // Otherwise the failing entry decides; its text is the reason.
            return recoveryRequired ? .requires_access : nil
        }
    }
}

extension PreparedWritersPublicationError: SemanticError, ErrorNamespaced, ErrorDispositionProviding {
    public static let errorNamespace = "agentic_io.publication"

    public var errorCode: String {
        switch self {
        case .recovery_required: return "recovery_required"
        }
    }

    public var errorPresentation: ErrorPresentation {
        switch self {
        case .recovery_required(let cause, let canRequest):
            var reason = "An earlier"
            if let cause {
                reason += " \(cause.kind.rawValue) failed (\(cause.status))"
                if let target = cause.target {
                    reason += " at \(target.path)"
                }
                if let message = cause.message {
                    reason += ": \(message)"
                }
            } else {
                reason += " publication failed"
            }
            reason += ". Its effect on disk is uncertain."
            return .init(
                message: "File changes are blocked until a failed publication is recovered.",
                reason: reason,
                recoverySuggestion: canRequest
                    ? "Inspect that target, then call io_tool_recover_mutations with what you found; the operator reviews it."
                    : "Ask the operator to recover before making further changes.",
                reasonSensitivity: .potentially_sensitive
            )
        }
    }

    public var errorDiagnosticFields: [ErrorDiagnosticField] {
        switch self {
        case .recovery_required(let cause, let canRequest):
            var fields: [ErrorDiagnosticField] = [
                .init(key: "mutation.can_request_recovery", value: .boolean(canRequest)),
            ]
            if let cause {
                fields.append(.init(key: "mutation.blocked_by", value: .string(cause.kind.rawValue)))
                fields.append(.init(key: "mutation.publication", value: .string(cause.publication_id.uuidString)))
                fields.append(.init(key: "mutation.status", value: .string(cause.status)))
                if let target = cause.target {
                    fields.append(.init(key: .path, value: .string(target.path), sensitivity: .potentially_sensitive))
                }
            }
            return fields
        }
    }

    public var errorDisposition: ErrorDisposition? { .requires_access }
}

// MARK: - Refusals whose own text already reads well: identity and disposition

extension RecoverMutationsToolError: ErrorNamespaced, ErrorDispositionProviding {
    public static let errorNamespace = "agentic_io.recover_mutations"

    public var errorCode: String {
        switch self {
        case .not_coordinated: return "not_coordinated"
        case .not_granted: return "not_granted"
        case .nothing_to_recover: return "nothing_to_recover"
        }
    }

    public var errorDisposition: ErrorDisposition? {
        switch self {
        case .not_granted: return .requires_access
        case .not_coordinated, .nothing_to_recover: return .invalid_input
        }
    }
}

extension FileEditPolicyError: ErrorNamespaced, ErrorDispositionProviding {
    public static let errorNamespace = "agentic_io.edit_policy"

    public var errorCode: String {
        switch self {
        case .grant_required: return "grant_required"
        case .required_operation_missing: return "required_operation_missing"
        case .insertion_position_outside_grant: return "insertion_outside_grant"
        case .replacement_range_outside_grant: return "replacement_outside_grant"
        }
    }

    public var errorDisposition: ErrorDisposition? {
        switch self {
        case .required_operation_missing: return .invalid_input
        case .grant_required, .insertion_position_outside_grant, .replacement_range_outside_grant: return .requires_access
        }
    }
}

extension FileMutationOperationPolicyError: ErrorNamespaced, ErrorDispositionProviding {
    public static let errorNamespace = "agentic_io.operation_policy"

    public var errorCode: String {
        switch self {
        case .operation_not_allowed: return "operation_not_allowed"
        case .plan_entry_mismatch: return "plan_entry_mismatch"
        }
    }

    public var errorDisposition: ErrorDisposition? {
        switch self {
        case .operation_not_allowed: return .requires_access
        case .plan_entry_mismatch: return .invalid_input
        }
    }
}

extension RemoveToolError: ErrorNamespaced, ErrorDispositionProviding {
    public static let errorNamespace = "agentic_io.remove"

    public var errorCode: String {
        switch self {
        case .emptyInput: return "empty_input"
        case .missing: return "missing"
        case .notDirectory: return "not_directory"
        case .symbolicLink: return "symbolic_link"
        case .notEmpty: return "not_empty"
        }
    }

    public var errorDisposition: ErrorDisposition? { .invalid_input }
}

extension PredefinedFileToolError: ErrorNamespaced, ErrorDispositionProviding {
    static let errorNamespace = "agentic_io.tool_input"

    var errorCode: String {
        switch self {
        case .workspaceRequired: return "workspace_required"
        case .missingField: return "missing_field"
        case .invalidValue: return "invalid_value"
        }
    }

    var errorDisposition: ErrorDisposition? {
        switch self {
        case .workspaceRequired: return .requires_configuration
        case .missingField, .invalidValue: return .invalid_input
        }
    }
}
