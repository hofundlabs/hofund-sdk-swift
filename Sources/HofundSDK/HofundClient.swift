// HofundSDK — Swift port of the Hofund Mirror client.
//
// Wire-compatible with @hofund/sdk-ts (CONTRACT_VERSION). An `actor` so a single
// instance is safe to share across tasks. Retry + idempotency are hand-rolled in
// `request()` (not delegated) so the dedupe contract matches sdk-ts exactly.
//
// Docs: https://sdk.hofundlabs.com/docs

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HofundClientConfig: Sendable {
    /// Tenant API key, format hfk_<mode>_<key_id>_<secret>. Required.
    public var apiKey: String
    /// Base URL for the SDK API. Trailing slashes are stripped.
    public var baseURL: String
    /// Retry policy. `nil` disables (single attempt). Default: 3 attempts, full-jitter.
    public var retry: RetryConfig?
    /// Idempotency policy. `nil` omits the header. Default: enabled (UUID v4).
    public var idempotency: IdempotencyConfig?
    /// HTTP transport. Defaults to URLSession; inject a mock for tests.
    public var transport: any HTTPTransport
    /// Jitter source for retry backoff. Injectable for deterministic tests.
    public var randomGenerator: @Sendable () -> Double

    public init(
        apiKey: String,
        baseURL: String = "https://sdk.hofundlabs.com",
        retry: RetryConfig? = RetryConfig(),
        idempotency: IdempotencyConfig? = IdempotencyConfig(),
        transport: any HTTPTransport = URLSessionTransport(),
        randomGenerator: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.retry = retry
        self.idempotency = idempotency
        self.transport = transport
        self.randomGenerator = randomGenerator
    }
}

