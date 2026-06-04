// Parity fixtures (port contract §9.2 class d) — per-method request shape + response
// parsing via the mock transport.

import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HofundSDK

final class RequestShapeTests: XCTestCase {
    func testHealthCheck() async throws {
        let (client, mock) = try makeClient([.respond(200, HEALTH_BODY)])
        let res = try await client.healthCheck()
        let req = mock.requests[0]
        XCTAssertEqual(encodedPath(req), "/v1/health")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(TEST_KEY)")
        XCTAssertEqual(res.status, "ok")
        XCTAssertEqual(res.version, "1.0.0")
    }

    func testRecordConsent() async throws {
        let (client, mock) = try makeClient([.respond(200, CONSENT_BODY)])
        let rec = try await client.recordConsent(
            subjectUserId: "s1", layer: .care, accepted: true, version: "v1")
        let body = try bodyObject(mock.requests[0])
        XCTAssertEqual(encodedPath(mock.requests[0]), "/v1/consent")
        XCTAssertEqual(body["subject_user_id"]?.stringValue, "s1")
        XCTAssertEqual(body["layer"]?.stringValue, "care")
        XCTAssertEqual(body["accepted"]?.boolValue, true)
        XCTAssertEqual(body["version"]?.stringValue, "v1")
        XCTAssertNil(body["source"]) // omitted when nil
        XCTAssertEqual(rec.id, "c1")
        XCTAssertEqual(rec.layer, .care)
    }

    func testRecordChainEventDefaults() async throws {
        let (client, mock) = try makeClient([.respond(200, EVENT_ACK_BODY)])
        let ack = try await client.recordChainEvent(
            subjectUserId: "s1",
            occurredAt: "2026-01-01T00:00:00Z",
            chain: ChainPayload(trigger: "stress", urgeIntensity: 7.0))
        let body = try bodyObject(mock.requests[0])
        XCTAssertEqual(encodedPath(mock.requests[0]), "/v1/chain")
        XCTAssertEqual(body["protocol_version"]?.stringValue, "q-dpdp-v0.1")
        XCTAssertEqual(body["source"]?.stringValue, "user")
        let chain = body["chain"]?.objectValue
        XCTAssertEqual(chain?["trigger"]?.stringValue, "stress")
        XCTAssertEqual(chain?["urge_intensity"]?.doubleValue, 7.0)
        XCTAssertNil(chain?["location"]) // null fields omitted
        XCTAssertEqual(ack.id, "e1")
        XCTAssertEqual(ack.source, .user)
    }

    func testRecordEmaEvent() async throws {
        let (client, mock) = try makeClient([.respond(200, EVENT_ACK_BODY)])
        _ = try await client.recordEmaEvent(
            subjectUserId: "s1", occurredAt: "2026-01-01T00:00:00Z", ema: EmaPayload(stress: 0.4))
        let body = try bodyObject(mock.requests[0])
        XCTAssertEqual(encodedPath(mock.requests[0]), "/v1/ema")
        XCTAssertEqual(body["ema"]?.objectValue?["stress"]?.doubleValue, 0.4)
    }

    func testRecordEventPayloadKey() async throws {
        let (client, mock) = try makeClient([.respond(200, EVENT_ACK_BODY)])
        _ = try await client.recordEvent(
            subjectUserId: "s1", occurredAt: "2026-01-01T00:00:00Z",
            protocolVersion: "siteproof-v0.1", payload: ["job_id": "j1"])
        XCTAssertNotNil(try bodyObject(mock.requests.last!)["event"])

        _ = try await client.recordEvent(
            subjectUserId: "s1", occurredAt: "2026-01-01T00:00:00Z",
            protocolVersion: "q-dpdp-v0.1", payload: ["trigger": "t"])
        XCTAssertNotNil(try bodyObject(mock.requests.last!)["chain"])
    }

    func testRecordEventsBatchShape() async throws {
        let batchBody = #"{"count":1,"results":[{"index":0,"status":"created","event":{"id":"e1","occurred_at":"2026-01-01T00:00:00Z","protocol_version":"q-dpdp-v0.1","source":"user"}}]}"#
        let (client, mock) = try makeClient([.respond(200, batchBody)])
        let res = try await client.recordEvents([
            BatchEventInput(subjectUserId: "s1", occurredAt: "2026-01-01T00:00:00Z",
                            protocolVersion: "q-dpdp-v0.1", payload: ["trigger": "t"], idempotencyKey: "k1"),
            BatchEventInput(subjectUserId: "s2", occurredAt: "2026-01-01T00:00:00Z",
                            protocolVersion: "siteproof-v0.1", payload: ["job_id": "j1"]),
        ])
        XCTAssertEqual(encodedPath(mock.requests[0]), "/v1/events/batch")
        let events = try bodyObject(mock.requests[0])["events"]?.arrayValue
        XCTAssertEqual(events?.count, 2)
        let first = events?[0].objectValue
        XCTAssertEqual(first?["subject_user_id"]?.stringValue, "s1")
        XCTAssertNotNil(first?["chain"])
        XCTAssertEqual(first?["idempotency_key"]?.stringValue, "k1")
        let second = events?[1].objectValue
        XCTAssertNotNil(second?["event"]) // siteproof payload key
        XCTAssertNil(second?["idempotency_key"])
        XCTAssertEqual(res.count, 1)
        if case .success = res.results[0] {} else { XCTFail("expected success result") }
    }

