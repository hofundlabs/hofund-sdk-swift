// Parity fixtures (port contract §9.2 class e) — error mapping.

import XCTest
@testable import HofundSDK

final class ErrorMappingTests: XCTestCase {
    func testNonOKThrowsApiErrorWithStatusAndMessage() async throws {
        let (client, _) = try makeClient([.respond(400, #"{"error":"bad input"}"#)])
        let err = await assertThrows {
            _ = try await client.recordConsent(subjectUserId: "s1", layer: .care, accepted: true, version: "v1")
        }
        guard case .api(let status, let message, _)? = err as? HofundError else { return XCTFail("expected api") }
        XCTAssertEqual(status, 400)
        XCTAssertEqual(message, "bad input")
    }

    func testMessageFallback() async throws {
        let (client, _) = try makeClient([.respond(400, #"{"message":"detailed"}"#)])
        let err = await assertThrows { _ = try await client.healthCheck() }
        guard case .api(_, let message, _)? = err as? HofundError else { return XCTFail("expected api") }
        XCTAssertEqual(message, "detailed")
    }

    func testConsentMissingMapping() async throws {
        let body = #"{"error":"consent_missing","layer":"care","subject_user_id":"s9","message":"subject has not granted care"}"#
        let (client, _) = try makeClient([.respond(403, body)])
        let err = await assertThrows {
            _ = try await client.recordChainEvent(
                subjectUserId: "s9", occurredAt: "2026-01-01T00:00:00Z", chain: ChainPayload(trigger: "t"))
        }
        guard case .consentMissing(let layer, let subject, let message, _)? = err as? HofundError else {
            return XCTFail("expected consentMissing")
        }
        XCTAssertEqual(layer, .care)
        XCTAssertEqual(subject, "s9")
        XCTAssertEqual(message, "subject has not granted care")
        XCTAssertEqual((err as? HofundError)?.status, 403)
    }

    func testPlain403StaysApiError() async throws {
        let (client, _) = try makeClient([.respond(403, #"{"error":"forbidden"}"#)])
        let err = await assertThrows { _ = try await client.healthCheck() }
        guard case .api(let status, _, _)? = err as? HofundError else { return XCTFail("expected api") }
        XCTAssertEqual(status, 403)
    }
}