public actor HofundClient {
    private let apiKey: String
    private let baseURL: String
    private let transport: any HTTPTransport
    private let retry: ResolvedRetryConfig
    private let idempotency: ResolvedIdempotencyConfig
    private let randomGenerator: @Sendable () -> Double
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Construct a client. Throws `HofundError.invalidArgument` if the API key is
    /// missing or malformed (fail fast — never make a request with a bad key).
    public init(config: HofundClientConfig) throws {
        guard !config.apiKey.isEmpty else {
            throw HofundError.invalidArgument("createHofundClient: apiKey is required")
        }
        guard HofundClient.isValidKey(config.apiKey) else {
            throw HofundError.invalidArgument(
                "createHofundClient: apiKey malformed (expected hfk_<live|test>_<16chars>_<32chars>)")
        }
        self.apiKey = config.apiKey
        self.baseURL = HofundClient.trimTrailingSlashes(config.baseURL)
        self.transport = config.transport
        self.retry = resolveRetryConfig(config.retry)
        self.idempotency = resolveIdempotencyConfig(config.idempotency)
        self.randomGenerator = config.randomGenerator
    }

    // MARK: - Transport

    private func request<T: Decodable>(_ method: String, _ path: String, body: Data?) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw HofundError.invalidArgument("invalid URL path: \(path)")
        }

        // One idempotency key per logical POST, reused across retries so the server
        // dedupes a retried write. GET/DELETE get none.
        let idempotencyKey = (method == "POST" && idempotency.enabled) ? idempotency.generator() : nil

        var lastError: Error?
        for attempt in 1...retry.attempts {
            if attempt > 1 {
                let delayMs = computeBackoffDelay(attempt: attempt, config: retry, rand: randomGenerator)
                if delayMs > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                }
            }

            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            if let idempotencyKey {
                req.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
            }
            if let body {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
            }

            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(req)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                lastError = HofundError.network(underlying: error)
                if attempt < retry.attempts { continue } else { throw lastError! }
            }

            let status = response.statusCode
            let ok = (200...299).contains(status)

            if !ok && retryableStatuses.contains(status) && attempt < retry.attempts {
                lastError = HofundError.api(
                    status: status,
                    message: "Hofund API \(method) \(path) transient error: \(status)",
                    body: nil)
                continue
            }

            if !ok {
                throw mapError(method: method, path: path, status: status, data: data)
            }
            return try decoder.decode(T.self, from: data)
        }

        throw lastError ?? HofundError.api(status: 0, message: "Hofund SDK: request exhausted", body: nil)
    }

    private func mapError(method: String, path: String, status: Int, data: Data) -> HofundError {
        let body = try? decoder.decode(JSONValue.self, from: data)
        var errorStr: String?
        var messageStr: String?
        var layer: ConsentLayer?
        var subject: String?
        if case .object(let obj)? = body {
            if case .string(let e)? = obj["error"] { errorStr = e }
            if case .string(let m)? = obj["message"] { messageStr = m }
            if case .string(let l)? = obj["layer"] { layer = ConsentLayer(rawValue: l) }
            if case .string(let s)? = obj["subject_user_id"] { subject = s }
        }

        if status == 403 && errorStr == "consent_missing" {
            return .consentMissing(
                layer: layer ?? .care,
                subjectUserId: subject ?? "",
                message: messageStr ?? "consent_missing",
                body: body)
        }

        let message = errorStr ?? messageStr ?? "Hofund API \(method) \(path) failed: \(status)"
        return .api(status: status, message: message, body: body)
    }

    // MARK: - Methods

    public func healthCheck() async throws -> HealthCheckResponse {
        try await request("GET", "/v1/health", body: nil)
    }

    public func recordConsent(
        subjectUserId: String,
        layer: ConsentLayer,
        accepted: Bool,
        version: String,
        source: String? = nil
    ) async throws -> ConsentRecord {
        let body = try encoder.encode(
            ConsentRequest(subjectUserId: subjectUserId, layer: layer, accepted: accepted, version: version, source: source))
        let wrapper: ConsentRecordWrapper = try await request("POST", "/v1/consent", body: body)
        return wrapper.record
    }

    public func listConsent(subjectUserId: String) async throws -> [ConsentRecord] {
        var comps = URLComponents()
        comps.queryItems = [URLQueryItem(name: "subject_user_id", value: subjectUserId)]
        let path = "/v1/consent?\(comps.percentEncodedQuery ?? "")"
        let wrapper: ConsentListWrapper = try await request("GET", path, body: nil)
        return wrapper.records
    }

    public func recordChainEvent(
        subjectUserId: String,
        occurredAt: String,
        chain: ChainPayload,
        protocolVersion: String? = nil,
        source: EventSource? = nil
    ) async throws -> EventAck {
        let body = try encoder.encode(
            ChainEventRequest(
                subjectUserId: subjectUserId,
                occurredAt: occurredAt,
                protocolVersion: protocolVersion ?? DEFAULT_PROTOCOL_VERSION,
                source: source ?? .user,
                chain: chain))
        let wrapper: EventAckWrapper = try await request("POST", "/v1/chain", body: body)
        return wrapper.event
    }

    public func recordEmaEvent(
        subjectUserId: String,
        occurredAt: String,
        ema: EmaPayload,
        protocolVersion: String? = nil,
        source: EventSource? = nil
    ) async throws -> EventAck {
        let body = try encoder.encode(
            EmaEventRequest(
                subjectUserId: subjectUserId,
                occurredAt: occurredAt,
                protocolVersion: protocolVersion ?? DEFAULT_PROTOCOL_VERSION,
                source: source ?? .user,
                ema: ema))
        let wrapper: EventAckWrapper = try await request("POST", "/v1/ema", body: body)
        return wrapper.event
    }

    public func recordEvent(
        subjectUserId: String,
        occurredAt: String,
        protocolVersion: String,
        payload: [String: JSONValue],
        source: EventSource? = nil
    ) async throws -> EventAck {
        let payloadKey = payloadKeyForProtocol(protocolVersion)
        let obj: [String: JSONValue] = [
            "subject_user_id": .string(subjectUserId),
            "occurred_at": .string(occurredAt),
            "protocol_version": .string(protocolVersion),
            "source": .string((source ?? .user).rawValue),
            payloadKey: .object(payload),
        ]
        let body = try encoder.encode(obj)
        let wrapper: EventAckWrapper = try await request("POST", "/v1/chain", body: body)
        return wrapper.event
    }

    public func recordEvents(_ events: [BatchEventInput]) async throws -> BatchResponse {
        if events.isEmpty { return BatchResponse(count: 0, results: []) }
        if events.count > 100 {
            throw HofundError.invalidArgument(
                "recordEvents: max 100 events per call (got \(events.count)). Chunk before calling.")
        }
        var items: [JSONValue] = []
        for e in events {
            var item: [String: JSONValue] = [
                "subject_user_id": .string(e.subjectUserId),
                "occurred_at": .string(e.occurredAt),
                "protocol_version": .string(e.protocolVersion),
                "source": .string(e.source.rawValue),
                payloadKeyForProtocol(e.protocolVersion): .object(e.payload),
            ]
            if let k = e.idempotencyKey { item["idempotency_key"] = .string(k) }
            items.append(.object(item))
        }
        let envelope: [String: JSONValue] = ["events": .array(items)]
        let body = try encoder.encode(envelope)
        return try await request("POST", "/v1/events/batch", body: body)
    }

    public func listChainEvents(_ input: ListEventsInput) async throws -> ListEventsResponse {
        try await listEvents(table: "chain", input: input)
    }

    public func listEmaEvents(_ input: ListEventsInput) async throws -> ListEventsResponse {
        try await listEvents(table: "ema", input: input)
    }

    private func listEvents(table: String, input: ListEventsInput) async throws -> ListEventsResponse {
        guard !input.subjectUserId.isEmpty else {
            let name = table == "chain" ? "listChainEvents" : "listEmaEvents"
            throw HofundError.invalidArgument("\(name): subjectUserId is required")
        }
        var path = "/v1/subjects/\(encodePathComponent(input.subjectUserId))/\(table)"
        var items: [URLQueryItem] = []
        if let v = input.from { items.append(URLQueryItem(name: "from", value: v)) }
        if let v = input.to { items.append(URLQueryItem(name: "to", value: v)) }
        if let v = input.protocolVersion { items.append(URLQueryItem(name: "protocol_version", value: v)) }
        if let v = input.limit { items.append(URLQueryItem(name: "limit", value: String(v))) }
        if let v = input.cursor { items.append(URLQueryItem(name: "cursor", value: v)) }
        if !items.isEmpty {
            var comps = URLComponents()
            comps.queryItems = items
            if let q = comps.percentEncodedQuery { path += "?\(q)" }
        }
        return try await request("GET", path, body: nil)
    }

    public func deleteSubject(
        subjectUserId: String,
        reason: String? = nil,
        requestId: String? = nil
    ) async throws -> DeleteSubjectResponse {
        guard !subjectUserId.isEmpty else {
            throw HofundError.invalidArgument("deleteSubject: subjectUserId is required")
        }
        var body: Data?
        if reason != nil || requestId != nil {
            body = try encoder.encode(DeleteSubjectRequest(reason: reason, requestId: requestId))
        }
        let path = "/v1/subjects/\(encodePathComponent(subjectUserId))"
        return try await request("DELETE", path, body: body)
    }

    // MARK: - Helpers

    private func encodePathComponent(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: HofundClient.pathAllowed) ?? s
    }

    private static let pathAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func trimTrailingSlashes(_ s: String) -> String {
        var r = s
        while r.hasSuffix("/") { r.removeLast() }
        return r
    }

    private static func isValidKey(_ key: String) -> Bool {
        let pattern = "^hfk_(live|test)_[a-z0-9]{16}_[a-z0-9]{32}$"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(key.startIndex..<key.endIndex, in: key)
        return re.firstMatch(in: key, options: [], range: range) != nil
    }
}

/// Convenience factory mirroring sdk-ts `createHofundClient`. Throws on a bad key.
public func createHofundClient(_ config: HofundClientConfig) throws -> HofundClient {
    try HofundClient(config: config)
}
