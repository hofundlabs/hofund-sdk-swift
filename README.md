# @hofund/sdk-swift

Swift SDK for the Hofund Intelligence Client Data Engine — placeholder.

Published package starts in P5 once Quittr iOS engineering coordinates an integration sprint. Until then, this directory is a placeholder so the monorepo shape is correct.

**Port contract:** the full implementation spec — wire endpoints, DTOs, retry/idempotency semantics, and the idiomatic Swift mapping (`actor HofundClient`, `Codable`, `URLSession`) — is in [`docs/P5-MOBILE-SDK-PORT.md`](../../docs/P5-MOBILE-SDK-PORT.md). It ports `@hofund/sdk-ts` v0.8.0 verbatim; implement from that doc, no need to reverse-engineer the TS source.
