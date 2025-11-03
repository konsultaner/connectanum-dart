# Connectanum Router Roadmap

## Transport & Runtime

- [x] Native Rust runtime (`ct_ffi`) with WAMP RawSocket support
- [x] Dart wrapper for native runtime (start/listen/poll/pollMessage)
- [x] Boss/worker isolate pipeline with zero-copy frame handling
- [x] Router CLI example (`packages/connectanum_router/example`)
- [ ] Native TLS offload & kTLS integration
- [ ] WebSocket transport (WAMP over WebSocket)
- [ ] Serializer matrix (JSON, MessagePack, CBOR, UBJSON, FlatBuffers)
  - [ ] Cross-serializer translation so mixed clients (e.g. JSON ↔ MessagePack/CBOR) can publish/call across encodings without data loss; include regression tests for EVENT, RESULT, and ERROR bridging and document zero-copy fallbacks.
- [ ] Backpressure / flow control between workers and native layer
- [ ] HTTP/1.1, HTTP/2, HTTP/3 transport layer (long-polling, streaming WAMP)
- [ ] HTTP RPC bridge (forward HTTP requests into WAMP RPCs and return responses)
- [ ] HTTP forwarding hooks for custom routing/handling in RPC implementations
- [ ] Graceful shutdown (drain sessions, send GOODBYE/HTTP responses, stop listeners)
  - [ ] Provide unified HTTP bridge that can surface Prometheus/Grafana exporters alongside REST→WAMP translation.
  - [ ] Support structured metrics endpoints over HTTP/2 and HTTP/3 so observability stack can scrape without extra proxies.
- [x] Outbound frame bridge (`ct_send`/FFI) for CHALLENGE/WELCOME/EVENT delivery
- [ ] End-to-end payload encryption (E2EE) strategy
  - [ ] Evaluate keeping encryption off the Dart hot-path (Dart’s 64-bit object model vs native/Rust or dedicated isolates with binary messaging).
  - [ ] Prototype native encryption/decryption pipeline that preserves zero-copy semantics and works across serializers.
  - [ ] Define key-management interfaces and handshake flow (HELLO/CHALLENGE payload negotiation).
  - [ ] Add regression tests ensuring encrypted PUB/SUB and RPC payloads interoperate with unencrypted peers where allowed.

## Router State & Infrastructure

- [x] Central `RouterStateStore` (realms, sessions, subscriptions, registrations)
- [x] Realm snapshots & invalidation events for workers
- [x] Command API (async mutation/query from workers)
- [x] Persistent ID allocators (session/subscription/registration/publication/ invocation/request)
- [ ] Worker pool autoscaling
  - [ ] Collect per-worker load metrics (connection counts, pending handle depth, queue latency, host stats)
  - [ ] Implement hysteresis-based scale-up/scale-down policy with configurable thresholds
  - [ ] Reassign connections gracefully during scale-down using drain flow
  - [ ] Integrate load-aware connection assignment (least-busy/weighted policies)
  - [ ] Verify cross-worker parallelism with high-contention integration tests (parallel call/publish workloads)
- [ ] Meta event dispatch plumbing (session/subscription/registration meta)
- [ ] Metrics counters / observability hooks

## Basic Profile (WAMP v2)

### Session & Realm Management

- [x] HELLO frame parsing in native layer
- [x] HELLO → WELCOME handshake & role negotiation (anonymous + challenge/response paths)
- [x] ABORT handling (capability or auth failure)
- [x] GOODBYE reception & realm cleanup
- [x] Router-initiated GOODBYE / graceful shutdown (drain sessions and propagate to clients)
- [ ] Heartbeat / ping-pong / session timeout support

### Publish & Subscribe

- [x] SUBSCRIBE frame decoding
- [x] UNSUBSCRIBE frame decoding
- [ ] Subscription tracking per session/realm
  - [ ] Unit tests: subscribe/unsubscribe success, invalid/topic errors, session teardown cleanup
- [ ] Topic publication routing (EVENT)
  - [ ] Unit tests: publish with ack on/off, exclude/eligible filters, wildcard/prefix routing
- [ ] Publication IDs / ACK handling
- [ ] ERROR routing for SUBSCRIBE/UNSUBSCRIBE/PUBLISH
- [x] End-to-end zero-copy PUB/SUB dispatch (reuse native frame buffers across subscribers)
  - [x] FFI support for cloning publish frames with patched headers only
  - [x] Worker routing uses native handles instead of Dart re-serialization
  - [x] Tests ensure EVENT payload buffers are reused across recipients

### Remote Procedure Calls

