// Error model (port contract §2). Swift enums can't subtype, so `consentMissing`
// is a sibling case of `api` (in sdk-ts it's a subclass) — `status`/`message` are
// exposed via computed properties for uniform handling.

import Foundation

public enum HofundError: Error {
    /// Any non-OK final response.
    case api(status: Int, message: String, body: JSONValue?)
    /// A 403 whose body carries `error == "consent_missing"`.
    case consentMissing(layer: ConsentLayer, subjectUserId: String, message: String, body: JSONValue?)
    /// The HTTP transport threw (DNS/TLS/socket). Always treated as retryable.
    case network(underlying: Error)
    /// Local argument validation failure (bad key, empty subject id, batch > 100).
    case invalidArgument(String)

    /// HTTP status for `api` / `consentMissing` (403); nil otherwise.
    public var status: Int? {
        switch self {
        case .api(let status, _, _): return status
        case .consentMissing: return 403
        case .network, .invalidArgument: return nil
        }
    }

    /// Human-readable message for any case.
    public var message: String {
        switch self {
        case .api(_, let message, _): return message
        case .consentMissing(_, _, let message, _): return message
        case .network(let underlying): return "network error: \(underlying)"
        case .invalidArgument(let message): return message
        }
    }
}

extension HofundError: LocalizedError {
    public var errorDescription: String? { message }
}
