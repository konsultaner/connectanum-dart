# Asynchronous SCRAM Key Derivation

Status: complete
Owner: Codex
Created: 2026-08-23
Last updated: 2026-08-24

## Goal

Keep Argon2id13 and PBKDF2 work off the Flutter web UI event loop and native
session isolate while preserving existing WAMP-SCRAM proofs, UTF-8/SASLprep
behavior, stored-key/server-key compatibility, and strict mutual server
authentication.

## Scope

- In scope: a platform-specific asynchronous derivation abstraction; killable
  per-operation native isolates and web workers; a pinned self-contained WASM
  Argon2id13 implementation for web; cancellation, timeout, crash, disposal,
  and reconnect handling; challenge-bound key caching; router verifier
  generation; WAMP WELCOME and HTTP grant verifier checks; native and browser
  regression coverage.
- Out of scope: changing SCRAM wire algorithms or KDF parameters, replacing
  SASLprep, persisting client keys, relaxing server-verifier requirements, or
  consumer-application authentication workarounds.

## Files Expected To Change

- `packages/connectanum_core/lib/src/authentication/`
- `packages/connectanum_core/test/authentication/`
- `packages/connectanum_client/lib/src/protocol/session.dart`
- `packages/connectanum_client/lib/src/mcp/http_auth_client.dart`
- `packages/connectanum_client/lib/src/transport/local_transport.dart`
- `packages/connectanum_router/lib/src/router/auth/scram_authenticator.dart`
- Focused client/router/browser tests and package metadata
- Third-party attribution and a reproducible pinned worker-source generator

## Preconditions

- Existing SCRAM vectors remain the compatibility baseline.
- Flutter web does not provide concurrent Dart isolates; browser Argon2 must
  therefore execute in a dedicated Web Worker and must not synchronously fall
  back to the UI thread.
- The WAMP SCRAM final server verifier is
  `WELCOME.Details.authextra.verifier` and must be checked before session
  success.

## Plan

1. Define task-based derivation and authentication-finalization contracts with
   explicit cancellation, timeout, disposal, and generation isolation.
2. Implement native isolate and browser Worker derivation, pin the web WASM
   source with attribution and a reproducible checksum, and prove native/web
   output parity.
3. Refactor SCRAM proof construction to use the asynchronous boundary, bind
   cached keys to all derivation and identity inputs, and clear mutable secret
   material when no longer needed.
4. Return the router's server signature and await constant-time verification in
   both WAMP WELCOME and HTTP auth-grant completion.
5. Cover responsiveness at 64 MiB, vectors, concurrency, cancellation,
   timeout, worker failure, disposal, reconnect, changed challenges, cache
   isolation, and PBKDF2 compatibility.
6. Run focused browser/native tests, local review, `bin/verify`, and the hosted
   deployment-chain evidence required by the touched packages.

## Verification

- `bin/test-fast` passed before and after implementation on 2026-08-23.
- Focused native core, client, router, local-transport, and HTTP-auth SCRAM
  tests passed on 2026-08-23.
- Chrome JavaScript and Dart2Wasm SCRAM worker tests passed on 2026-08-23,
  including native-output parity, a responsive event loop during a 64 MiB
  Argon2id13 derivation, exact concurrent-result routing, worker crash,
  cancellation, timeout, and disposal.
- Full exact-tree `bin/verify` passed again on 2026-08-24, including the Chrome
  Dart2Wasm SCRAM worker gate, package-consumer activation, live SCRAM MCP,
  client final-verifier buffering, router auth, remote auth, benchmark, and
  native forwarding coverage.
- Final proof-lifetime hardening clears mutable authentication-message,
  signature, recovered-key, proof, stored-key, and server-key buffers after
  proof construction or verification. The final exact-tree `bin/verify` passes
  after this hardening.
- Exact-head GitHub CI, package dry run, router image dry run, and deployment
  audit remain required when the implementation is pushed.

## Decision Log

- 2026-08-23: Use one killable worker per derivation. This makes cancellation,
  timeout, crash cleanup, and stale-response isolation stronger than a shared
  long-lived queue while authentication derivations remain infrequent.
- 2026-08-23: Bundle the pinned Argon2id13 WASM worker source into generated
  Dart rather than requiring consumers to copy private assets or load a CDN.
  Blob/CSP worker initialization failures remain visible and fail closed.
- 2026-08-23: Route PBKDF2 through the same asynchronous platform boundary so
  challenge lifecycle behavior is consistent while retaining identical
  SHA-256 PBKDF2 output.
- 2026-08-23: Existing synchronous Argon2 provisioning helpers may remain on
  native Dart for compatibility, but web calls must throw rather than run the
  expensive KDF synchronously.
- 2026-08-23: Require the standards-defined server verifier before reporting
  SCRAM success. Stored-key router configurations therefore also require the
  matching server key, as documented already.
- 2026-08-23: Pause the client transport subscription while asynchronous
  server-verifier validation is pending. The stream buffers any post-WELCOME
  frames and resumes only after authentication succeeds, so no valid message
  is lost and no unverified session traffic is delivered.

## Handoff

- Implementation and local verification are complete. Native derivations use
  killable per-operation isolates; web derivations use dedicated Workers with
  pinned generated Argon2id13 WASM and no synchronous web fallback. SCRAM
  success now requires the router server verifier, cache reuse is bound to the
  complete normalized challenge and identity, and stale reconnect results fail
  closed. Mutable proof-construction and router-verification intermediates are
  cleared promptly. Hosted deployment-chain evidence is the remaining
  post-push step.
