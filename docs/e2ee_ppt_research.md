# WAMP E2EE / PPT Research

## Why This Exists

The repo already had the right message-layer hook for end-to-end payload
protection: `ppt_scheme = "wamp"`. This note captured the boundary for the
first implementation and now records the resulting phase-1 prototype.

## Current Repo Baseline

- `packages/connectanum_core/lib/src/message/e2ee_payload.dart` now ships the
  provider abstraction, the built-in
  `WampCborXsalsa20Poly1305Provider`, and explicit failure types for
  missing providers, unsupported ciphers, missing keys, invalid payload shape,
  and authentication/decryption failure.
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
- `packages/connectanum_client/lib/src/client.dart` already exposes
  `Client.e2eeProvider`, so the concrete provider is part of the public client
  configuration surface without another transport-specific config layer.
- `packages/connectanum_client/lib/src/protocol/session.dart` now also exposes
  `SessionE2eeProviderContext` plus `Client.e2eeProviderResolver`, so each
  session can resolve its concrete provider from authenticated/negotiated
  runtime state before message traffic starts while preserving the static
  `Client.e2eeProvider` fallback.
- Router forwarding still treats WAMP E2EE payloads as opaque ciphertext bytes;
  the router runtime tests now pin `ppt_cipher` / `ppt_keyid` passthrough on
  internal-session publish/call flows.
- The repo already depends on `pinenacl` and `pointycastle` for authentication
  work; phase 1 now uses `pinenacl` `SecretBox` for the Dart-side
  `xsalsa20poly1305` prototype. There is still no Rust-native encrypt/decrypt
  parity.

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

## Phase 1 Outcome

- Outbound `CALL` / `PUBLISH` / `YIELD` on the Dart path now emit one packed
  ciphertext argument and fill `ppt_serializer = "cbor"`,
  `ppt_cipher = "xsalsa20poly1305"`, and `ppt_keyid`.
- Inbound `RESULT` / `EVENT` / `INVOCATION` decrypt only when a provider is
  attached; missing providers, missing keys, unsupported ciphers, malformed
  payload shape, and authentication/decryption failures all surface explicitly.
- Same-serializer lazy forwarding still preserves ciphertext bytes without a
  decode/re-encrypt round trip.
- Router internal-session forwarding still does not decrypt; it preserves the
  opaque payload bytes and the `ppt_*` metadata that the endpoints need.

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

## Possible Next Slices After Phase 1

1. Decide whether key discovery/rotation should stay out-of-band or move into a
   session/auth handshake extension.
2. Add Rust/native parity only after the Dart payload contract is considered
   stable.
3. Revisit router-assisted key distribution only if deployments need it; do not
   collapse phase 1 back into router-side payload inspection.

## Phase 2 Design Outcome

The packaging/release prerequisite is now satisfied, so the next E2EE milestone
can move from “research whether we should” to “design exactly how we do it”.
The recommended phase-2 direction is:

- keep `connectanum_core` responsible for PPT wire shape and payload framing
- keep the router blind to encrypted payload contents
- add a contextual runtime negotiation/provider layer above the current
  `WampE2eeProvider`
- add a backward-compatible auth-handshake extension for key/capability
  negotiation before any Rust-native encrypt/decrypt work lands

## Recommended Native / Off-Dart Architecture

### 1. Split framing from runtime key decisions

Phase 1 proved that the framing contract works. Phase 2 should avoid baking
key selection and peer/session policy into serializer helpers. The current
provider needs a richer runtime context, not more static helper branches.

Recommended direction:

- keep `E2EEPayload.packE2EEPayload` / `unpackE2EEPayload` as framing entry
  points
- introduce a runtime context object that carries:
  - direction (`outbound` / `inbound`)
  - message family (`CALL` / `PUBLISH` / `YIELD` / `EVENT` / `RESULT` /
    `INVOCATION` / `ERROR`)
  - realm
  - URI / procedure / topic when available
  - local auth identity (`authid`, `authrole`, provider)
  - negotiated remote peer metadata when available
  - selected `ppt_serializer`, `ppt_cipher`, and `ppt_keyid`
- keep the current provider as the “pure Dart local implementation” adapter for
  that richer contract

That lets the client decide encryption policy from real session context without
teaching `connectanum_core` about transport or auth state.

### 2. Add a native-capable provider lane, not a router decryption lane

The native parity target should be “encrypt/decrypt without bouncing payloads
back through Dart”, not “let the router understand ciphertext”.

Recommended shape:

- the client owns the E2EE policy and key registry
- the router continues to forward opaque ciphertext plus `ppt_*` metadata
- `ct_ffi` gains a native E2EE session/keyring handle layer that is configured
  from the client side before the session starts
- native direct event/result/invocation paths decrypt at the client boundary,
  where the current Dart provider already runs today

This keeps the trust boundary intact:

- transport/native runtime may accelerate cryptography
- router still cannot read payload contents
- mixed Dart/native client implementations can share the same negotiation
  contract

### 3. Stage native parity behind the negotiated Dart contract

