// Retry policy (port contract §1.4). The exact status set and full-jitter backoff
// math must match sdk-ts so the server's idempotency dedupe lines up.

import Foundation

/// Retry configuration. Pass `nil` as the client's retry config to disable retries
/// (single attempt, no delay) — the Swift equivalent of sdk-ts `retry: false`.
public struct RetryConfig: Sendable {
    /// Total attempts including the first try. Default 3. Clamped to ≥ 1.
    public var attempts: Int
    /// Base delay in ms for exponential backoff with full jitter. Default 250.
    public var baseDelayMs: Int
    /// Hard ceiling for any single backoff delay. Default 4000.
    public var maxDelayMs: Int

    public init(attempts: Int = 3, baseDelayMs: Int = 250, maxDelayMs: Int = 4000) {
        self.attempts = attempts
        self.baseDelayMs = baseDelayMs
        self.maxDelayMs = maxDelayMs
    }
}

struct ResolvedRetryConfig {
    let attempts: Int
    let baseDelayMs: Int
    let maxDelayMs: Int
}

/// `nil` → a single attempt with no delay; otherwise clamp each field to its floor.
func resolveRetryConfig(_ input: RetryConfig?) -> ResolvedRetryConfig {
    guard let input else {
        return ResolvedRetryConfig(attempts: 1, baseDelayMs: 0, maxDelayMs: 0)
    }
    return ResolvedRetryConfig(
        attempts: max(1, input.attempts),
        baseDelayMs: max(0, input.baseDelayMs),
        maxDelayMs: max(0, input.maxDelayMs)
    )
}

/// Full-jitter exponential backoff. Returns the wait in ms *before* attempt N (N ≥ 2);
/// attempt 1 always waits 0. Equivalent to sdk-ts `computeBackoffDelay`:
/// `floor(rand() * min(base * 2^(attempt-2), max))`. `rand` is injectable for tests.
func computeBackoffDelay(
    attempt: Int,
    config: ResolvedRetryConfig,
    rand: () -> Double
) -> Int {
    if attempt <= 1 { return 0 }
    let exp = Double(config.baseDelayMs) * pow(2.0, Double(attempt - 2))
    let capped = min(exp, Double(config.maxDelayMs))
    return Int((rand() * capped).rounded(.down))
}

/// HTTP statuses the SDK retries by default: 408, 425, 429, 500, 502, 503, 504.
/// 400/401/403 are programmer/auth errors and are never retried.
public let retryableStatuses: Set<Int> = [408, 425, 429, 500, 502, 503, 504]
