# WAMP E2EE / PPT Research

## Why This Exists

The repo already had the right message-layer hook for end-to-end payload
protection: `ppt_scheme = "wamp"`. This note captured the boundary for the
first implementation and now records the resulting phase-1 prototype.

## Working typed profile stage, 2026-10-04

An uncommitted candidate implements the Connectanum-local v2 wamp/flatbuffers
profile in portable XSalsa20-Poly1305 and AES-256-GCM providers. Cipher/key machinery
is shared with CBOR-v1 without inheriting its plaintext framing. The typed input
is exactly one Uint8List, with no keyword container or application-schema/root
validation; empty and CBOR-shaped bytes remain valid. The ciphertext limit includes
nonce/tag (40/28 bytes respectively); the outer frame/transport may impose a smaller
limit. Preflight precedes default/key mutation. Exact required Session profile and
provider matching is tested. This version is a Connectanum contract, not a claimed
WAMP-standard E2EE version or authentication of all surrounding profile metadata.

The new optional Rust consume-format-wide API explicitly separates CBOR PPT (0)
from whole typed plaintext (1). Unknown formats preserve the handle. A valid
consume is one-shot even on authentication failure, returning no plaintext owner
on failure. Dart's cache now includes format and rejects a different-format read
after consumption. Older artifacts preserve CBOR behavior and return no typed
consuming capability; typed callers must use generic authenticated raw-byte
decryption instead of the CBOR heuristic. Typed consuming output is read-only,
with its owner anchored to backing external typed data and its returned wrapper.

Focused core VM 105, client VM 82, core Chrome JS/WASM 22, Session Chrome JS/WASM
42, Rust ffi-test 260 and native runtime 84 cases pass. The failed root-directory
browser invocation and initial eight runtime read-only failures are retained.
The subsequent native checkpoint below adds typed-provider classes, generic
fallback parity, file-path rejection and focused derived-view/GC evidence.
Fresh canonical/mutation checks remain required under #101/#102. Existing native encrypt/decrypt generic helpers
copy input into native storage and copy output back to Dart; those costs still
need separate transformation/copy accounting under #103. Focused success is not
a complete performance or milestone result. Evidence/dispositions:
/tmp/connectanum-flatbuffers-typed-e2ee-companion-decisions.json.

The native `NativeWampFlatBuffersXsalsa20Poly1305Provider` and
`NativeWampFlatBuffersAes256GcmProvider` are sibling implementations of v2, sharing
key/cipher logic with CBOR-v1. They bound raw typed input before policy/default
side effects, explicitly select typed consuming decryption, and fall back to
generic authenticated whole-byte decryption on older native artifacts. Native
file-segment framing remains CBOR-v1 and is rejected before mutation by v2.

Frozen focused checks pass Rust/FFI 261, providers 25, runtime 92 and Session 44;
Session also passes Chrome JS/WASM. The old d26581c3 production artifact passes 24
provider and eight receive fallback contracts. The excluded production-artifact
case uses a test-only native owner registry. For both ciphers, that separate-process
probe collects incoming/provider wrappers, releases abandoned plaintext, preserves
a nested read-only ByteData view and releases its owner when the final view is gone.
This proves the tested synchronous-decrypt view lifetime, not asynchronous send
lifetimes or zero-copy encryption. Explicit owner release makes all derived views
unusable; callers needing retained views should use automatic finalization.
Proof: /tmp/connectanum-flatbuffers-typed-native-owner-oracle-verification.json.

## Previous integrated FlatBuffers milestone checkpoint, 2026-10-04

The integrated candidate supports an outer FlatBuffers WAMP envelope and
unencrypted, single-buffer typed FlatBuffers PPT. Built-in encrypted payload
providers still use the existing version-1 CBOR plaintext contract; a typed
FlatBuffers E2EE profile remains an explicit #101 completion gate. Native CBOR
cipher parity was implemented after the historical phase-1 baseline below.

The reproduced packed-CBOR send defect is repaired: matching serializer names
cannot bypass the selected outbound encryption provider. Outbound sends invoke
that provider for fresh authenticated ciphertext, including inputs decoded from
another key. Pure router forwarding still preserves ciphertext without decrypting.
The public mixed-serializer Session matrix proves both existing ciphers through
RPC, progressive replies, ERROR and pub/sub; it does not prove typed FlatBuffers
E2EE, application-schema agreement or all transport combinations.