Do not start with a Rust-only key flow. The order should be:

1. negotiation metadata contract
2. client-side contextual provider contract
3. Dart implementation using the negotiated contract
4. `ct_ffi` parity for the same negotiated contract

That avoids shipping two incompatible E2EE models.

## Phase 2 Native Parity Outcome

- `ct_ffi` now exposes native E2EE keyring/session handles plus synchronous
  `xsalsa20poly1305` encrypt/decrypt entrypoints over already-framed PPT
  bytes.
- `connectanum_client` now ships
  `NativeWampCborXsalsa20Poly1305Provider`, which keeps PPT framing in
  `connectanum_core` while moving key storage and cryptography into the native
  runtime.
- Session-scoped resolver-created native providers now release their native
  handles on session teardown through the shared
  `DisposableWampE2eeProvider` contract.
- The remaining phase-2 gap is no longer basic native crypto parity. The next
  step is a richer provider runtime context for per-message policy and key
  selection on top of the now-shared Dart/native provider lane.

## Recommended HELLO / CHALLENGE Negotiation Shape

The repo already has the right message surfaces:

- `HELLO.details.authextra`
- `CHALLENGE.extra`
- `AUTHENTICATE.extra`
- `WELCOME.details.authextra`

Phase 2 should use one optional `e2ee` object within those existing maps rather
than inventing new top-level WAMP message fields.

### HELLO

Client advertises support and local preferences:

```json
{
  "authextra": {
    "e2ee": {
      "version": 1,
      "required": false,
      "schemes": ["wamp"],
      "serializers": ["cbor"],
      "ciphers": ["xsalsa20poly1305"],
      "key_ids": ["kid-client-a"],
      "client_pubkey": "<base64url-x25519-pubkey>",
      "kex": "x25519-xsalsa20poly1305"
    }
  }
}
```

Notes:

- `required = true` means fail closed if the server/auth flow cannot establish
  an agreed E2EE session.
- `key_ids` advertises usable outbound recipient keys without exposing secret
  material.
- `client_pubkey` is optional and should be used only for negotiated ephemeral
  or semi-static public-key schemes.

### CHALLENGE

Authenticator or router-auth flow returns policy plus server/authenticator
parameters:

```json
{
  "e2ee": {
    "required": true,
    "selected_scheme": "wamp",
    "selected_serializer": "cbor",
    "selected_cipher": "xsalsa20poly1305",
    "accepted_key_id": "kid-client-a",
    "server_pubkey": "<base64url-x25519-pubkey>",
    "challenge_binding": "<opaque-binding-token>"
  }
}
```

Purpose:

- bind key negotiation to the same auth challenge that establishes identity
- let the client know whether the server accepted the advertised key/cipher
- optionally bind the E2EE agreement to the auth challenge so replay/downgrade
  attempts are explicit

### AUTHENTICATE

Client confirms the negotiated parameters:

```json
{
  "extra": {
    "e2ee": {
      "accepted": true,
      "key_id": "kid-client-a",
      "client_pubkey": "<base64url-x25519-pubkey>",
      "client_proof": "<opaque-proof-or-signature>"
    }
  }
}
```

Purpose:

- confirm which key identity the client is actually binding to the session
- optionally prove possession or bind the key exchange to the auth challenge

### WELCOME

Server returns the established session parameters:

```json
{
  "authextra": {
    "e2ee": {
      "established": true,
      "scheme": "wamp",
      "serializer": "cbor",
      "cipher": "xsalsa20poly1305",
      "peer_key_id": "kid-server-a",
      "send_key_id": "kid-server-a",
      "receive_key_id": "kid-client-a",
      "peer_pubkey": "<base64url-x25519-pubkey>"
    }
  }
}
```

This becomes the negotiated session contract that both Dart and native client
paths consume.

## Compatibility and Security Rules

- Absence of `authextra.e2ee` means the session falls back to the current
  out-of-band provider model.
- `required = true` must fail the session if negotiation does not succeed; it
  must not silently downgrade to plaintext WAMP payloads.
- The router/authenticator may validate and relay negotiation metadata, but it
  should not need payload decryption keys to do so.
- Phase 2 should still support only:
  - `ppt_scheme = "wamp"`
  - `ppt_serializer = "cbor"`
  - `ppt_cipher = "xsalsa20poly1305"`
- Additional ciphers or serializers should come only after the negotiated
  contract and native parity are stable.

## Recommended Implementation Slices After This Design

1. ✅ Preserve `authextra.e2ee` / `CHALLENGE.extra.e2ee` metadata on the Dart
   handshake path and expose negotiated session state through `Session`.
2. ✅ Introduce a contextual E2EE runtime contract on the client side that can use
   either:
   - the current Dart provider, or
   - a future native/session-backed provider
3. ✅ Thread outbound/inbound PPT defaults from the negotiated session contract so
   callers do not need fully out-of-band configuration for every encrypted
   session.
4. Add `ct_ffi` keyring/session handles and native encrypt/decrypt parity only
   after the Dart negotiation + session-provider contract is exercised
   end-to-end.