    func testRecordEventsEmptyShortCircuits() async throws {
        let (client, mock) = try makeClient()
        let res = try await client.recordEvents([])
        XCTAssertEqual(res.count, 0)
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testRecordEventsOver100Throws() async throws {
        let (client, mock) = try makeClient()
        let many = (1...101).map {
            BatchEventInput(subjectUserId: "s\($0)", occurredAt: "2026-01-01T00:00:00Z",
                            protocolVersion: "q-dpdp-v0.1", payload: [:])
        }
        let err = await assertThrows { try await client.recordEvents(many) }
        if case .invalidArgument? = err as? HofundError {} else { XCTFail("expected invalidArgument") }
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testListChainEventsURL() async throws {
        let listBody = #"{"events":[{"id":"e1","occurred_at":"2026-01-01T00:00:00Z","protocol_version":"q-dpdp-v0.1","source":"user","payload":{"k":"v"}}],"count":1,"next_cursor":"CURSOR"}"#
        let (client, mock) = try makeClient([.respond(200, listBody)])
        let res = try await client.listChainEvents(
            ListEventsInput(subjectUserId: "s1", from: "2026-01-01T00:00:00Z",
                            to: "2026-02-01T00:00:00Z", protocolVersion: "q-dpdp-v0.1", limit: 50, cursor: "C0"))
        let req = mock.requests[0]
        XCTAssertEqual(encodedPath(req), "/v1/subjects/s1/chain")
        XCTAssertEqual(queryValue(req, "from"), "2026-01-01T00:00:00Z")
        XCTAssertEqual(queryValue(req, "to"), "2026-02-01T00:00:00Z")
        XCTAssertEqual(queryValue(req, "protocol_version"), "q-dpdp-v0.1")
        XCTAssertEqual(queryValue(req, "limit"), "50")
        XCTAssertEqual(queryValue(req, "cursor"), "C0")
        XCTAssertEqual(res.count, 1)
        XCTAssertEqual(res.nextCursor, "CURSOR")
        XCTAssertEqual(res.events[0].payload["k"]?.stringValue, "v")
    }

    func testListEmaEventsRoute() async throws {
        let (client, mock) = try makeClient([.respond(200, #"{"events":[],"count":0,"next_cursor":null}"#)])
        _ = try await client.listEmaEvents(ListEventsInput(subjectUserId: "s1"))
        XCTAssertEqual(encodedPath(mock.requests[0]), "/v1/subjects/s1/ema")
    }

    func testListRejectsEmptySubject() async throws {
        let (client, _) = try makeClient()
        let err = await assertThrows { try await client.listChainEvents(ListEventsInput(subjectUserId: "")) }
        if case .invalidArgument? = err as? HofundError {} else { XCTFail("expected invalidArgument") }
    }

    func testDeleteSubjectEncodedIdAndBody() async throws {
        let delBody = #"{"subject_user_id":"a/b","ledger_id":"l1","deleted_at":"2026-01-01T00:00:00Z","deleted":{"chain_events":2,"ema_events":1,"consent_records":1,"insight_delivery_log":0}}"#
        let (client, mock) = try makeClient([.respond(200, delBody)])
        let res = try await client.deleteSubject(subjectUserId: "a/b", reason: "user_request", requestId: "ticket-9")
        let req = mock.requests[0]
        XCTAssertEqual(req.httpMethod, "DELETE")
        XCTAssertEqual(encodedPath(req), "/v1/subjects/a%2Fb")
        let body = try bodyObject(req)
        XCTAssertEqual(body["reason"]?.stringValue, "user_request")
        XCTAssertEqual(body["request_id"]?.stringValue, "ticket-9")
        XCTAssertEqual(res.deleted.chainEvents, 2)
        XCTAssertEqual(res.ledgerId, "l1")
    }

    func testDeleteSubjectNoBody() async throws {
        let delBody = #"{"subject_user_id":"s1","ledger_id":"l1","deleted_at":"x","deleted":{"chain_events":0,"ema_events":0,"consent_records":0,"insight_delivery_log":0}}"#
        let (client, mock) = try makeClient([.respond(200, delBody)])
        _ = try await client.deleteSubject(subjectUserId: "s1")
        XCTAssertNil(mock.requests[0].httpBody)
    }

    func testDeleteSubjectRejectsEmpty() async throws {
        let (client, _) = try makeClient()
        let err = await assertThrows { try await client.deleteSubject(subjectUserId: "") }
        if case .invalidArgument? = err as? HofundError {} else { XCTFail("expected invalidArgument") }
    }
}