The [WAMP draft](https://wamp-proto.org/wamp_latest_ietf.html#section-14.1)
(checked 2026-10-04) lists FlatBuffers for PPT and requires one outer binary
argument. Its generic logical payload packaging and application-typing sections
must be read together: a typed table represents the application's complete
payload. The E2EE section itself remains TBD. New encryption support must document
its concrete plaintext/profile contract, preserve CBOR version-1 behavior and
keep application schema/IDL services outside core requirements.

The native consuming decrypt API recognizes a canonical CBOR plaintext
single-binary-argument envelope and may return only that argument. A typed
FlatBuffers implementation must not silently use this plaintext heuristic as its
schema or format contract. Generic crypto accepts plaintext bytes, but any native
zero-copy adaptation must select the output format explicitly and preserve its
owner, cache identity and failure/consumption rules. No new profile is claimed here.

### Native outer-envelope parity repair, focused verification

An outside-workspace extension of the existing consuming-decrypt fixture to an
outer FlatBuffers envelope fails for both existing CBOR ciphers: native code
returns unsupported (-1) after the RawSocket handshake and message decoding.
The original JSON/MessagePack/CBOR matrix does not cover that dimension. This
is separate from typed FlatBuffers encryption; the public Session matrix using
portable providers alone does not prove native consuming-decrypt parity.
The fail-first fixture inputs and results are preserved in
/tmp/connectanum-flatbuffers-native-e2ee-gap-probe.json and
/tmp/connectanum-flatbuffers-native-e2ee-gap-probe.log. The same two cases also fail against the rebuilt
master-merge library 67d8d0e436e6c81d, after handshake and materialization, in
/tmp/connectanum-flatbuffers-master-merged-native-e2ee-gap.json and its log.
The parser retains the opaque FlatBuffers vector separately from ordinary CBOR
arguments. Ciphertext extraction must handle that stored representation without
conflating the outer envelope with the decrypted plaintext contract.

The subsequent repair selects ciphertext from the opaque FlatBuffers vector or
its ordinary CBOR-encoded binary argument. It preserves CBOR-v1 plaintext framing,
the existing cipher choices and handle-consumption rules. Six Rust contracts cover
fresh unique AES receive-allocation reuse, shared ciphertext preservation, segmented
and independent-allocation fallback, borrowed access and invalid representations.
The full FFI suite passes 257 tests; isolated Dart runtime/provider suites pass 76
and eight against native library SHA256 88ee58a790a44db5819efd19d6159fe0a23f49a8535b0b67e86d1d9eb07102dc.
Fail-first and passing evidence is preserved in
/tmp/connectanum-flatbuffers-outer-cbor-e2ee-focused-proof.json. This is focused
local verification; the new frozen candidate's full checks and hosted CI remain
pending. Allocation reuse is proved for fresh unique receive storage, not every
backwards-builder slice, shared buffer or pooled WebSocket allocation.

Typed encryption still needs an explicit plaintext-format selector. Do not infer
that contract from the outer serializer. The current Dart decrypt cache identifies
session handle, key ID and cipher; the additive plaintext-format selector must
become part of that identity.

### Next profile design (proposal, not implemented)

An additive Connectanum-local version-2 `wamp/flatbuffers` profile is a candidate
for the typed single-buffer plaintext contract. A new version is a separation
choice, not a standardized WAMP E2EE version. Version-1 CBOR bytes, provider names,
key-selection fallbacks and cipher behavior must remain compatible.

The current CBOR providers hardcode CBOR packing/unpacking, so typed providers
must share cipher primitives without inheriting that plaintext framing. Required
session negotiation must check the selected version/serializer/provider together.
The native consuming decrypt path needs an explicit output-format selector and
matching cache identity; typed output must not depend on the CBOR-envelope
heuristic. Document and test directional key selection for the new profile while
preserving the established version-1 rule. Application schema choice remains
outside the transport; no registry or IDL service is required.

Source preparation also confirms the existing typed PPT byte contract:
FlatBuffers Serializer.serializePPTFragments requires exactly one Uint8List and
no keyword container, returns that same span and bounds its length at 64 MiB.
deserializePPT returns one byte span and enforces the length limit; neither method
verifies an application's table schema or requires a nonempty buffer. The typed
encryption design must preserve that schema-independent behavior, including empty
spans, while accounting for nonce/tag overhead against the outer wire limits.
Do not add an inferred root-table minimum or infer plaintext format from CBOR-like
leading bytes. Native typed-reader and database validation remain adapter concerns.

A bounded GLM judgment supports this direction and flags those contract boundaries.
This records preparation only: profile negotiation, public provider APIs, native
parity, malformed/unsupported cases and full Session coverage still need
implementation and verification under #101.

## Historical phase-1 baseline

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

## Phase 2 Runtime Context Outcome

- `connectanum_core` now exposes `WampE2eeRuntimeContext` and
  `WampE2eePartyContext` on the provider contract, so providers can inspect:
  - direction (`outbound` / `inbound`)
  - message family (`CALL` / `PUBLISH` / `YIELD` / `EVENT` / `RESULT` /
    `INVOCATION` / `ERROR`)
  - realm and URI/topic/procedure context
  - local session identity (`sessionId`, `authid`, `authrole`,
    `authmethod`, `authprovider`, `authextra`)
  - disclosed peer metadata (`caller` / `publisher`, `trustlevel`, and
    auth-related custom detail fields when present)
  - negotiated `WELCOME.authextra.e2ee` state
- Lazy/materialized payload views now preserve that runtime context alongside
  the attached E2EE provider, so zero-copy forwarding still works without
  dropping policy inputs before actual decrypt-on-access.
- The Dart client now fills this context on outbound `CALL` / `PUBLISH`, on
  inbound `RESULT` / `EVENT` / `INVOCATION`, and on invocation-response
  `YIELD` messages. The `RESULT` path also recovers the original procedure from
  pending-call state so providers can make result-side decisions with the same
  URI context that the call used.
- The next E2EE step should consume this runtime context for actual policy and
  key-selection decisions rather than adding more transport/session plumbing.

## Phase 2 Key-Selection Policy Outcome

- `connectanum_core` now exposes `WampE2eeKeySelectionPolicy`, a small
  provider-level callback surface that receives the current
  `WampE2eeRuntimeContext` plus mutable `PPTOptions` and can return the
  `ppt_keyid` the provider should use.
- Both `WampCborXsalsa20Poly1305Provider` and
  `NativeWampCborXsalsa20Poly1305Provider` now consume that callback before
  falling back to their provider-wide default key id, which means:
  - outbound `CALL` / `PUBLISH` can choose different keys from URI/topic,
    realm, local auth identity, peer metadata, or negotiated session state
  - inbound `RESULT` / `EVENT` / `INVOCATION` can recover a key id from the
    same runtime context when message details do not already carry one
- The session/runtime plumbing from the previous slice is now materially useful:
  the client path can attach a policy-aware provider once, and per-message key
  selection happens inside the provider without router participation or FFI
  contract changes.
- The next E2EE step is no longer “add a callback.” It is to make the callback
  reusable across applications instead of forcing each deployment to re-encode
  the same negotiated fallback and peer/trust rules by hand.

## Phase 2 Policy Adapter Outcome

- `connectanum_core` now ships reusable policy adapters on top of the shared
  `WampE2eeKeySelectionPolicy` surface:
  - `WampE2eeKeySelectionPolicies.negotiated()` maps
    `WELCOME.authextra.e2ee` into direction-aware fallback key ids.
  - `WampE2eeKeySelectionPolicies.rules(...)` and
    `WampE2eeKeySelectionRule` match URI, message family, local auth identity,
    peer auth identity, and peer trust metadata.
  - `WampE2eeKeySelectionPolicies.firstDefined(...)` composes specific policy
    rules ahead of broader negotiated fallback.
- The built-in Dart and native providers now expose that policy surface through
  `WampE2eePolicyAwareProvider`, so wrappers can preserve provider-owned
  policy instead of treating negotiated session state as an unconditional
  override.
- The client session wrapper now applies negotiated serializer/cipher defaults
  as before, but key selection is policy-first and negotiated-second. That
  means a deployment can attach one provider with reusable policy adapters and
  still let negotiated `WELCOME.authextra.e2ee` act as the fallback contract.
- This closes the current “hand-roll selector callback” gap. Further E2EE work
  should only happen if real application integrations justify higher-level
  provider presets, rotation helpers, or wire-level key-agreement changes.

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
