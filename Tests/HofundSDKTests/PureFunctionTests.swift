// Parity fixtures (port contract §9.2 classes a, b, c) — pure helpers, no HTTP.

import XCTest
@testable import HofundSDK

final class PureFunctionTests: XCTestCase {
    // MARK: (a) key validation

    func testRejectsEmptyApiKey() {
        do {
            _ = try HofundClient(config: HofundClientConfig(apiKey: ""))
            XCTFail("expected throw")
        } catch let e as HofundError {
            if case .invalidArgument = e {} else { XCTFail("wrong case") }
        } catch { XCTFail("wrong error") }
    }

    func testRejectsMalformedApiKey() {
        let bad = [
            "nope",
            "hfk_live_short_short",
            "hfk_prod_abcdefghijklmnop_abcdefghijklmnopqrstuvwxyz012345",
        ]
        for key in bad {
            XCTAssertThrowsError(try HofundClient(config: HofundClientConfig(apiKey: key)), key)
        }
    }

    func testAcceptsWellFormedApiKey() throws {
        _ = try HofundClient(config: HofundClientConfig(apiKey: TEST_KEY))
        _ = try HofundClient(
            config: HofundClientConfig(apiKey: "hfk_live_abcdefghijklmnop_abcdefghijklmnopqrstuvwxyz012345"))
    }

    func testContractVersionPin() {
        XCTAssertEqual(CONTRACT_VERSION, "0.8.0")
    }

    // MARK: (b) retry config + backoff math

    func testResolveRetryNilIsSingleAttempt() {
        let r = resolveRetryConfig(nil)
        XCTAssertEqual(r.attempts, 1)
        XCTAssertEqual(r.baseDelayMs, 0)
        XCTAssertEqual(r.maxDelayMs, 0)
    }

    func testResolveRetryDefaults() {
        XCTAssertEqual(resolveRetryConfig(RetryConfig()).attempts, 3)
    }

    func testResolveRetryClampsAttempts() {
        XCTAssertEqual(resolveRetryConfig(RetryConfig(attempts: 0)).attempts, 1)
        XCTAssertEqual(resolveRetryConfig(RetryConfig(attempts: -5)).attempts, 1)
    }

    func testBackoffFirstAttemptIsZero() {
        XCTAssertEqual(computeBackoffDelay(attempt: 1, config: resolveRetryConfig(RetryConfig()), rand: { 1.0 }), 0)
    }

    func testBackoffFullJitterRespectsCap() {
        let cfg = resolveRetryConfig(RetryConfig(baseDelayMs: 250, maxDelayMs: 4000))
        XCTAssertEqual(computeBackoffDelay(attempt: 2, config: cfg, rand: { 1.0 }), 250)
        XCTAssertEqual(computeBackoffDelay(attempt: 3, config: cfg, rand: { 1.0 }), 500)
        XCTAssertEqual(computeBackoffDelay(attempt: 4, config: cfg, rand: { 1.0 }), 1000)
        XCTAssertEqual(computeBackoffDelay(attempt: 10, config: cfg, rand: { 1.0 }), 4000) // capped
        XCTAssertEqual(computeBackoffDelay(attempt: 5, config: cfg, rand: { 0.0 }), 0) // jitter floor
        let d = computeBackoffDelay(attempt: 3, config: cfg, rand: { 0.5 })
        XCTAssertTrue(d >= 0 && d <= 500)
    }

    func testRetryableStatusSet() {
        XCTAssertEqual(retryableStatuses, [408, 425, 429, 500, 502, 503, 504])
        for s in [400, 401, 403, 404, 200] {
            XCTAssertFalse(retryableStatuses.contains(s))
        }
    }

    // MARK: (c) protocol payload key

    func testPayloadKeySiteproof() {
        XCTAssertEqual(payloadKeyForProtocol("siteproof-v0.1"), "event")
        XCTAssertEqual(payloadKeyForProtocol("siteproof-v9.9"), "event")
    }

    func testPayloadKeyDefault() {
        XCTAssertEqual(payloadKeyForProtocol("q-dpdp-v0.1"), "chain")
        XCTAssertEqual(payloadKeyForProtocol("something-else"), "chain")
    }

    // MARK: idempotency helpers

    func testDefaultUuidGenerator() {
        let u = defaultUuidGenerator()
        let re = try! NSRegularExpression(
            pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        XCTAssertNotNil(re.firstMatch(in: u, range: NSRange(u.startIndex..<u.endIndex, in: u)), u)
        XCTAssertNotEqual(defaultUuidGenerator(), defaultUuidGenerator())
    }

    func testResolveIdempotency() {
        XCTAssertFalse(resolveIdempotencyConfig(nil).enabled)
        XCTAssertTrue(resolveIdempotencyConfig(IdempotencyConfig()).enabled)
    }
}
