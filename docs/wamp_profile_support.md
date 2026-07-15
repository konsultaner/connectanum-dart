# WAMP Profile Support and Production Readiness

Last audited: 2026-07-15

This matrix uses the current
[WAMP Basic Profile](https://wamp-proto.org/wamp_bp_latest_ietf.html) and
[WAMP Advanced Profile](https://wamp-proto.org/wamp_ap_latest_ietf.html).
The Advanced Profile is modular: implementations may support a subset, but
every supported feature must be announced by the relevant roles. `HELLO` and
`WELCOME` therefore advertise only behavior already covered by package tests.

## Status Terms

- **Implemented** means the relevant client and router behavior exists and is
  covered by package-owned behavioral tests.
- **Partial** means one side or a deliberately limited variant exists and the
  router does not claim the complete feature.
- **Unsupported** means the feature is not announced and must not be assumed by
  a consumer application.

## Basic Profile

The Basic Profile subset required by all six implemented roles is implemented:

| Area | Roles and flows | Status |
| --- | --- | --- |
| Session | Client roles plus Broker/Dealer: `HELLO`, `WELCOME`, `ABORT`, `GOODBYE`, and request `ERROR` flows | Implemented |
| Pub/Sub | Publisher, Broker, Subscriber: publish with and without acknowledgement, subscribe, unsubscribe, and event delivery | Implemented |
| RPC | Caller, Dealer, Callee: register, unregister, call, invocation, yield, result, and error delivery | Implemented |
| Serialization | JSON, MessagePack, and CBOR | Implemented |
| Transport | WebSocket and RawSocket, cleartext and TLS | Implemented |

The repository runs all 22 vendored Basic Profile single-message vector files
against JSON, MessagePack, and CBOR. Package-owned integration tests cover the
multi-session router flows, but only one upstream multi-session vector is
currently vendored. This is strong implementation evidence, not independent
conformance certification.

## Advanced Feature Announcements

The following table covers the complete feature-announcement list in the
current Advanced Profile.

### RPC

| Feature | Spec status | Connectanum status |
| --- | --- | --- |
| Progressive Call Results | stable | Implemented and announced by Caller, Dealer, and Callee |
| Progressive Call Invocations | alpha | Implemented and announced by Caller, Dealer, and Callee; the Dealer pins the callee/invocation and freezes initiating options across chunks |
| Call Timeout | alpha | Implemented and announced by Caller, Dealer, and Callee; Dealer-owned inactivity timeouts and Callee-owned `forward_timeout` are supported |
| Call Canceling | alpha | Implemented and announced, including `skip`, `kill`, and `killnowait` |
| Caller Identification | stable | Implemented and announced |
| Call Trustlevels | alpha | Unsupported |
| Registration Meta API | beta | Implemented and announced; all standard read/statistics procedures and lifecycle events are routed in-realm with authorization-aware visibility |
| Pattern-based Registration | stable | Implemented and announced for prefix and wildcard matching |
| Shared Registration | beta | Implemented and announced with round-robin, first, and last selection policies |
| Sharded Registration | alpha | Unsupported |
| Registration Revocation | alpha | Unsupported at the router |
| Procedure Reflection | sketch | Unsupported |

### Pub/Sub

| Feature | Spec status | Connectanum status |
| --- | --- | --- |
| Subscriber Black/White Listing | stable | Implemented and announced for session, authid, and authrole filters |
| Publisher Exclusion | stable | Implemented and announced |
| Publisher Identification | stable | Implemented and announced |
| Publication Trustlevels | alpha | Partial: the client parses and announces receipt support; the router does not assign or announce trustlevels |
| Subscription Meta API | beta | Implemented and announced; all standard read/statistics procedures and lifecycle events are routed in-realm with authorization-aware visibility |
| Pattern-based Subscription | stable | Implemented and announced for prefix and wildcard matching |
| Sharded Subscription | alpha | Unsupported |
| Event History | beta | Unsupported |
| Topic Reflection | sketch | Unsupported |

### Other Announced Features

| Feature | Spec status | Connectanum status |
| --- | --- | --- |
| Challenge-response Authentication | stable | Implemented for client and router |
| Ticket Authentication | beta | Implemented for client and router |
| Cryptosign Authentication | beta | Implemented for client and router |
| RawSocket Transport | stable | Implemented for client and router |
| Batched WebSocket Transport | sketch | Unsupported |
| HTTP Longpoll Transport | beta | Unsupported |
| Session Meta API | beta | Partial and not announced: all standard read/statistics procedures needed by this release are implemented, but destructive `kill*` administration procedures are not |
| Call Rerouting | sketch | Unsupported |
| Payload Passthru Mode | sketch | Implemented and announced across supported payload-bearing messages |

## Additional Advanced Chapters

The Advanced Profile also describes capabilities outside its central
feature-announcement table:

| Capability | Connectanum status |
| --- | --- |
| Event Retention | Unsupported at the router; message option fields alone are not treated as implementation |
| Subscription Revocation | Partial: the client handles unsolicited `UNSUBSCRIBED`; the router does not actively revoke subscriptions |
| Session Testament | Unsupported |
| Salted Challenge Response / SCRAM | Implemented as a client/router authentication method |
| Dynamic Authentication API | Partial: pluggable and remote authentication exists, but full WAMP Dynamic Authentication API interoperability is not claimed |
| Authorization | Implemented with router realm policies and integration tests |
| Payload E2EE | Implemented for the versioned Connectanum v1 release profile: standard PPT fields, CBOR, XSalsa20-Poly1305, AES-256-GCM, negotiated/policy key selection and rotation, Dart/native providers, opaque router forwarding, and fail-closed validation; FlatBuffers is unsupported |
| Binary values in JSON | Implemented with WAMP's NUL-prefixed Base64 representation |
| Message batching and multiplexed WAMP transport | Unsupported |
| WAMP IDL, interface catalogs, and interface reflection | Unsupported as WAMP features; MCP catalogs are a separate API surface |
| Router-to-Router Links | Unsupported as the standardized WAMP RLink feature |

## Conformance Evidence

- The single-message suite vendors 22 Basic and 3 Advanced vector files and
  runs each applicable vector through JSON, MessagePack, and CBOR.
- Package-owned router tests cover cancellation, progressive results and
  invocations, call timeouts, Registration/Subscription/Session statistics
  Meta API calls, Meta lifecycle events, pattern subscriptions and
  registrations, shared registrations, publisher identity, publisher
  exclusion, eligibility filters, authentication, authorization, payload
  passthrough/E2EE, and serializer bridging.
- The only vendored upstream multi-session vector currently covers publisher
  exclusion. Expanding upstream multi-session vectors remains the main
  protocol-certification gap.

## Benchmark Evidence

The latest hosted
[WAMP Profile Benchmarks run 29084302142](https://github.com/konsultaner/connectanum-dart/actions/runs/29084302142)
passed on commit `5034dc7` with 70 workloads and no transport-counter or
performance-policy findings. It covers cleartext and TLS, RawSocket and
WebSocket, RPC and pub/sub, JSON/MessagePack/CBOR, control cycles, and
eight-subscriber native fan-out.

| Gate family | Throughput above policy floor | p95 below policy ceiling |
| --- | ---: | ---: |
| Cleartext transport throughput | 114% to 199% | 36% to 76% |
| TLS transport throughput | 100% to 149% | 58% to 72% |
| Eight-subscriber fan-out | 169% to 565% | 62% to 66% |

These margins are comfortably production-grade for the measured baseline, but
the hosted gate currently uses one Linux x86_64 runner, one router worker, one
native runtime thread, and short samples. It does not yet gate soak duration,
CPU, memory, file descriptors, or multi-worker scaling.

The 2026-07-15 local release gates add the previously missing final-feature
evidence:

| Gate | Coverage | Local result |
| --- | --- | --- |
| `wamp_e2ee_throughput.json` | 16 encrypted RPC/pub-sub rows; RawSocket/WebSocket; Dart/native; XSalsa20-Poly1305/AES-256-GCM | Passed; 1.77-13.90 Mbps, 262.73-2824.47 ms p95 |
| `wamp_final_release_features.json` | 12 progressive invocation, timeout, and full 15-procedure Meta statistics sweep rows; RawSocket/WebSocket; Dart/native | Passed |

Across the final-feature matrix, progressive rows delivered 0.45-1.79 Mbps at
8.12-25.41 ms p95, 50 ms timeout rows completed at 55.38-59.49 ms p95, and
full Meta sweeps completed at 11.17-33.22 ms p95. Every transport,
backpressure, protocol, and internal error counter remained zero. Hosted
evidence for these new gates is still required after push.

## Readiness Verdict

The Basic Profile and the announced Advanced subset, including the four final
release capabilities, are suitable for a controlled production deployment
with workload-specific load testing. The evidence does not support a claim
that every Advanced Profile feature is implemented, nor a blanket production
certification for arbitrary topology or load.

Before a general production declaration, add:

1. A hosted multi-worker and multi-runtime-thread benchmark gate.
2. Soak tests with CPU, memory, connection, and file-descriptor budgets.
3. More upstream multi-session conformance vectors for the announced Advanced
   features.
4. Performance gates for the remaining announced features, including
   cancellation, progressive results, pattern routing, shared registration,
   eligibility filtering, and unencrypted payload passthrough.
