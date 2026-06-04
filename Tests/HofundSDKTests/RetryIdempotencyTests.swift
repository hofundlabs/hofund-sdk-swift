// Parity fixtures — retry behavior + idempotency-key header semantics.

import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HofundSDK

final class RetryIdempotencyTests: XCTestCase {
    func testPostIncludesIdempotencyKey() async throws {
        let (client, mock) = try makeClient([.respond(200, CONSENT_BODY)])
        _ = try await client.recordConsent(subjectUserId: "s1", layer: .care, accepted: true, version: "v1")
        XCTAssertNotNil(idempotencyHeader(mock.requests[0]))
    }

    func testGetHasNoIdempotencyKey() async throws {
        let (client, mock) = try makeClient([.respond(200, HEALTH_BODY)])
        _ = try await client.healthCheck()
        XCTAssertNil(idempotencyHeader(mock.requests[0]))
    }

    func testDeleteHasNoIdempotencyKey() async throws {
        let delBody = #"{"subject_user_id":"s1","ledger_id":"l1","deleted_at":"x","deleted":{"chain_events":0,"ema_events":0,"consent_records":0,"insight_delivery_log":0}}"#
        let (client, mock) = try makeClient([.respond(200, delBody)])
        _ = try await client.deleteSubject(subjectUserId: "s1", reason: "r")
        XCTAssertNil(idempotencyHeader(mock.requests[0]))
    }

    func testIdempotencyNilDisables() async throws {
        let (client, mock) = try makeClient([.respond(200, CONSENT_BODY)], idempotency: nil)
        _ = try await client.recordConsent(subjectUserId: "s1", layer: .care, accepted: true, version: "v1")
        XCTAssertNil(idempotencyHeader(mock.requests[0]))
    }

    func testCustomIdempotencyGenerator() async throws {
        let (client, mock) = try makeClient(
            [.respond(200, CONSENT_BODY)],
            idempotency: IdempotencyConfig(generator: { "fixed-key-123" }))
        _ = try await client.recordConsent(subjectUserId: "s1", layer: .care, accepted: true, version: "v1")
        XCTAssertEqual(idempotencyHeader(mock.requests[0]), "fixed-key-123")
    }

    func testRetriesReuseSameKey() async throws {
        let (client, mock) = try makeClient([.respond(503, "{}"), .respond(200, CONSENT_BODY)])
        _ = try await client.recordConsent(subjectUserId: "s1", layer: .care, accepted: true, version: "v1")
        XCTAssertEqual(mock.requests.count, 2)
        let k0 = idempotencyHeader(mock.requests[0])
        XCTAssertNotNil(k0)
        XCTAssertEqual(k0, idempotencyHeader(mock.requests[1]))
    }

    func testTwoPostsDifferentKeys() async throws {
        let (client, mock) = try makeClient([.respond(200, CONSENT_BODY)])
        _ = try await client.recordConsent(subjectUserId: "s1", layer: .care, accepted: true, version: "v1")
        _ = try await client.recordConsent(subjectUserId: "s2", layer: .care, accepted: true, version: "v1")
        XCTAssertEqual(mock.requests.count, 2)
        XCTAssertNotEqual(idempotencyHeader(mock.requests[0]), idempotencyHeader(mock.requests[1]))
    }

    func testRetriesOn503ThenSucceeds() async throws {
        let (client, mock) = try makeClient([.respond(503, "{}"), .respond(200, HEALTH_BODY)])
        let res = try await client.healthCheck()
        XCTAssertEqual(res.status, "ok")
        XCTAssertEqual(mock.requests.count, 2)
    }

    func testDoesNotRetryOn401() async throws {
        let (client, mock) = try makeClient([.respond(401, #"{"error":"unauthorized"}"#)])
        let err = await assertThrows { _ = try await client.healthCheck() }
        guard case .api(let status, _, _)? = err as? HofundError else { return XCTFail("expected api error") }
        XCTAssertEqual(status, 401)
        XCTAssertEqual(mock.requests.count, 1)
    }

    func testRetryNilSingleAttemptOn503() async throws {
        let (client, mock) = try makeClient([.respond(503, "{}")], retry: nil)
        let err = await assertThrows { _ = try await client.healthCheck() }
        guard case .api(let status, _, _)? = err as? HofundError else { return XCTFail("expected api error") }
        XCTAssertEqual(status, 503)
        XCTAssertEqual(mock.requests.count, 1)
    }

    func testThreeConsecutive500s() async throws {
        let (client, mock) = try makeClient(
            [.respond(500, #"{"error":"boom"}"#)], retry: RetryConfig(attempts: 3, baseDelayMs: 0))
        let err = await assertThrows { _ = try await client.healthCheck() }
        guard case .api(let status, _, _)? = err as? HofundError else { return XCTFail("expected api error") }
        XCTAssertEqual(status, 500)
        XCTAssertEqual(mock.requests.count, 3)
    }

    func testNetworkErrorRetriesThenThrows() async throws {
        let (client, mock) = try makeClient(
            [.fail(URLError(.notConnectedToInternet))], retry: RetryConfig(attempts: 3, baseDelayMs: 0))
        let err = await assertThrows { _ = try await client.healthCheck() }
        if case .network? = err as? HofundError {} else { XCTFail("expected network error") }
        XCTAssertEqual(mock.requests.count, 3)
    }

    func testNetworkErrorRetriesThenSucceeds() async throws {
        let (client, mock) = try makeClient(
            [.fail(URLError(.timedOut)), .respond(200, HEALTH_BODY)],
            retry: RetryConfig(attempts: 3, baseDelayMs: 0))
        let res = try await client.healthCheck()
        XCTAssertEqual(res.status, "ok")
        XCTAssertEqual(mock.requests.count, 2)
    }
}
