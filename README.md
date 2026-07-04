# HofundSDK (sdk-swift)

Swift SDK for the **Hofund Mirror** platform — consent ledger + behavioral/operational
event ingestion. A native port of [`@hofundlabs/sdk-ts`](../sdk-ts), wire-compatible with
**contract version 0.8.0** (`CONTRACT_VERSION`).

> Targets the **Hofund Mirror** API (`https://sdk.hofundlabs.com`) — the first-party
> consent/telemetry path. It is **not** a client for the Quittr engine REST API; native
> apps call that directly. See [`docs/P5-MOBILE-SDK-PORT.md`](../../docs/P5-MOBILE-SDK-PORT.md) §0.

## Status

P5a–P5d implemented (scaffolding → transport → all 11 methods → mobile ergonomics).
SwiftPM, `Foundation` + `URLSession` only (no third-party deps). `async`/`await`,
min iOS 15 / macOS 12. Verified by the `sdk-swift` CI job (ubuntu + `swift test`);
no Swift toolchain on the authoring machine, so CI is the build gate.

## Install (Swift Package Manager)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/hofundlabs/hofundlabs_sdk", from: "0.8.0"),
],
// then add product "HofundSDK" to your target's dependencies
```

(Published-package coordinates TBD; today it builds from the monorepo path
`packages/sdk-swift`.)

## Usage

```swift
import HofundSDK

let client = try HofundClient(
    config: HofundClientConfig(apiKey: "hfk_test_xxxxxxxxxxxxxxxx_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"))

// Consent must be granted before ingestion (care layer gates chain + ema).
_ = try await client.recordConsent(
    subjectUserId: "subject-123", layer: .care, accepted: true, version: "2026-01")

// Record a behavioral chain event.
let ack = try await client.recordChainEvent(
    subjectUserId: "subject-123",
    occurredAt: "2026-06-03T18:00:00Z",
    chain: ChainPayload(trigger: "stress", urgeIntensity: 7.0, outcome: "interrupted"))

// Offline-queue flush: batch up to 100 events with per-item idempotency keys.
let batch = try await client.recordEvents([
    BatchEventInput(
        subjectUserId: "subject-123",
        occurredAt: "2026-06-03T18:05:00Z",
        protocolVersion: "q-dpdp-v0.1",
        payload: ["trigger": "boredom"],
        idempotencyKey: "local-event-42"),
])
```

### Errors

`HofundClient(config:)` throws `HofundError.invalidArgument` for a missing/malformed key.
Requests throw `HofundError`:

- `.consentMissing(layer:subjectUserId:message:body:)` — a `403` meaning the subject
  hasn't granted the required layer. Not a bug; surface it, don't retry.
- `.api(status:message:body:)` — any other non-OK response.
- `.network(underlying:)` — transport failure; always retried.

### Retry & idempotency

Defaults: 3 attempts with full-jitter exponential backoff on network errors + `408/425/429/5xx`;
never on `400/401/403`. Each POST carries one `Idempotency-Key` reused across its retries so the
server dedupes. Disable via `HofundClientConfig(retry: nil)` / `idempotency: nil`.

## Build & test

```bash
cd packages/sdk-swift
swift test
```

Tests use an injected `MockTransport` (no network) and are **golden-fixture parity tests**
mirroring the `@hofundlabs/sdk-ts` unit tests — they assert the emitted request JSON, backoff
math, `payloadKeyForProtocol`, idempotency-key reuse, and error mapping all match the TS
reference. The transport seam is `HTTPTransport`; the default is `URLSessionTransport`.

## Parity contract

`sdk-ts`, `sdk-kotlin`, and `sdk-swift` are three implementations of one wire contract.
Any change to the TS surface updates [`docs/P5-MOBILE-SDK-PORT.md`](../../docs/P5-MOBILE-SDK-PORT.md)
and the native ports together. This port pins `CONTRACT_VERSION = "0.8.0"`.
