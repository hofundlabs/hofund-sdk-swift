// Idempotency policy (port contract §1.5). One key per logical POST, reused across
// that call's retries so the server dedupes a retried write. GET/DELETE get no key.

import Foundation

/// Idempotency configuration. Pass `nil` as the client's idempotency config to omit
/// the `Idempotency-Key` header (the Swift equivalent of sdk-ts `idempotency: false`).
public struct IdempotencyConfig: Sendable {
    /// Per-call key generator. Defaults to a lowercased UUID v4.
    public var generator: @Sendable () -> String

    public init(generator: @escaping @Sendable () -> String = defaultUuidGenerator) {
        self.generator = generator
    }
}

/// Default key generator: a random UUID v4, lowercased (matches sdk-ts output shape).
public func defaultUuidGenerator() -> String {
    UUID().uuidString.lowercased()
}

struct ResolvedIdempotencyConfig {
    let enabled: Bool
    let generator: @Sendable () -> String
}

func resolveIdempotencyConfig(_ input: IdempotencyConfig?) -> ResolvedIdempotencyConfig {
    guard let input else {
        return ResolvedIdempotencyConfig(enabled: false, generator: defaultUuidGenerator)
    }
    return ResolvedIdempotencyConfig(enabled: true, generator: input.generator)
}