- [x] REGISTER / UNREGISTER decoding
- [x] CALL / RESULT / ERROR decoding
- [ ] Registration tracking per realm/session
  - [ ] Unit tests: register/unregister success, duplicate/ownership enforcement, session cleanup
  - [ ] Invocation dispatch + RESULT/ERROR forwarding
    - [x] Synthetic RawSocket integration harness (ffi-test mode) covering HELLO→CALL→progressive/final RESULT forwarding
    - [ ] Unit tests: call→invocation→result, failing callee, timeouts, progressive results placeholder
- [ ] ERROR handling for REGISTER/UNREGISTER/CALL
- [ ] CALL cancellation (basic profile – CANCEL)
- [x] End-to-end zero-copy RPC dispatch (reuse native call payload buffers)
  - [x] FFI helper for cloning invocation frames without copying arguments
  - [x] Worker invocation forwarding uses cloned native handles
  - [x] Tests ensure YIELD/ERROR paths dispose clones correctly

## Advanced Profile

### Pub/Sub Enhancements

- [ ] Pattern-based subscriptions (prefix / wildcard with order/priority)
- [ ] Subscription meta events (created, deleted, on/off subscribe)
- [ ] Publisher options (exclude_me, eligible/exclude authid/authrole lists)
- [ ] Payload persist / retained events
- [ ] Throttle/debounce hooks driven by client-provided hashes in publish pipeline
  - Reference: [WAMP issue #391 comment](https://github.com/wamp-proto/wamp-proto/issues/391#issuecomment-998577967) for debounce/throttle semantics and hashing strategy.
  - Ensure serializers accept implementation-specific option/detail keys (spec allows `_foo` style; tolerate legacy non-underscore keys to interop with existing routers like Crossbar).

### RPC Enhancements

  - [ ] Shared registrations with invocation policies (round-robin, random, load)
  - [ ] Shared registration meta events
- [ ] Load-aware invocation balancing (collect CPU/RAM/remote metrics and select least-loaded callee)
- [ ] Progressive call results (`progress=true`)
- [ ] Call cancellation modes (`kill`, `killnowait`, `killall`) — ensure cancellers can wait for cleanup so subsequent processing shuts down gracefully
- [ ] Caller disclosure (`caller`, `caller_authid`, `caller_authrole`)
- [ ] Throttle/debounce hooks driven by client-provided hashes in call pipeline
  - Align behaviour with [WAMP issue #391 comment](https://github.com/wamp-proto/wamp-proto/issues/391#issuecomment-998577967) to allow routers to honour client-provided throttling keys.
  - Client/server serializers must preserve custom fields (prefer `_custom` naming per spec, but remain lenient to match existing implementations).
- [ ] Sharded registrations / invocation trust level (`trustlevel`)

### Authentication & Authorization

- [x] Challenge/response (`CHALLENGE`/`AUTHENTICATE`) flow
- [x] Router worker integrates authenticator registry with per-session state/tests
- [x] Anonymous/no-auth handshake (immediate WELCOME)
- [ ] Pluggable authenticators (shared client/router implementations):
  - [ ] Static ticket
  - [ ] WAMP-CRA (HMAC challenge/response)
  - [ ] SCRAM (salted challenge/response)
  - [ ] WAMP-cryptosign / ED25519
  - [x] Remote authentication executor (delegate auth decisions to external service)
    - [x] Document Java interoperability contract (realm `connectanum.authenticate`, procedures `authenticate.hello` / `authenticate.authenticate` / `authenticate.abort`), including expected payload shape and error semantics. See `docs/remote_auth_interop.md`.
    - [x] Implement router-side transaction nonce generator (cryptographically strong, per-session) with bounded TTL and automatic cleanup on client disconnect.
    - [x] Add realm-configurable policy to whitelabel permitted authroles/authproviders returned by delegate; abort if response violates policy.
    - [x] Support multiple remote authenticators per realm/listener with failover strategy and connection-state monitoring.
    - [x] Enforce rate limiting/backoff for remote auth RPC calls and integrate failures with `AuthSecurityTracker`.
    - [ ] Introduce authenticated transport to the remote service (mutual TLS and/or signed tokens) and automatic credential rotation hooks.
    - [ ] Restrict serialized payload to the minimal required auth fields; validate schema on both request and response before issuing `CHALLENGE`/`WELCOME`.
    - [ ] Preserve “fake challenge” behavior on remote rejection while logging audit details for operators.
    - [ ] Add integration tests spinning up a stub remote service to verify success, rejection, timeout, and abort flows end-to-end.
    - [ ] Add internal transport support for router ↔ auth server chaining:
      - [ ] Design in-process frame transport (shared ring buffer / isolate message channel) with backpressure.
      - [ ] Embed an internal WAMP client inside the router to proxy authentication requests over the internal transport.
      - [ ] Auth server hosts a router instance plus internal client that drives credential providers.
      - [ ] Ensure configuration allows switching between TCP delegates and in-process delegates for testing.
      - [ ] Extend unit/integration tests to cover internal-transport authentication flow.
      - [ ] Prerequisite: RPC invocation and PUB/SUB dispatch must be implemented so the router can forward authentication RPCs end-to-end.
    - [ ] Add shared message-flow abstraction (PUB/SUB ~ REGISTER/CALL):
      - [ ] Extract reusable primitives for routing requests, tracking responders, and emitting replies/events.
      - [ ] Ensure new abstraction is covered by unit tests for both publish/event and call/result paths.
  - [ ] Interoperability with `connectanum-authentication` remote executor (Java auth server)
  - [ ] Survey community extensions (GitHub/routers) for additional mechanisms
- [ ] Realm-level authorizers (permission checks before SUBSCRIBE/PUBLISH/etc.)
- [ ] Static TLS cert/SNI configuration pipeline to native runtime
- [ ] Intrusion detection (failed-auth rate limiting, account lockouts, anomaly alarms)

### Introspection & Testing

- [ ] WAMP meta API (session, subscription, registration listings)
- [ ] Caller tracing & diagnostic events
- [ ] Administrative control interface (pause/resume realm, drain connections)
- [ ] Replay/testing hooks (record & replay message streams)
- [x] FFI “test mode” harness for synthetic RawSocket integration tests (HELLO/CALL/YIELD flows)

## Tooling & Documentation

- [x] Router example CLI for local testing
- [ ] Developer docs for native runtime build pipeline
- [ ] Configuration reference (realm JSON schema, TLS modes, worker tuning)
  - [ ] Document feature toggles in crossbar-compatible config (meta events, benchmark exporters, zero-copy assertions)
  - [ ] Allow per-listener/realm flags to disable optional subsystems without code changes
- [x] Crossbar-compatible configuration schema + validation tooling
- [ ] Example gallery for router features
  - [x] CLI demo covering hashed credentials, `CredentialRejection`, and remote delegates (`packages/connectanum_router/example`)
  - [ ] WebSocket transport demo (router + remote auth server)
  - [ ] Stub remote service integration (fake challenge parity)
- [ ] Comprehensive WAMP feature test suites (basic + advanced)
  - [ ] Basic profile: HELLO/WELCOME, PUB/SUB, RPC, error flows
  - [ ] Advanced profile: pattern subscriptions, shared registrations, cancellation, progressive results
- [x] Auth server scaffolding (`packages/connectanum_auth_server`) providing the same authenticator API for remote deployments
- [ ] Auth server CLI (config loader, RPC loop, health endpoints)
- [ ] Remote auth secure transport (mTLS / signed tokens) and credential rotation
- [ ] Fake challenge parity & stub remote service integration tests
- [ ] Internal transport support for embedded router↔client flows
  - [ ] Define in-process transport abstraction (frame routing with backpressure)
  - [ ] Embed internal client inside edge router to speak RemoteAuthenticatorDelegate over the new transport
  - [ ] Auth server runs router instance + internal client that talks to credential providers
  - [ ] Wire configuration knobs for selecting internal vs TCP transports
  - [ ] Migrate existing delegate tests/examples to the internal transport once available
- [ ] End-to-end smoke tests (native runtime ↔ router ↔ client)
- [ ] Benchmarks (throughput/latency per worker configuration)
  - [ ] Provide release-build workflow for `ct_ffi` (and document `CONNECTANUM_NATIVE_LIB` usage) dedicated to performance runs.
  - [ ] Implement a reusable load generator (multi-session HELLO/PUB/SUB/RPC workloads) to stress the router.
  - [ ] Expose lightweight instrumentation (per-worker queue depth, handle retention counts, throughput/latency timers) for benchmark reporting.
  - [ ] Add automation scripts that run warm-up + steady-state cycles and emit latency/throughput summaries.
  - [ ] Ship Prometheus exporters and Grafana dashboards for benchmark metrics visualisation.
  - [ ] Provide docs/scripts to bootstrap a local Grafana/Prometheus stack alongside benchmarks.
- [ ] MCP (Model Context Protocol) server implementation for agentic AI integrations
- [ ] Metrics & logging integration (Prometheus metrics, structured logs, CPU/RAM/throughput gauges)
  - [ ] Always-on low-cost counters (native/Dart) exposed via on-demand snapshots for benchmark harnesses.
  - [ ] Configurable metrics exporter isolate (Prometheus) gated by crossbar-compatible config flags to avoid production overhead.
  - [ ] Sampling windows for high-cost histograms (latency, zero-copy reuse) triggered only during benchmarks.
