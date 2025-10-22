# Connectanum Router Roadmap

## Transport & Runtime

- [x] Native Rust runtime (`ct_ffi`) with WAMP RawSocket support
- [x] Dart wrapper for native runtime (start/listen/poll/pollMessage)
- [x] Boss/worker isolate pipeline with zero-copy frame handling
- [x] Router CLI example (`packages/connectanum_router/example`)
- [ ] Native TLS offload & kTLS integration
- [ ] WebSocket transport (WAMP over WebSocket)
- [ ] Serializer matrix (JSON, MessagePack, CBOR, UBJSON, FlatBuffers)
- [ ] Backpressure / flow control between workers and native layer
- [ ] HTTP/1.1, HTTP/2, HTTP/3 transport layer (long-polling, streaming WAMP)
- [ ] HTTP RPC bridge (forward HTTP requests into WAMP RPCs and return responses)
- [ ] HTTP forwarding hooks for custom routing/handling in RPC implementations
- [ ] Graceful shutdown (drain sessions, send GOODBYE/HTTP responses, stop listeners)

## Router State & Infrastructure

- [ ] Central `RouterStateStore` (realms, sessions, subscriptions, registrations)
- [ ] Realm snapshots & invalidation events for workers
- [ ] Command API (async mutation/query from workers)
- [ ] Persistent ID allocators (session/subscription/registration/publication/ invocation/request)
- [ ] Meta event dispatch plumbing (session/subscription/registration meta)
- [ ] Metrics counters / observability hooks

## Basic Profile (WAMP v2)

### Session & Realm Management

- [x] HELLO frame parsing in native layer
- [ ] HELLO → WELCOME handshake & role negotiation
- [ ] ABORT handling (capability or auth failure)
- [ ] GOODBYE reception & realm cleanup
- [ ] Heartbeat / ping-pong / session timeout support

### Publish & Subscribe

- [x] SUBSCRIBE frame decoding
- [x] UNSUBSCRIBE frame decoding
- [ ] Subscription tracking per session/realm
- [ ] Topic publication routing (EVENT)
- [ ] Publication IDs / ACK handling
- [ ] ERROR routing for SUBSCRIBE/UNSUBSCRIBE/PUBLISH

### Remote Procedure Calls

- [x] REGISTER / UNREGISTER decoding
- [x] CALL / RESULT / ERROR decoding
- [ ] Registration tracking per realm/session
- [ ] Invocation dispatch + RESULT/ERROR forwarding
- [ ] ERROR handling for REGISTER/UNREGISTER/CALL
- [ ] CALL cancelation (basic profile – CANCEL)

## Advanced Profile

### Pub/Sub Enhancements

- [ ] Pattern-based subscriptions (prefix / wildcard with order/priority)
- [ ] Subscription meta events (created, deleted, on/off subscribe)
- [ ] Publisher options (exclude_me, eligible/exclude authid/authrole lists)
- [ ] Payload persist / retained events

### RPC Enhancements

- [ ] Shared registrations with invocation policies (round-robin, random, load)
- [ ] Shared registration meta events
- [ ] Progressive call results (`progress=true`)
- [ ] Call cancellation modes (`kill`, `killnowait`, `killall`) — ensure cancellers can wait for cleanup so subsequent processing shuts down gracefully
- [ ] Caller disclosure (`caller`, `caller_authid`, `caller_authrole`)
- [ ] Sharded registrations / invocation trust level (`trustlevel`)

### Authentication & Authorization

- [ ] Challenge/response (`CHALLENGE`/`AUTHENTICATE`) flow
- [ ] Pluggable authenticators:
  - [ ] Static ticket
  - [ ] WAMP-CRA (HMAC challenge/response)
  - [ ] SCRAM (salted challenge/response)
  - [ ] WAMP-cryptosign / ED25519
  - [ ] Remote authentication executor (delegate auth decisions to external service)
  - [ ] Survey community extensions (GitHub/routers) for additional mechanisms
- [ ] Realm-level authorizers (permission checks before SUBSCRIBE/PUBLISH/etc.)
- [ ] Static TLS cert/SNI configuration pipeline to native runtime
- [ ] Intrusion detection (failed-auth rate limiting, account lockouts, anomaly alarms)

### Introspection & Testing

- [ ] WAMP meta API (session, subscription, registration listings)
- [ ] Caller tracing & diagnostic events
- [ ] Administrative control interface (pause/resume realm, drain connections)
- [ ] Replay/testing hooks (record & replay message streams)

## Tooling & Documentation

- [x] Router example CLI for local testing
- [ ] Developer docs for native runtime build pipeline
- [ ] Configuration reference (realm JSON schema, TLS modes, worker tuning)
- [ ] End-to-end smoke tests (native runtime ↔ router ↔ client)
- [ ] Benchmarks (throughput/latency per worker configuration)
- [ ] MCP (Model Context Protocol) server implementation for agentic AI integrations
- [ ] Metrics & logging integration (Prometheus metrics, structured logs, CPU/RAM/throughput gauges)
