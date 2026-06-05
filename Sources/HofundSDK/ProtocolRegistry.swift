// Maps a protocol_version to the body key its server-side validator expects.
// Keep in sync with PROTOCOL_REGISTRY in apps/web/src/lib/event-validators.ts and
// payloadKeyForProtocol in @hofundlabs/sdk-ts (port contract §1.6).

import Foundation

public func payloadKeyForProtocol(_ protocolVersion: String) -> String {
    protocolVersion.hasPrefix("siteproof-") ? "event" : "chain"
}

/// Default protocol used by recordChainEvent / recordEmaEvent when omitted.
public let DEFAULT_PROTOCOL_VERSION = "q-dpdp-v0.1"

/// The sdk-ts contract version this port targets (parity pin, port contract §9.1).
public let CONTRACT_VERSION = "0.8.0"
