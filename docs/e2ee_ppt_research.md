# WAMP E2EE / PPT Research

## Why This Exists

The repo already has the right message-layer hook for end-to-end payload protection:
`ppt_scheme = "wamp"`. What it does not have yet is an implementation. The
current `E2EEPayload` helper is still a stub, while the surrounding lazy-payload
and payload-passthru machinery is already in place.

The next prototype should therefore answer one narrow question first: how do we
add transport-neutral WAMP E2EE without breaking the existing lazy-payload and
zero-copy routing contract?

## Current Repo Baseline

- `packages/connectanum_core/lib/src/message/e2ee_payload.dart` is still a TODO.
- `packages/connectanum_core/lib/src/message/abstract_ppt_options.dart`
  already accepts `ppt_scheme = "wamp"`, but currently only with
  `ppt_serializer = "cbor"`. The upstream draft also mentions `flatbuffers`,
  but this repo does not support that serializer yet.
- `packages/connectanum_client/lib/src/protocol/session.dart` already routes
  outbound `ppt_scheme = "wamp"` payloads through `E2EEPayload.packE2EEPayload`
  and preserves already-packed lazy payload bytes when the serializer matches.
- `packages/connectanum_core/lib/src/message/abstract_message_with_payload.dart`
  already routes inbound `ppt_scheme = "wamp"` payloads through
  `E2EEPayload.unpackE2EEPayload`, and the surrounding `LazyMessagePayload`
  model can keep a packed binary payload opaque until materialization.
- The repo already depends on `pinenacl` and `pointycastle` for authentication
  work, but there is no E2EE-specific crypto path in either the Dart stack or
  the Rust native transport today.

## External References

- The current WAMP Internet-Draft says routers are trusted and can read or
  modify application payloads, so WAMP transport/session security does not by
  itself provide end-to-end payload confidentiality, authenticity, or integrity:
  <https://wamp-proto.org/wamp_latest_ietf.html>
- The same draft defines payload-passthru fields
  `ppt_scheme|ppt_serializer|ppt_cipher|ppt_keyid` across
  `CALL/PUBLISH/YIELD/INVOCATION/EVENT/RESULT/ERROR`, which makes PPT/E2EE a
  message-layer concern rather than a transport-specific concern:
  <https://wamp-proto.org/wamp_latest_ietf.html>
- For the predefined WAMP E2EE flow, the draft lists
  `ppt_scheme = "wamp"`, serializers `cbor|flatbuffers`, optional ciphers
  `xsalsa20poly1305|aes256gcm`, and an optional `ppt_keyid`:
  <https://wamp-proto.org/wamp_latest_ietf.html>
- The cryptosign authentication section uses `HELLO.authmethods` and
  `HELLO.authextra` for authentication keys and challenges, but that is still
  session-authentication machinery rather than a standardized E2EE key
  negotiation flow:
  <https://wamp-proto.org/wamp_latest_ietf.html>
- WAMP issue #81 captures the underlying trust problem plainly: routers are
  effectively man-in-the-middle entities unless payload protection is layered on
  top: <https://github.com/wamp-proto/wamp-proto/issues/81>
- WAMP issue #229 describes WAMP-cryptobox as an end-to-end application payload
  encryption scheme built on payload transparency and NaCl-style authenticated
  public-key encryption: <https://github.com/wamp-proto/wamp-proto/issues/229>
- WAMP issue #356 states that both WAMP-cryptobox and XBR already target
  end-to-end payload confidentiality/integrity, but the spec text is still not
  standardized and the current implementations are implementation-specific:
  <https://github.com/wamp-proto/wamp-proto/issues/356>
- WAMP issue #420 describes Crossbar global authenticators as an existing
  router-to-router trust optimization. That is relevant for future key
  distribution, but it is not required for a first transport-neutral payload
  prototype: <https://github.com/wamp-proto/wamp-proto/issues/420>

## Prototype Options

### Option A: Payload-Only Prototype With Out-of-Band Key Registry

- Applications provide a key lookup by `ppt_keyid`, peer identity, URI, or
  equivalent runtime context.
- No `HELLO`, `CHALLENGE`, `WELCOME`, or router-auth changes are required.
- Routers and transports remain opaque forwarders of ciphertext bytes plus
  `ppt_*` metadata.

Pros:

- Smallest possible prototype.
- Fully transport-neutral.
- Best fit for the existing lazy-payload contract.

Cons:

