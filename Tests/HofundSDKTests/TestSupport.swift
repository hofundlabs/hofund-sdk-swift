import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HofundSDK

// Same synthetic fixture convention as sdk-ts index.test.ts (not a real key).
let TEST_KEY = "hfk_test_abcdefghijklmnop_abcdefghijklmnopqrstuvwxyz012345"

/// A transport that replays scripted steps in order (reusing the last once exhausted)
/// and records every request. Serial test usage → `@unchecked Sendable` is safe.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    enum Step {
        case respond(Int, String)
        case fail(Error)
    }

    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let step = steps.count > 1 ? steps.removeFirst() : steps[0]
        switch step {
        case .fail(let error):
            throw error
        case .respond(let status, let body):
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            return (Data(body.utf8), http)
        }
    }
}

func makeClient(
    _ steps: [MockTransport.Step] = [.respond(200, "{}")],
    retry: RetryConfig? = RetryConfig(baseDelayMs: 0),
    idempotency: IdempotencyConfig? = IdempotencyConfig()
) throws -> (HofundClient, MockTransport) {
    let mock = MockTransport(steps)
    let client = try HofundClient(
        config: HofundClientConfig(apiKey: TEST_KEY, retry: retry, idempotency: idempotency, transport: mock))
    return (client, mock)
}

/// Run `body`, fail if it does not throw, and return the thrown error for inspection.
@discardableResult
func assertThrows<T>(
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> T
) async -> Error? {
    do {
        _ = try await body()
        XCTFail("expected an error to be thrown", file: file, line: line)
        return nil
    } catch {
        return error
    }
}

// MARK: - Request inspection helpers

func encodedPath(_ req: URLRequest) -> String {
    URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
}

func queryValue(_ req: URLRequest, _ name: String) -> String? {
    URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == name })?.value
}

func bodyObject(_ req: URLRequest) throws -> [String: JSONValue] {
    let data = req.httpBody ?? Data()
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    return value.objectValue ?? [:]
}

func idempotencyHeader(_ req: URLRequest) -> String? {
    req.value(forHTTPHeaderField: "Idempotency-Key")
}

// MARK: - JSONValue accessors (tests only)

extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var intValue: Int? {
        if case .integer(let i) = self { return i }
        return nil
    }
    var doubleValue: Double? {
        switch self {
        case .number(let d): return d
        case .integer(let i): return Double(i)
        default: return nil
        }
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

// Canned response bodies.
let HEALTH_BODY = #"{"status":"ok","version":"1.0.0","timestamp":"2026-01-01T00:00:00Z"}"#
let CONSENT_BODY = #"{"record":{"id":"c1","layer":"care","accepted":true,"version":"v1","accepted_at":"2026-01-01T00:00:00Z","revoked_at":null}}"#
let EVENT_ACK_BODY = #"{"event":{"id":"e1","occurred_at":"2026-01-01T00:00:00Z","protocol_version":"q-dpdp-v0.1","source":"user"}}"#