- No automatic key discovery or rotation.
- Application configuration has to carry more responsibility up front.

### Option B: Session-Establishment Key Advertisement

- Extend `HELLO.authextra` and `WELCOME` / `CHALLENGE` detail maps with
  encryption public keys or key descriptors.
- Let peers negotiate or announce usable E2EE keys during session setup.

Pros:

- Makes first-use discovery simpler.
- Keeps key metadata close to session establishment.

Cons:

- This is a protocol extension, not something standardized in the current draft.
- It tightly couples data encryption to authentication/session establishment.
- It complicates router interop before the core payload format is proven.

### Option C: Router-Assisted Key Distribution

- Remote authenticators or global-auth style flows return encryption-key
  descriptors, policy, or key IDs.
- Router-side auth infrastructure becomes the distribution plane for E2EE keys.

Pros:

- Operationally attractive in multi-router deployments.
- Gives deployments one place to manage rotation and policy.

Cons:

- Pulls the prototype into auth-system work immediately.
- Routers learn more metadata about payload-protection state.
- Larger scope than the current roadmap item needs.

## Recommended Phase 1

Implement Option A first.

### Scope

- `ppt_scheme = "wamp"`
- `ppt_serializer = "cbor"` only
- `ppt_cipher = "xsalsa20poly1305"` first
- Application-supplied E2EE provider/keyring on session/router config
- Dart-side pack/unpack only for the first prototype
- Router and native transport continue to forward opaque ciphertext bytes

### Why

- It matches the repo's current CBOR-only guard for WAMP PPT.
- It keeps the transport and router forwarding path unchanged.
- It preserves the current zero-copy and lazy-payload value proposition, since
  ciphertext remains a single packed binary payload.
- It avoids inventing a key-negotiation extension before the wire format and API
  surface are stable.

## Required Code-Shape Changes Before Implementation

The current static `E2EEPayload.packE2EEPayload(...)` and
`E2EEPayload.unpackE2EEPayload(...)` signatures do not have enough context to do
real encryption. They need access to at least:

- an outbound key selection policy
- an inbound key lookup
- the chosen cipher
- the chosen `ppt_keyid`
- peer or route context if key selection is not global

That means the first implementation should not hardcode crypto directly inside
the existing static helpers without introducing runtime context.

### Preferred Direction

Introduce a runtime E2EE provider abstraction at the client/router layer, and
keep `connectanum_core` focused on wire-shape validation and payload framing.

Reason:

- `connectanum_core` currently knows about payload encoding and message shape,
  but not about peers, identities, or key stores.
- Encryption decisions are runtime decisions, not pure serializer decisions.
- The client and router already own the relevant session/auth/peer context.

### Consequence

Undecryptable inbound `ppt_scheme = "wamp"` payloads should not silently decode
to empty args/kwargs. The runtime needs an explicit surface for:

- no provider configured
- `ppt_keyid` not found
- unsupported cipher
- authentication/decryption failure

The best fit is to keep ciphertext as an opaque lazy payload until a provider
chooses to decrypt it, rather than forcing immediate materialization.

## First Prototype Test Matrix

### Core / Client

- outbound `CALL` / `PUBLISH` with an E2EE provider emits:
  - one packed binary payload
  - `ppt_scheme = "wamp"`
  - `ppt_serializer = "cbor"`
  - `ppt_cipher = "xsalsa20poly1305"`
  - `ppt_keyid`
- same-serializer lazy forwarding keeps ciphertext bytes intact without a
  decode/re-encode round-trip
- inbound `RESULT` / `EVENT` / `INVOCATION` decrypts only when a provider is
  configured
- missing provider or missing key yields an explicit encrypted-payload failure
  path

### Router

- internal-session routing preserves `ppt_*` metadata and ciphertext bytes
- mixed transport paths continue to work because PPT is still handled at message
  level rather than transport level

### Deferred

- handshake-based key negotiation
- `flatbuffers`
- Rust-native encrypt/decrypt parity
- dedicated benchmark scenarios

## Recommended Next Implementation Slice

1. Add a runtime `WampE2eeProvider`-style interface plus config plumbing on the
   client/router side.
2. Add an explicit undecryptable-encrypted-payload surface instead of silently
   materializing empty payloads.
3. Implement CBOR + `xsalsa20poly1305` outbound pack and inbound unpack on the
   Dart path.
4. Cover `CALL/PUBLISH/RESULT/EVENT/INVOCATION` with focused tests before
   attempting native parity or handshake extensions.
