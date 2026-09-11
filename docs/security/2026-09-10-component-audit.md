# Component Security Audit

Status: in progress. This is not a security certification or a completed review
of the package family. The coverage matrix and remaining gates are tracked in
the [active plan](../exec-plans/2026-09-10-component-security-audit.md).

## Scope And Threat Model

Baseline: `733c6d914a88d5058a8f1c574a545560026337d5`, package version
`3.0.0-beta.5`. Review includes the seven Dart packages, native transport/FFI
and benchmark crates, standalone consumer application, CLI/configuration,
dependency graph, and release workflows. Adversaries include unauthenticated
network peers, authenticated low-privilege realm members, malicious remote
services/clients, and compromised package/build inputs. Operator-configured
trusted capabilities must be distinguished from accidental privilege exposure.

## Confirmed Findings

### SA-001: Remote Auth Service Admission Precedes State Mutation

**Impact: availability and authentication-accounting integrity; moderate with
the prerequisites below. Fixed and verified locally.**

The standalone auth service validated `auth_token` after removing the pending
transaction on AUTHENTICATE. Invalid-token HELLO requests could also allocate or
overwrite fake-challenge state and record a failed attempt against an
attacker-supplied auth identity. Independently, the WAMP procedure binding
removed its own pending state before checking credentials on AUTHENTICATE and
ABORT, or when HELLO returned failure. Fixing only one map would not protect a
real service exchange.

Prerequisites: access to the auth-service RPCs despite lacking the additional
shared service token. Destroying a particular in-flight exchange additionally
requires its opaque transaction ID; the router generates cryptographically
random IDs. Invalid-token fake-state allocation and claimed-identity failure
accounting do not require knowing an existing ID. This is not evidence of
account takeover, key recovery, or an anonymously reachable service under
correct realm ACLs and mTLS admission.

The fix validates service credentials before either layer accesses pending
state. Rejected service credentials do not count as failures of the claimed
user. Identity masking still works after service admission. Invalid service
credentials now receive `status: failure` / `wamp.error.not_authorized`, even
when fake challenges are enabled. Token-free trusted configurations remain
supported. Successful ticket/CRA/SCRAM response construction is unchanged.

AUTHENTICATE and ABORT payloads are fully parsed before consuming a challenge.
Wrongly typed optional maps/strings now return `wamp.error.invalid_argument`
instead of silently becoming absent values. Omitted/null optional fields keep
their existing behavior.

Evidence:

- Direct service regressions fail in 13 cases on unchanged production code;
  the fixed suite passes all 25 tests. Missing, incorrect, and non-string service
  tokens are covered with fake challenges on/off, including legitimate retry,
  no unsolicited fake transaction, no user lockout, and no user audit poisoning.
- Two live RawSocket/mTLS regressions fail before the fix. All eight remote-auth
  integration tests pass afterward, covering all three RPCs, malformed admitted
  requests, legitimate continuation, credential rotation/reconnect, permission
  enforcement, malformed service responses, and timeout behavior.
- Performance: 12 alternating before/after passes completed 60,000 measured
  logins and 14,400 warmup logins with no errors. See the comparison below.

Residual auth-service review: admitted-caller transaction ownership/collisions,
expiry and aggregate pending-state bounds, asynchronous cancellation/cleanup,
error sanitization, and token rotation policy still need independent review.

### SA-002: Resolved Native Network Dependencies Have Published Advisories

**Transport and benchmark dependency mitigations are implemented; final full
verification and production-budget gates pass. Before/after performance
confirmation remains open.**

The initial `cargo audit` against both locally resolved Rust lockfiles on
2026-09-10 reported the following. These lockfiles are ignored by the repository,
not checked in; security minimums must therefore be enforced in the manifests.

| Dependency | Resolved | Advisory | Scope / next action |
| --- | --- | --- | --- |
| `h2` | `0.3.27` | [RUSTSEC-2026-0258](https://rustsec.org/advisories/RUSTSEC-2026-0258.html) | Direct `ct_core` HTTP/2 dependency; empty DATA frame queuing can exhaust memory when streams are not drained. Migrate to patched `>=0.4.16` and validate HTTP type compatibility and HTTP/2 performance. |
| `quinn-proto` | `0.11.14` | [Upstream advisory](https://github.com/quinn-rs/quinn/security/advisories/GHSA-4w2j-m93h-cj5j), RUSTSEC-2026-0185 | Direct/transitive native QUIC dependency; excessive out-of-order gaps can exhaust memory. Patched `>=0.11.15`; inspect upstream mitigation and test HTTP/3 performance after updating. |
| `rustls-webpki` | `0.101.7` | RUSTSEC-2026-0104, RUSTSEC-2026-0098, RUSTSEC-2026-0099 | Benchmark-control `reqwest` 0.11.27 / `hyper-rustls` 0.24.2 / `rustls` 0.21.12 dependency, not the production router TLS server. Control client intentionally trusts lab certificates and uses HTTP/1; assess advisory-specific reachability and update this older client dependency. |

The transport manifests now require `h2 >=0.4.16` (within 0.4) and
`quinn-proto >=0.11.15` (within 0.11). The HTTP/2 adapter and FFI test client now
use the existing `http` 1.x dependency instead of a second 0.2 type graph.
Production window sizes, concurrency limits, body readers, public FFI ABI, and
TLS policy are unchanged. The tested local candidate resolves `h2 0.4.19` and
`quinn-proto 0.11.17`. Its transport audit reports zero published vulnerabilities;
the maintenance warnings below remain. The benchmark's independent graph is
also upgraded: reqwest 0.13.5 uses Rustls 0.23, h2/QUIC enforce the same minima,
and the unused ureq dependency is removed. Hyper 0.14 remains only for HTTP/1;
its old HTTP/2 feature is disabled, and the two H2 test servers use h2 directly.
The resolved benchmark audit now has zero vulnerabilities and zero warnings.

The benchmark scan also reported
[RUSTSEC-2026-0190](https://rustsec.org/advisories/RUSTSEC-2026-0190.html), an
`anyhow::Error::downcast_mut` unsoundness warning. No such call is present in the
benchmark source, so this was not demonstrated as reachable from a peer. The
manifest nevertheless requires patched `anyhow >=1.0.103` and resolves 1.0.104.
The tested benchmark graph resolves h2 0.4.19, quinn-proto 0.11.17, reqwest
0.13.5, and Rustls 0.23.38. Local lockfile SHA-256 values are
`13497ce8aaca9fd23ea45d21d9ae809aebeb8439a881a6695ce291d3b3c9e447`
(benchmark) and
`2c4a72fb955b5a3a5a4c7401ccba40c8500b3d561f5682ae345472127d101fe8`
(transport). These describe tested resolutions, not committed lockfile pins.

Attack prerequisites: a malicious HTTP/2 or QUIC peer on an enabled native
endpoint. The affected parsers operate before application authorization.
The demonstrated impact is resource exhaustion, not a proof of code execution,
authentication bypass, or payload disclosure. TLS does not make malicious
authenticated transport frames safe.

Four bounded raw-frame regressions use the actual production HTTP/2 builder
over Tokio duplex I/O. A PING ACK forms a processing barrier while the request
body is deliberately not drained. Both plain and padded empty DATA were queued
on `h2 0.3.27`, and 101-frame floods were accepted: all four tests failed before
the upgrade. The candidate discards nonterminal empty frames, preserves payload
and terminal-empty END_STREAM behavior, and sends `ENHANCE_YOUR_CALM` GOAWAY for
both floods. All four pass. This is a protocol-adapter regression, not a public
TCP/TLS attack replay; the existing live FFI network tests provide separate
positive-control transport coverage.

The bounded [QUIC assembler probe](../../tool/quinn_assembler_security_probe.rs)
compiles the resolved upstream assembler and range-set sources verbatim without
vendoring or modifying production dependencies. With each one-byte fragment
retaining a separate 1,500-byte packet allocation, a missing prefix, and gaps,
`0.11.14` accepted all 4,096 fragments without a limit error. Both `0.11.15` and
the resolved `0.11.17` reject at fragment 1,034. The same probe verifies ordinary
reordering and overlapping data still reconstruct all 2,000 expected bytes.
This is source-level upstream evidence, **not** an encrypted QUIC packet replay
through Connectanum; that deeper transport/FFI review remains open.

Expanded `ffi-test` execution exposed three previously unselected event fixtures
with native TLS enabled but no certificate. They now use an existing test
identity, and the synthetic idle event asserts the GOAWAY counter actually
supplied to the hook. No production validation or live timeout expectation was
relaxed. All 97 feature-enabled FFI tests pass. `bin/verify` now runs this entire
suite rather than only the metrics test; a fail-first script regression protects
the broader gate. The former benchmark WebPKI 0.101 graph is no longer resolved.
Its control client still uses HTTP/1 only and accepts self-signed lab identities;
that explicit benchmark-only policy has not moved into production code. A live
TLS test offers both h2 and HTTP/1.1 and verifies that control requests negotiate
HTTP/1.1. Other regressions cover preserved binary-request headers, invalid
bearer-header rejection, a multi-frame UTF-8 JSON request, and a large 401 response
without status/body loss. All 74 HTTP-driver and 29 artifact library tests pass.
Existing connection-reuse, chunking, H2/H3 multiplexing, and timeout tests remain.
The complete native benchmark suite is now in `bin/verify`, protected by another
fail-first script regression; all 24 verification-script tests pass.
An isolated invocation of the control-timeout test exposed reliance on another
test installing Rustls's process-wide crypto provider. It now installs the same
ring provider explicitly and passes independently, matching the existing CLI
startup without changing runtime client policy.

The RustSec database used for the scan was commit
`b50980aad8b8f14f77e25a97b32dd94bf008b0af` (updated 2026-09-09). Reproduce with
`cargo audit --file native/transport/Cargo.lock` and
`cargo audit --file native/bench/Cargo.lock`.

The transport lockfile additionally reports maintenance warnings for
`rustls-pemfile`, `serde_cbor`, and the renamed `xsalsa20poly1305` crate. These
are maintenance risks, not proof of exploitable vulnerabilities. Dart and
standalone-application dependencies were also queried below; platform-native
dependencies and bundled assets still need separate review.

For the HTTP/2 regressions, run
`cargo test --manifest-path native/transport/Cargo.toml -p ct_core http2_security_tests`.
The source-level QUIC probe is intentionally outside normal Cargo targets so
building a consumer package never depends on a registry-cache source path.
To reproduce it, build `ct_core` with `--message-format=json`, obtain the `bytes`
`.rlib` from its compiler-artifact records, and obtain the resolved `quinn-proto`
`src` directory using its manifest location from `cargo metadata`. Compile
`tool/quinn_assembler_security_probe.rs` with Rust 2021, that directory in
`QUINN_PROTO_SOURCE`, `--extern bytes=<rlib>`, and
`-L dependency=native/transport/target/debug/deps`, then run the resulting binary.
The same probe compiles against the old void-returning assembler and patched
Result-returning assembler; its failure is a missing runtime rejection, not a
compile-time API mismatch. The fixture allocates at most a few MiB and uses no
network access or real user traffic.

### SA-003: Remote Authentication Transaction Lifecycle

**Confirmed availability and lifecycle-integrity defects. Authentication-only
candidate and full verification pass; the six-pass before/after comparison below
is provisional on this shared host. Not published. Router dispatch is unchanged.**

Six deterministic direct-service tests fail on unchanged `1bc60ef1`:
aborting during factory creation does not prevent late HELLO, aborting during
HELLO or AUTHENTICATE does not suppress late success, duplicate HELLO overwrites
an existing challenge, in-flight factory creation bypasses the configured
pending limit, and a challenge remains usable exactly at its expiry deadline.
The service also lacks automatic eviction of abandoned challenges. These are
not proof of credential bypass or account takeover. Service-token/realm
admission still applies, and targeting a specific transaction requires its ID.

The candidate reserves a single shared transaction record before any provider
await, rejects duplicate IDs without changing the original record, and retains
the record throughout AUTHENTICATE. Timer expiry, abort, and shutdown invalidate
late results. The binding uses this same registry instead of maintaining a
second challenge map. Binding identity prevents one binding's close/abort from
invalidating another binding's work; the public RPC schema and old Dart import
URI remain available. Direct continuation checks realm, auth identity, session,
and transport metadata against the admitted context.

Capacity is per configured realm and includes unfinished factory/provider work,
real/masked challenges, and abort cleanup. Cancelling the caller's future does
not release capacity while underlying uncooperative work is still running.
Provider futures cannot be forcibly stopped: cleanup runs once after the active
callback settles, and a hung provider retains its bounded slot.
`pendingAuthenticationCounts` exposes occupied slots for operator inspection.
Positive timeouts now cover the entire attempt from admission; nonpositive
capacity/timeouts preserve existing operator opt-out semantics. Late errors
are caught without logging provider exception contents or poisoning an
aborted identity's failure accounting.

All 41 auth-service tests pass, including 16 lifecycle tests with controllable
completers and fake-clock/timer coverage. Three new mTLS tests exercise
in-flight HELLO deadline expiry, duplicate challenge preservation, and closing an active
AUTHENTICATE while a separate binding remains usable; all 11 live remote-auth
tests pass. The prior fake-identity test now continues with the identity returned
by its fake challenge rather than changing identity midway through the attempt.
Separate negative tests preserve the original challenge after mismatched
identity/transport continuation and abort attempts.

An additional live abort experiment exposed router head-of-line blocking:
dispatch to an in-process callee awaits its full response before signalling
readiness. A later abort RPC cannot reach the service while that worker is
waiting. The failure reproduced on both the original connection and a second
connection sharing the worker. Temporarily detaching response waiting made the
same-connection regression pass, but the experiment was removed after the native
lifetime review below. The retained live test proves timer cancellation without
depending on another CALL reaching the blocked worker; it is not evidence that
same-connection RPC cancellation is fixed. Direct service abort is covered by
deterministic provider/factory cancellation tests.

The first full verification attempt with the dispatch experiment failed one
worker test whose completion assumption was no longer valid, and one native
HTTP/3 direct-JSON test with a 30-second timeout/handshake failure. The separated
patch passes all 85 unchanged worker-session tests plus the 11 remote-auth tests.
Fresh full verification passes, including the previously timed-out HTTP/3 test,
all router/live MCP and zero-copy tests, public package/CLI smokes, and
Chrome/Dart2Wasm. The initial failed run remains recorded, not treated as green.

Protocol basis: WAMP
[session lifecycle](https://wamp-proto.org/wamp_bp_latest_ietf.html) makes ABORT
terminate opening rather than authorize a later WELCOME, and
[challenge authentication](https://wamp-proto.org/wamp_ap_latest_ietf.html)
requires success/failure to correspond to the current handshake. Remote RPC
transaction IDs and service capacity are Connectanum implementation policy, not
additional WAMP wire messages or a claim that WAMP mandates a particular limit.

**Router dispatch/native ownership candidate at the SA-003 checkpoint:**
in-process lazy payloads are reconstructed from native addresses, while the
worker releases its retained handle when the reply port completes. Verify
cancellation/disconnect and escaped lazy-view ownership before accepting more
concurrent dispatch. The dispatch experiment is not part of this patch.
A raw-pointer view with an ordinary metadata-map anchor is
not, by itself, evidence of native allocation ownership. SA-004 below subsequently
established deterministic lifetime regressions; no exploitation is demonstrated.
This review must not be replaced by merely observing that the auth tests pass.
Any follow-up fix must preserve zero-copy ownership across application-retained
views and prove cancellation, normal reply, disconnect, and isolate teardown
without reading potentially freed memory in a test.
The resolved MessagePack decoder also defaults to borrowed binary data, so
materializing a generic message is not automatically an ownership fix. In
contrast, the auth RPC adapter normalizes its schema recursively into new
lists/maps before awaiting the provider, including nested byte lists. Do not
generalize that auth-specific boundary to generic internal handlers.
Broader remote-auth delegation, router HTTP-auth admission, binding registration
failure cleanup, provider error policy, and cross-service trust remain in scope.

### SA-004: Native Payload Views Outlive Their Routing Handles

**Confirmed native allocation-lifetime defect. Local ownership mitigation and
full verification pass; performance and additional cancellation review remain
in progress. Not published.**

Both native client and router materializers exposed `Uint8List` views directly
over `StoredMessage` buffers. Explicit handle release, routing completion, or
runtime shutdown could remove the final native owner while application code
still held a byte view or a lazily decoded binary value. Internal-session CALLs
also reconstructed views from integer addresses sent between isolates, without
first acquiring receiver-side ownership. Cancellation could invalidate a queued
transfer or an already-delivered handler's payload.

Prerequisites: use of the native runtime and application code retaining payload
bytes beyond the routing handle's lifetime. The live regression uses an ordinary
authorized WebSocket CALL to an internal service, retains a subview, replies,
then closes the sessions/router. No malformed frame or privileged native pointer
input is required. This is a use-after-free risk, not demonstrated code execution
or proven extraction of another session's data. The fail-first probes check a
test-only Rust `Weak<StoredMessage>` before any post-release byte access, and stop
when the allocation is gone; they never deliberately read freed memory.

The new native export API clones the message's `Arc` while its store entry is
locked and returns an independent owner token for the selected slice. Dart
attaches a native release callback to the external typed-data backing store,
not merely to the message wrapper. Frame, argument, keyword, details, and
supported sole-binary invocation views retain storage without copying payloads.
Releasing a routing handle does not release those owners. On older libraries
without the paired export/free symbols, the shared client/router helper uses
owned Dart copies rather than exposing unowned memory. That compatibility path
does copy data and is not claimed to retain zero-copy performance.

Internal-session receivers now retain the transmitted handle before consulting
native message info. Expired transfers fail closed without dereferencing their
old addresses. Generic payload decoding refuses native-transfer metadata unless
an owned message is supplied. Reply fallback copies from the originating owned
message, not addresses in a returned metadata map; the existing native-forwarded
echo path remains available. This does not change WAMP wire formats, serializers,
session authentication, or router authorization policy.

The design follows Dart's [external typed-list finalizer API](https://api.dart.dev/dart-ffi/Uint8Pointer/asTypedList.html)
and [native finalizer lifetime contract](https://api.dart.dev/dart-ffi/NativeFinalizer-class.html).
The callback is a real native `void(void*)` function dropping an owner token,
not a cast of the integer-handle release API. Normal isolate-group shutdown is
covered; abrupt process termination is not a cleanup guarantee.

Evidence:

- All six original fail-first cases, client/router times JSON/MessagePack/CBOR,
  observed native allocation destruction while byte views were live. The fixed
  tests pass and also exercise runtime shutdown, repeated release, expired
  receiver transfers, and MessagePack/CBOR sole-binary invocation views.
- Four Rust tests pass: exact pointer and byte identity for exported frame,
  argument, keyword, and details slices; lazy segmented-frame preservation and
  store clearing; missing/invalid exports; and 100 export/release races. Weak
  observers reach zero once the last exported owner is freed.
- A live internal-session WebSocket regression passes after reply and router
  shutdown. It verifies native allocation liveness before reading the escaped
  subview. The existing lazy subscriber/callee regression also passes.
- An independent isolate group retains only a subview, reads it after the
  sending handle and runtime are released, and exits normally. The observing
  group then verifies that the native allocation was destroyed. All 11 focused
  tests pass with both the new ownership ABI and the older-library copy path.
- Full `bin/verify` passes, including 494 router tests, 11 live remote-auth
  tests, 13 zero-copy tests, 124 benchmark tests, native FFI/benchmark suites,
  package/MCP smokes, and Chrome/Dart2Wasm. One earlier resumed fast run caught a
  transient integration compile error, since corrected. An overlapping focused
  run failed to acquire the verification process's runtime lock; the subsequent
  isolated run passes. Neither failure is hidden as passing baseline evidence.

The six-pass before/after comparison below completed without errors but exposed
RPC throughput and memory regressions. Performance is not cleared.
Still required: ownership-path profiling/optimization and confirmation, the
large-frame/file performance gates, fuller live cancellation/late-delivery coverage, and review
of separately owned JSON/E2EE/external buffers. Native integer-handle exhaustion
and mutable byte aliases also remain review candidates, not closed findings.

### SA-004 Initial Performance Evidence

[Machine-readable comparison](2026-09-10-native-message-lifetime-benchmarks.json)
preserves every run's workload statistics, process memory, transport counters,
CPU observations, exact commands, binary hashes, and the complete scenario TOML.
The run uses the same patched HTTP driver, one router worker, four native runtime
threads, and separately built AOT service/client executables. Baseline service
source is `26bc6234`; the preserved baseline client executable predates the
auth-only work, which did not change client code. Both native libraries contain
the SA-002 dependency updates. This comparison changes the SA-004 client, router,
and native ownership implementation together; it is not yet an attribution
profile of individual costs.

Order is baseline/candidate/candidate/baseline/baseline/candidate. Each process
runs actual warmup requests immediately before each measured workload: 184,176
measured operations and 11,160 warmup operations in total, with no request or
transport-error counter failures. Rates below count request plus response
application payload during the measured data window, not network wire bytes;
warmups are excluded. Lifecycle timings and tail latencies are retained in the
artifact rather than conflated with payload throughput.

| Workload | Baseline Gbit/s | Candidate Gbit/s | Median change |
| --- | ---: | ---: | ---: |
| Native RawSocket JSON RPC, 1 KiB serial | 0.00627 | 0.00624 | -0.5% |
| Native RawSocket MessagePack RPC, 64 KiB | 9.080 | 9.334 | +2.8% |
| Native RawSocket CBOR RPC, 64 KiB | 9.572 | 8.409 | -12.1% |
| Native WebSocket MessagePack RPC, 64 KiB | 9.772 | 9.193 | -5.9% |
| Native WebSocket CBOR RPC, 64 KiB | 9.552 | 9.182 | -3.9% |
| Native RawSocket CBOR pub/sub, 64 KiB | 0.781 | 0.773 | -1.0% |
| Native WebSocket MessagePack pub/sub, 64 KiB | 2.086 | 2.060 | -1.2% |
| Dart RawSocket CBOR RPC, 64 KiB | 9.223 | 8.885 | -3.7% |
| Native RawSocket MessagePack RPC, 32 MiB | 38.175 | 34.465 | -9.7% |
| Native RawSocket CBOR RPC, 64 MiB | 37.005 | 33.922 | -8.3% |

The 64 MiB workload's median observed server RSS rises from about 173 MiB to
315 MiB and client peak RSS from 321 MiB to 380 MiB. Its median p99 rises from
27.839 ms to 32.797 ms. The 32 MiB workload's median p99 rises from 21.866 ms to
25.892 ms. Larger retained allocations and repeated receiver materialization
are profiling candidates, not yet proven explanations. Optimizations must retain
the tested lifetime guarantees, not detach owners early or hide allocation costs.

The host is shared: a VM and emulators remained active, and a brief unrelated
inference load was observed before the fourth process. No audit tests, builds,
or local-companion inference overlapped the measured run. All observations,
including that baseline pass, are preserved. These uncertainties do not justify
calling the repeated RPC decreases harmless. **Do not publish this candidate or
claim unchanged speed until the affected paths are optimized and remeasured.**

### SA-004 Metadata Ownership Optimization

The first candidate gave every details/options byte view an owner of the entire
native message. Lazy metadata loaders could therefore retain a large payload
even when only metadata remained relevant. Six additional fail-first regressions
reproduced that retention across client/router and all three serializers. The
client fixture explicitly materializes `NativeSessionMessage`; an initial direct
`Result` cast was corrected before recording the six valid failing probes.

Metadata now uses `NativeMessageBytes.withCopiedBytes`: acquire and validate the
native owner, copy details into a Dart-owned list, synchronously copy the other
metadata strings under that owner, then free the temporary owner in `finally`.
Lazy metadata retains only Dart storage. Frame, argument, keyword, and binary
payload views keep the original zero-copy backing-store ownership. There is no
native ABI, WAMP wire, serializer negotiation, or cryptographic change.

All 20 focused cases pass, including callback success/failure after releasing
the original handle and shutting down the runtime, stale handles, deliberately
mismatched pointers/lengths, and all previous payload/subview/isolate-group
tests. The legacy ABI passes its 17 applicable cases; three tests specifically
requiring native owner tokens are skipped there. Local bounded review found no
concrete bug; its export-disagreement cleanup concern is explicitly covered.
The initial heavyweight review exhausted its response limit and is not counted
as completed review evidence. Full `bin/verify` passes with 503 router tests and
all existing native, benchmark, live MCP, package, and Chrome/Dart2Wasm gates.

[The first repeat](2026-09-10-native-metadata-lifetime-benchmarks.json) and
[the lower-inference repeat](2026-09-10-native-metadata-lifetime-quieter-benchmarks.json)
each retain all six ABBAAB runs, 184,176 measured operations, 11,160 actual warmup
operations, zero errors, exact binaries/commands, scenario, memory, tails, and
CPU observations. The former encountered roughly 2200% unrelated inference CPU.
The latter had much lower inference activity, but a VM, emulator, and other CPU
activity remained; it is not a dedicated-host measurement. No audit tests,
builds, or companion inference overlapped either comparison.
The candidate was built and verified with Dart 3.13.1 on macOS arm64; the local
Rust toolchain is rustc 1.95.0. The same frozen native library and HTTP driver
were used for both metadata repeats; no unrecorded native rebuild is substituted.

| Lower-inference workload | Baseline Gbit/s | Candidate Gbit/s | Median change |
| --- | ---: | ---: | ---: |
| Native RawSocket JSON RPC, 1 KiB serial | 0.00676 | 0.00638 | -5.6% |
| Native RawSocket MessagePack RPC, 64 KiB | 8.628 | 8.951 | +3.7% |
| Native RawSocket CBOR RPC, 64 KiB | 9.327 | 9.091 | -2.5% |
| Native WebSocket MessagePack RPC, 64 KiB | 8.827 | 9.019 | +2.2% |
| Native WebSocket CBOR RPC, 64 KiB | 9.073 | 8.861 | -2.3% |
| Native RawSocket CBOR pub/sub, 64 KiB | 0.777 | 0.771 | -0.8% |
| Native WebSocket MessagePack pub/sub, 64 KiB | 2.118 | 2.044 | -3.5% |
| Dart RawSocket CBOR RPC, 64 KiB | 9.014 | 8.717 | -3.3% |
| Native RawSocket MessagePack RPC, 32 MiB | 38.751 | 35.549 | -8.3% |
| Native RawSocket CBOR RPC, 64 MiB | 37.544 | 34.330 | -8.6% |

Large-frame p99 rises from 20.128 to 25.873 ms (32 MiB) and from 28.201 to
35.322 ms (64 MiB). The latter's median observed server RSS remains higher,
about 169 MiB versus 309 MiB. Copying metadata fixes its independent retention
problem, but does not explain away or resolve the payload performance cost.
Diagnostic OS samples of the frozen first candidate lacked Dart symbols, so
they do not establish a CPU hotspot. Next targets are redundant receiver-side
full-message materialization and per-export native owner allocations. Preserve
both lifetime guarantees and truthful external-memory accounting.

The full 24-workload large-frame matrix, eight-workload heavy file-transfer
matrix, and 30-workload file matrix pass their unchanged counter, throughput,
and lifecycle budgets. They cover 864 large-frame samples (24 GiB request plus
response), 190 heavy file transfers (24 GiB), and 408 matrix file transfers
(25.5 GiB), with no errors. The
[production gate evidence](2026-09-10-native-ownership-production-gates.json)
retains each workload, policy, report, and candidate binary identity. The nine
canonical profile scenarios last passed on SA-002; rerun them for the finalized
ownership candidate as well. These are absolute gates, not
before/after clearance. **The candidate remains local and must not be published
while the roughly 8% large-frame regression remains unresolved.**

### SA-004 Direct Arc Owner Tokens

The native slice exporter now transfers its already-acquired `Arc<StoredMessage>`
reference directly instead of allocating a separate `Box<Arc<StoredMessage>>`
for each export. Its paired finalizer reconstructs and drops that one reference.
This follows the standard library's documented
[Arc raw-pointer ownership contract](https://doc.rust-lang.org/std/sync/struct.Arc.html#method.into_raw).
Separate exports can have equal token addresses; each successful export still
owns a separate reference and must be freed once. Consumers must not deduplicate
tokens by address. Payload pointers, zero-copy storage, Dart finalizers, external
memory accounting, serializer behavior, and the ABI shape are unchanged.

The new fail-first regression releases the routing handle, verifies four strong
references, frees one token, verifies three references, concurrently frees the
rest, and verifies zero references. Its allocation-reuse assertion fails on the
boxed implementation only after safe cleanup; no freed payload is read. All five
focused Rust ownership tests pass after the change. Bounded local review did
not establish another defect: failed exports drop their local Arc, null-free
already has a regression, and equal token addresses do not imply duplicate
ownership. Freeing a single acquired reference twice remains invalid native API
use; deliberately invoking undefined behavior is not a valid negative test.

Fresh `bin/test-fast` and `bin/verify` pass. Verification includes 142 Rust core,
95 default FFI, 102 test-hook FFI, 29 native artifact, 74 HTTP-driver, and 503
router tests, plus the existing package, live MCP, and Chrome/Dart2Wasm gates.
The measured library is the release `ffi-test` output actually built by
`bin/verify`, not the older library left in the ordinary release directory.
Its SHA-256 is
`77f12083ff5e54dc299f7749f41dedda0f4b1b4d4267f420baaec6979bb6ca76`.

The [two comparisons](2026-09-10-native-arc-owner-benchmarks.json) each retain
six ABBAAB passes, 184,176 measured operations, 11,160 warmup operations, zero
errors, commands, hashes, scenario, CPU, memory, and latency summaries.
The incremental comparison changes only the native library and keeps identical
metadata-optimized Dart executables. Its 32 MiB MessagePack median falls 1.3%;
64 MiB CBOR improves 4.1%. Other results are mixed. This removes one allocation
per nonempty export, but is not evidence that the full security fix has no cost.

| Full baseline comparison | Baseline Gbit/s | Candidate Gbit/s | Median change |
| --- | ---: | ---: | ---: |
| Native RawSocket JSON RPC, 1 KiB serial | 0.00626 | 0.00626 | +0.04% |
| Native RawSocket MessagePack RPC, 64 KiB | 9.811 | 9.015 | -8.1% |
| Native RawSocket CBOR RPC, 64 KiB | 9.768 | 8.282 | -15.2% |
| Native WebSocket MessagePack RPC, 64 KiB | 9.579 | 9.548 | -0.3% |
| Native WebSocket CBOR RPC, 64 KiB | 9.508 | 9.090 | -4.4% |
| Native RawSocket CBOR pub/sub, 64 KiB | 0.795 | 0.780 | -1.9% |
| Native WebSocket MessagePack pub/sub, 64 KiB | 2.082 | 2.076 | -0.3% |
| Dart RawSocket CBOR RPC, 64 KiB | 9.366 | 8.484 | -9.4% |
| Native RawSocket MessagePack RPC, 32 MiB | 40.499 | 35.894 | -11.4% |
| Native RawSocket CBOR RPC, 64 MiB | 38.912 | 34.595 | -11.1% |

Large-frame median p99 increases from 22.930 to 24.879 ms and from 25.690 to
33.559 ms, respectively. Median observed server RSS for the 64 MiB case rises
from about 171 MiB to 313 MiB. Inference remains near idle, but unrelated VM
activity ranges from about 132% to 568% at run boundaries. Preserve every pass;
these remain shared-host observations, not dedicated production-binary proof.
No audit build, test, or companion inference overlapped the comparisons.

The optimized library also passes all 62 unchanged
[large-frame and file gates](2026-09-10-native-arc-owner-production-gates.json):
24 large-frame workloads / 864 samples / 24 GiB request plus response,
eight heavy-file workloads / 190 transfers / 24 GiB, and 30 file-matrix workloads
/ 408 transfers / 25.5 GiB, without errors or counter/metric findings.
**Relative performance is still not cleared.** Keep the candidate local. Next,
reduce redundant receiver-side materialization without weakening ownership,
repeat the comparisons and finalized production-library/profile gates, and
continue the full audit's outstanding cancellation and external-buffer reviews.

### SA-004 Payload-Only CALL Receiver

Internal native CALL receivers now acquire only independent argument and keyword
views, rather than materializing a complete `NativeIncomingMessage`, parsing its
metadata, and attaching an immediately disposed routing-handle finalizer. The
temporary retained handle is released on every helper exit, including allocation,
peek, validation, and export failure. Message code and serializer must match
before byte exports occur. The original sender handle is not consumed. Empty
payloads need no byte owner; nonempty backing stores retain their independent
owners, and old native libraries still return Dart-owned copies. Generic message
materialization, wire encoding, and external-memory accounting are unchanged.

The internal producer uses the exact `json`, `messagePack`, and `cbor` encoding
names and excludes PPT/transparent-binary messages from this shortcut. Local
review's encoding-mismatch concern was checked against that producer, not assumed
to be a remote wire incompatibility. This is a narrower receiver contract and
ownership optimization, not an additional demonstrated remote vulnerability.

All 31 focused lifetime cases pass, including JSON/MessagePack/CBOR arguments and
keywords, empty CALLs, serializer/type mismatch without leaked handles, expired
handles, and escaped subviews surviving original-handle release and shutdown.
Normal isolate-group cleanup releases payload-only owners. The legacy-library
run passes 28 cases with three native-owner-specific skips; all 14 live WebSocket
tests and router analysis pass. Full `bin/verify` passes, including 514 router,
102 test-hook FFI, 95 default FFI, and the existing live MCP, package, remote-auth,
zero-copy, and Chrome/Dart2Wasm gates.

The first pre-change fast gate caught absolute repository paths in the previous
Arc production-gate artifact, which had been added after that checkpoint's full
verification. Those command/checker paths are now repository-relative, with an
explicit convention; measurements and binary hashes are unchanged. Corrected
`bin/test-fast` and full verification pass. Newly generated artifacts are also
normalized and checked by the public-reference guard after generation.

The [full and incremental comparisons](2026-09-10-native-call-payload-benchmarks.json)
each retain six ABBAAB passes, 184,176 measured operations, 11,160 warmups, and
zero errors. Source fingerprints, runner sources, frozen binary identities,
commands, raw hashes, scenarios, CPU, memory, and latency remain available.
Embedded runner sources normalize repository paths for privacy; their hashes
identify the original local scripts before normalization, not the displayed text.
The new AOT service SHA-256 is
`17a0c6fd8028ae0ac366677554bcd388eb7bfdd8403194830e6a47b573319885`.
The incremental comparison changes only that service; the Arc native library,
client executable, and HTTP driver are identical on both sides.

| Full pre-SA-004 baseline comparison | Baseline Gbit/s | Candidate Gbit/s | Median change |
| --- | ---: | ---: | ---: |
| Native RawSocket JSON RPC, 1 KiB serial | 0.00628 | 0.00624 | -0.5% |
| Native RawSocket MessagePack RPC, 64 KiB | 9.342 | 9.476 | +1.4% |
| Native RawSocket CBOR RPC, 64 KiB | 9.451 | 9.438 | -0.1% |
| Native WebSocket MessagePack RPC, 64 KiB | 9.644 | 9.525 | -1.2% |
| Native WebSocket CBOR RPC, 64 KiB | 9.179 | 9.562 | +4.2% |
| Native RawSocket CBOR pub/sub, 64 KiB | 0.718 | 0.796 | +10.9% |
| Native WebSocket MessagePack pub/sub, 64 KiB | 1.931 | 2.089 | +8.2% |
| Dart RawSocket CBOR RPC, 64 KiB | 8.950 | 9.070 | +1.3% |
| Native RawSocket MessagePack RPC, 32 MiB | 35.719 | 36.536 | +2.3% |
| Native RawSocket CBOR RPC, 64 MiB | 35.345 | 36.186 | +2.4% |

This repeat does not reproduce the earlier large-frame throughput decrease, but
does not clear it: baseline throughput moved too, inference reached 102.7% at a
run boundary, and unrelated VM activity ranged from 130.9% to 254.9%. Large-frame
median p99 still rises from 22.776 to 24.625 ms and 28.929 to 30.899 ms. Median
observed 64 MiB server RSS remains higher, 169.6 versus 311.5 MiB.
The incremental comparison is mixed: 32 MiB MessagePack decreases 3.4%, 64 MiB
CBOR increases 2.6%, and remaining throughput changes range from -1.7% to +2.9%.
Its large-frame p99 rises from 22.004 to 24.680 ms and 30.877 to 31.954 ms.
Inference is near idle, but VM activity ranges from 130.1% to 342.2%. Neither
comparison proves a speedup or unchanged performance. No audit test, build, or
companion inference overlapped a measured pass; every pass is retained.

A separate [AOT GC diagnostic](2026-09-10-native-call-payload-gc.json) uses the
SDK's documented [standalone VM options](https://raw.githubusercontent.com/dart-lang/sdk/3.13.1/CHANGELOG.md)
and [GC file recorder](https://github.com/dart-lang/sdk/blob/3.13.1/runtime/vm/timeline.cc).
It runs baseline/Arc/payload/payload/Arc/baseline, each with eight warmup and 64
measured serial 64 MiB CBOR calls, without errors. All 18 per-process trace hashes,
launchers, aggregation source, and per-event statistics are retained. These
whole-process traces include startup, warmup, and teardown and are not throughput
measurements. Begin/end intervals are paired by process, thread, name, and
isolate group; unmatched pairs fail aggregation. Concurrent/nested intervals
must not be added together as stop-the-world time.

Both safe receiver variants record 147 server young-generation collections
(146 marked `external`) and 72 old-generation intervals marked `finalize` in
each run. The pre-ownership baseline records four young collections and no old
collection intervals. Payload-only receiver totals are 11.5-12.5 ms for young
and 10.0-13.4 ms for old intervals, versus Arc's 12.6-14.0 ms and 12.5-16.6 ms.
This confirms external-memory collection pressure remains; it does not establish
how much of the uninstrumented throughput or RSS difference GC causes. Removing
accounting or weakening owner lifetimes is not an acceptable optimization.

All 62 unchanged [large-frame/file gates](2026-09-10-native-call-payload-production-gates.json)
pass: 24 frame workloads / 864 samples / 24 GiB, eight heavy-file workloads /
190 transfers / 24 GiB, and 30 file-matrix workloads / 408 transfers / 25.5 GiB.
There are no errors or counter/metric findings. **Relative performance remains
open and the candidate stays local.** Final production-library/canonical-profile
evidence and SA-002/SA-003 confirmation are still required. Continue the wider
audit with bounded signed-handle allocation tests, cancellation/late-transfer
cases, and other external-buffer owners; these leads are not confirmed findings.

### SA-005: Native Message Handles Cross The Signed ABI Boundary

**Status:** confirmed; local fail-closed mitigation passes full verification.
Comparison and absolute-gate evidence are retained, but relative performance is
not cleared. Wider-handle migration is still required.

**Severity and prerequisites:** high-impact conditional lifetime/resource defect.
This is the native process's internal message-handle namespace, not a WAMP
request ID supplied by a peer. An admitted workload must accumulate enough
parsed messages and retained aliases to exhaust that process-global namespace.
The tests inject counter boundaries into isolated stores; they do not claim a
single malformed packet can set the counter or demonstrate a complete remote
cross-session disclosure chain.

`MessageStore` previously used unchecked `AtomicU32::fetch_add` for both creation
and cloning, while poll/wait/retain returned signed `c_int` and readers rejected
nonpositive handles. After `i32::MAX`, entries could be stored under IDs returned
as errors, preventing ordinary callers from releasing them. At unsigned wrap,
zero collided with the no-message sentinel and subsequent IDs replaced existing
map entries. A stale handle could therefore resolve to a different allocation.
The namespace was already process-lifetime: clearing messages did not reset it.

Four safe fail-first tests reproduce a returned `2147483648`, a returned zero,
live-entry replacement after three injected-boundary clones, and reuse of an
occupied same-shard ID. Assertions compare owned Arc identities and reference
counts, never read freed bytes, and never modify the process-global counter.

The shared insertion path now atomically reserves only `1..=i32::MAX`, rejects
zero/exhausted counters without advancing them, and accepts only vacant map
entries. The last positive ID remains valid exactly once. Rejected owners are
dropped; a clone releases its source shard guard before insertion. Parsing and
test enqueue paths propagate allocation failure without storing or queuing a
bad ID. Invalid retain remains `ERR_INVALID_ARGUMENT` (-4); exhaustion returns
the existing `ERR_HANDLE_UNAVAILABLE` (-14). C ABI layouts and Dart bindings do
not change. Existing owners and handles can still be read/released after
allocation exhaustion, and clearing cannot resurrect stale handles.

The expanded tests cover new-message rejection cleanup, final-ID insertion,
occupied-slot preservation, clear/reuse boundaries, unavailable-source admission,
and 16 concurrent creators/cloners competing for eight remaining IDs. A separate
FFI test verifies positive-boundary/error conversion. All 112 feature-enabled
FFI tests pass on confirmation. The first full run passed 111 tests but timed out
in an HTTP/3 handshake; that test passed in isolation and the complete fresh
suite passed. Its cause remains unproven, not fixed by this WAMP-only change.
Fresh `bin/verify` passes, including 105 default FFI, 112 test-hook FFI, 514 router,
and the existing package, live MCP, remote-auth, zero-copy, and Chrome/Dart2Wasm
checks. Do not treat the initial failed run as passing evidence. The measured
`ffi-test` release library SHA-256 is
`67479063a474a9867d79ac274999747e53912bcc1a37fa6279e9e603b436b036`.

The [native-only comparison and production gates](2026-09-10-native-message-handle-benchmarks.json)
retain frozen identities, source fingerprints, commands, runner sources, scenario,
raw hashes, and verification outcomes, including the initial failed FFI run.
Both variants use the same payload-only AOT service, client, and driver; only the
native library changes. Six ABBAAB passes complete 188,640 measured operations
and 11,160 warmups without errors. Each pass now uses 512 calls at 32 MiB and
256 at 64 MiB, rather than the earlier 16 and eight, providing longer measurement
windows and 384 GiB of measured large-frame request-plus-response payload.

| Native-only comparison | Baseline Gbit/s | Candidate Gbit/s | Median change |
| --- | ---: | ---: | ---: |
| Native RawSocket JSON RPC, 1 KiB serial | 0.00629 | 0.00627 | -0.5% |
| Native RawSocket MessagePack RPC, 64 KiB | 9.361 | 9.218 | -1.5% |
| Native RawSocket CBOR RPC, 64 KiB | 9.568 | 9.640 | +0.8% |
| Native WebSocket MessagePack RPC, 64 KiB | 9.409 | 9.469 | +0.6% |
| Native WebSocket CBOR RPC, 64 KiB | 9.011 | 9.431 | +4.7% |
| Native RawSocket CBOR pub/sub, 64 KiB | 0.789 | 0.776 | -1.7% |
| Native WebSocket MessagePack pub/sub, 64 KiB | 2.073 | 1.939 | -6.5% |
| Dart RawSocket CBOR RPC, 64 KiB | 9.096 | 9.138 | +0.5% |
| Native RawSocket MessagePack RPC, 32 MiB | 39.786 | 41.355 | +3.9% |
| Native RawSocket CBOR RPC, 64 MiB | 35.957 | 41.017 | +14.1% |

WebSocket pub/sub median p99 rises from 65.944 to 67.048 ms. Large-frame p99 is
18.600 versus 18.558 ms and 35.557 versus 34.700 ms; median observed 64 MiB server
RSS is 315.2 versus 314.3 MiB. Background inference rises from near idle to
2201.5% at a run boundary; VM activity ranges from 133.5% to 298.8%, with emulators
also active. The late baseline and candidate CBOR passes both fall to roughly
34 Gbit/s. Preserve every pass: neither the apparent large-frame improvement nor
the pub/sub decrease can be assigned to the guard from these measurements alone.
No audit build, test, or companion inference overlapped the benchmark passes.
**Relative performance remains open**, especially pub/sub confirmation; this
also does not clear earlier SA-002/SA-004 results.

All 62 unchanged absolute gates pass with the same library: 24 large-frame
workloads / 864 samples / 24 GiB, eight heavy-file workloads / 190 transfers /
24 GiB, and 30 file-matrix workloads / 408 transfers / 25.5 GiB. There are no
errors or counter/metric findings. Public-artifact references and JSON/hash
consistency checks pass after evidence generation. Nothing is published.

**Remaining work:** checked admission prevents wrapping, leaks from unreachable
handles, and replacement, but leaves a finite legacy lifetime limit. Recycling
released IDs is not a solution because queued work/finalizers can retain stale
identities. Add an explicitly wide, positive handle ABI and migrate every
consumer together: poll/wait, get/peek, retain/release, slice export, binary decode,
SHA-256, E2EE, forwarding, test queues, both Dart bindings, and the shared byte
export helper. Legacy wrappers must fail closed rather than truncate wide IDs;
partial capability sets must not mix wide producers with narrow consumers.
Test operations above the old signed boundary and keep old-library compatibility.
Review the other native handle stores' reset/wrap behavior independently. This
mitigation is not the completed security audit or release clearance.

### SA-005 Native Wide-Handle ABI

The native half of the migration is implemented locally. The additive `_wide`
family uses signed 64-bit routing message handles for polling/waiting, get/peek,
retain/release, byte exports, binary decode, SHA-256 updates, both E2EE message
consumers, forwarding (including progressive invocation v2), and test queues and
observers. `ct_message_handle_abi_version()` reports version 1. Connection,
keyring, crypto-session and hash handles, status codes, `CtMessageInfo`, and WAMP
wire IDs are unchanged. Existing C entry points keep their original signatures.

An independent store and counter avoid consuming the legacy allocation budget.
Wide readers accept legacy IDs; wide retain creates a distinct wide handle with
independent shared ownership. Neither counter resets on clear or restart. The
native read helper retains the allocation and releases the map shard before
running the reader/encoder. Exported slice owners still outlive routing handles.

Simply starting IDs above 32 bits is insufficient protection against an
accidentally narrow binding: its low word could name an unrelated legacy message.
Two fail-first tests reproduced that problem and the low-word carry boundary in
the initial local wide allocator. The final layout starts at `0x180000000` and
always sets bit 31, skipping the positive low-word range at carry. Every issued
wide handle therefore becomes negative if narrowed to signed 32 bits, and legacy
entry points reject it rather than accessing another message. `i64::MAX` remains
usable once; its successor is a nonissued exhaustion sentinel. Collisions,
invalid counters and exhaustion drop rejected owners without replacement or reuse.
This defensive layout does not replace consistent binding-family selection.

All 17 focused wide-handle tests pass. Coverage includes concurrent final-ID
allocation, invalid/carry/exhaustion boundaries, stale IDs across clear, explicit
legacy narrowing rejection, independent byte owners, full-width binary/hash
consumers, E2EE consumption on failure, and both E2EE ciphers. The unique AES-GCM
consuming path still reuses the receive allocation. Six live tests exercise
RawSocket and WebSocket with JSON, MessagePack and CBOR, including all native
forwarding variants, progressive flags, payloads and unchanged wire IDs.

Fresh final `bin/verify` passes: 142 core, 121 default FFI, 129 test-hook FFI,
29 native artifact and 74 HTTP-driver tests, 514 router tests, and the existing
package/live MCP/zero-copy/Chrome/Dart2Wasm gates. Initial new-test compile errors,
an incorrect expectation that peek exports the whole frame, and a default-feature
test import error were corrected; their failed runs remain separate evidence.
The pre-marker passing verification is not final-tree evidence. The final frozen
FFI-test library SHA-256 is
`9d221311e95d882985ec022c8b27c5d56ed3d460a452369557a0c8507af417ce`.

A dynamic C-ABI smoke test loads that exact library and checks all 18 production
wide symbols plus version 1 with explicit signed-64-bit argument/return types.
Handles `6442450944` and `6442450945` survive poll/retain without truncation;
legacy narrowing rejects them. An exported frame remains valid after both
handles are released and the store is cleared, and the weak allocation observer
reports destruction only after the independent export owner is freed.

The [native-wide compatibility evidence](2026-09-10-native-wide-message-handle-benchmarks.json)
preserves source/library hashes, all raw-result hashes, commands and scripts,
failed verification attempts, final verification, and the dynamic C-ABI probe.
Six ABBAAB passes compare this candidate against the checked-32-bit native
library at `9864836c`, using identical Dart executables. They complete 188,640
measured operations and 11,160 warmups with no errors, including 384 GiB of
large-frame request/response payload. Median application throughput is:

| Workload | Checked-32-bit GBit/s | Native-wide adapters GBit/s | Change |
| --- | ---: | ---: | ---: |
| RawSocket JSON RPC, 1 KiB | 0.006244 | 0.006242 | -0.04% |
| RawSocket MessagePack RPC, 64 KiB | 9.631 | 9.413 | -2.26% |
| RawSocket CBOR RPC, 64 KiB | 9.420 | 9.497 | +0.81% |
| WebSocket MessagePack RPC, 64 KiB | 9.356 | 9.342 | -0.16% |
| WebSocket CBOR RPC, 64 KiB | 9.472 | 9.358 | -1.21% |
| RawSocket CBOR pub/sub, 64 KiB | 0.787 | 0.793 | +0.66% |
| WebSocket MessagePack pub/sub, 64 KiB | 2.088 | 2.057 | -1.51% |
| Dart RawSocket CBOR RPC, 64 KiB | 8.978 | 8.897 | -0.91% |
| RawSocket MessagePack RPC, 32 MiB | 42.278 | 42.569 | +0.69% |
| RawSocket CBOR RPC, 64 MiB | 41.519 | 42.115 | +1.43% |

This is **not performance clearance**. The artifact retains every pass and
tail-latency observation, including Dart CBOR RPC median p99 increasing from
2.531 to 2.851 ms. Median sampled server RSS for 64 MiB CBOR RPC is 280.6 MiB
before and 318.5 MiB after; this is an observation, not an established leak or
attributed regression. Boundary CPU samples show unrelated inference reaching
1009.1%, VM activity 133.5-278.9%, and emulator activity 20.6-32.3%. No own
builds, tests or companion inference overlapped the benchmarks. The comparison
does not settle earlier SA-002/SA-004 decreases or memory questions.

The first absolute-budget run completes all 62 workloads over 73.5 GiB without
sample errors or counter findings, but **fails** one metric. The 24-workload
large-frame and eight-workload heavy-file gates pass. In the 30-workload file
matrix, buffered Dart WebSocket JSON at 64 MiB reports 2.067 GBit/s in the data
window but 1.952 GBit/s over its lifecycle, below the unchanged 2.0 GBit/s minimum.
The fail-fast checker exits 1. Its artifacts are preserved; the reconstructed
aggregate explicitly omits unavailable orchestrator timestamps/CPU samples.

A predetermined four-process ABBA confirmation repeats the entire unchanged
30-workload file scenario and policy, not only the failed case. All four gates
pass, with 1,632 samples and 102 GiB total payload without sample errors. For the
initially failing workload, lifecycle results are baseline 2.145, candidate
2.169, candidate 2.167, baseline 2.160 GBit/s. Inference boundary activity is
0.4-0.5% and VM activity remains 153.1-155.0%. The initial miss did not reproduce
in these two candidate passes; its cause is not established. Do not erase it,
relax the policy, or infer a general no-regression claim from this bounded run.

**At this native-only checkpoint:** both Dart bindings and the shared byte exporter still select
legacy producers. Migrate the entire family together, including optional crypto
lookups and finalizer/release paths; verify partial-library fallback/rejection,
old-library compatibility, high-handle client/router transfers and actual wide
application benchmarks. Legacy application compatibility measurements cannot
prove wide-path application speed or resolve earlier audit regressions. Native
HTTP body lifetime and other resource-store reset/wrap reviews remain pending.
No audit change is published.

### SA-005 Dart Wide-Handle Adoption

On 2026-09-11, both Dart bindings and the shared byte exporter adopt the complete
version-1 family together. Only routing-message handles become signed 64-bit;
connection/crypto/hash handles, status codes, wire IDs and message layouts do not
change. Capability negotiation runs before binding any message functions. An
unknown version or any missing required symbol rejects initialization rather
than mixing widths. An unadvertised older library keeps its legacy family.
Every legacy handle-consuming callback rejects signed-32-bit overflow and
underflow before FFI, including forwarding, crypto, hashing, release and export.
Optional legacy consuming-decrypt support and owned-copy fallback remain intact.

Six fail-first Dart regressions reproduced truncation in the not-yet-migrated
bindings. All 25 capability tests now pass, including every missing family
symbol. Compiled incomplete/unknown-version C fixtures prove rejection precedes
unrelated lookups. A controlled live legacy allocation demonstrates that an
unguarded `Int32` FFI call aliases `handle + 2^32`; every guarded consumer rejects
that value and negative underflow without consuming the legitimate message.
Actual high-ID tests cover client/router poll, wait, get/peek, retain/release,
byte owners, sole-binary decode, SHA-256, both E2EE ciphers and consuming decrypt.
The 36 focused live client/router tests pass, including forwarding across
transports and serializers. Existing lifetime/subview/isolate cleanup tests pass
on the wide ABI; older libraries pass 35 applicable owner-API cases and 32
copy-fallback cases. Skips explicitly identify unsupported wide/owner features.

The first complete `bin/verify` passes with 526 router tests, 121 default/129
test-hook FFI tests, 124 Dart benchmark tests, and the existing live MCP,
package-consumer, zero-copy and Chrome/Dart2Wasm gates. A subsequent runner
inspection found the explicit client file lists omitted the new capability
suite. A fail-first script regression catches both omissions; fast and full
verification now include it, and all 25 script tests pass. Updated-runner handoff
verification then fails two native HTTP/3 handshake cases with a 30-second Dart
timeout and native error -16. The identical native-library hash is confirmed;
all eight HTTP/3 cases pass in isolation, and the full 526-case router suite
passes with existing native debug logging. Final ordinary full `bin/verify`
then exits 0, including the updated 25-case capability gate, 526 router tests,
and all live/package/zero-copy/Chrome checks. No timeout, retry, skip, or
production code was changed to hide the failure; its cause remains unproven
and its log is retained independently.
Initial test-only analyzer errors, an observer-less legacy fixture, and JSON
fixtures for binary-only hash/decrypt fast paths were corrected. Failed logs are
retained separately, not represented as passing behavior evidence. Local model
reviews were advisory: two bounded reviews completed without a confirmed finding;
the full-diff timeout and router-review output limit are not complete review
evidence. Native/Dart argument widths and fallback contracts were checked directly.

The [Dart-wide benchmark evidence](2026-09-11-dart-wide-message-handle-benchmarks.json)
contains all six ABBAAB passes, source/executable/library hashes, raw-result
hashes, commands, scripts, verification outcomes, and unchanged gate policies.
Both variants load the identical frozen native library with SHA-256
`9d221311e95d882985ec022c8b27c5d56ed3d460a452369557a0c8507af417ce`.
Baseline uses the previously built SA-004 payload-only service and metadata worker;
tracked Dart sources are unchanged between `cbc0511e` and parent `592df650`.
Candidate service and worker are freshly built AOT bundles. This isolates Dart
wide-family adoption from the earlier native-library change. It completes
188,640 measured operations plus 11,160 warmups without errors, including 384 GiB
of measured large-frame request/response payload. Median application throughput:

| Workload | Legacy Dart GBit/s | Wide Dart GBit/s | Change |
| --- | ---: | ---: | ---: |
| RawSocket JSON RPC, 1 KiB | 0.007189 | 0.007202 | +0.17% |
| RawSocket MessagePack RPC, 64 KiB | 9.044 | 8.630 | -4.58% |
| RawSocket CBOR RPC, 64 KiB | 9.700 | 9.409 | -2.99% |
| WebSocket MessagePack RPC, 64 KiB | 7.786 | 9.642 | +23.84% |
| WebSocket CBOR RPC, 64 KiB | 8.004 | 8.066 | +0.77% |
| RawSocket CBOR pub/sub, 64 KiB | 0.762 | 0.701 | -7.96% |
| WebSocket MessagePack pub/sub, 64 KiB | 2.158 | 2.142 | -0.73% |
| Dart RawSocket CBOR RPC, 64 KiB | 9.616 | 8.499 | -11.61% |
| RawSocket MessagePack RPC, 32 MiB | 41.590 | 40.397 | -2.87% |
| RawSocket CBOR RPC, 64 MiB | 39.757 | 37.080 | -6.73% |

**Performance is not cleared.** RawSocket pub/sub ranges do not overlap in these
three observations per variant, and its median p99 rises from 51.482 to 56.034 ms.
Large-frame results also decrease. Other workloads are mixed, with substantial
within-variant spread. Median sampled server RSS for 64 MiB RPC decreases from
327.9 to 301.4 MiB; this is neither peak-memory proof nor clearance of the earlier
ownership memory findings. Inference is absent in the first five boundary pairs
but reaches 92.1% at the last; VM activity is 142.5-271.5% and emulator activity
21.7-120.6%. No own builds, tests or companion inference overlap measured runs.
Do not assign a cause or dismiss the decreases as harmless noise without profiling.

All 62 unchanged AOT large-frame/file workloads pass their absolute gates over
73.5 GiB of application payload. The canonical `bin/wamp-profile-validate` runner
also passes all nine scenarios / 102 workloads on the current-tree JIT paths,
covering cleartext/TLS, controls, pub/sub fan-out, both E2EE ciphers, progressive
invocations, timeouts and Meta APIs. These are absolute budgets, not relative
performance clearance. The wide Dart migration is locally implemented; profiling
the measured decreases, other native resource-store reset/wrap and HTTP-body
lifetimes, earlier audit performance questions, and all pending component rows
remain required work. Nothing is pushed or published.

Separate source-review lead: `start_http3_listener` awaits a connecting peer
inside its accept loop. Reproduce behavior with a bounded half-open client and
an independent legitimate client before deciding on an admission/handshake fix.
This lead is not established as the cause of the observed verification timeouts.
The subsequent bounded reproduction and mitigation are recorded in SA-006 below.

### SA-006: HTTP/3 Handshake Admission Blocks Independent Clients

**Impact: unauthenticated denial of service against an enabled, reachable HTTP/3
listener. Fixed and verified locally; performance clearance remains open.**

`start_http3_listener` awaited each QUIC handshake directly inside its accept
loop. One peer that sent a valid Initial but did not finish the handshake
prevented unrelated peers from being admitted. The endpoint's configured
`handshake_timeout_ms` was also not applied to this path. This affects HTTP/3
routes, including MCP when served there; it is not evidence of a TLS/auth bypass
or of blocking the separate TCP RawSocket/WebSocket/HTTP listeners. An attacker
needs network access to the optional QUIC listener, not application credentials.

Two loopback-only fail-first regressions reproduce the defect against unchanged
production sources from `5dc11c9a`. A UDP relay forwards real client Initial
packets and withholds server replies. Observing the first server reply proves
handshake admission before an independent client is tested, without sleep-based
ordering. The independent HTTP/3 GET misses its entire three-second deadline;
a configured 150 ms handshake deadline does not drain the stalled connection
within six seconds. An ordinary request control succeeds on the same listener.

The listener now owns a `JoinSet` of concurrent admission tasks, bounded by the
existing positive listen backlog. Each handshake has the configured timeout;
excess arrivals are refused before starting TLS. Completed tasks are reaped,
listener cancellation drops pending tasks, and a closed notification receiver
stops and closes the QUIC endpoint. The admission limit also covers tasks waiting
to notify the application. It is not an active-connection quota or immunity to
all floods. Request processing, TLS verification, 0-RTT policy, stream/window
sizes and the public ABI are unchanged. Unauthenticated handshake failures no
longer emit an unbounded stream of ordinary logs; opt-in `ffi-test` diagnostics
remain available.

This uses the existing [Quinn Incoming acceptance/refusal contract](https://docs.rs/quinn/0.11.9/quinn/struct.Incoming.html).
Quinn retains closed connections for three PTOs, consistent with
[QUIC closing-period requirements](https://www.rfc-editor.org/rfc/rfc9000.html#section-10.1).
The first new shutdown assertion incorrectly allowed only three seconds for
that interval; a six-second cleanup allowance makes the unchanged shutdown
control pass while both actual defect regressions still fail. The independent
client gate remains three seconds, and no production or existing CI timeout
was relaxed. A later new capacity assertion initially used the wrong peer error
enum; the corrected test verifies `ConnectionClosed(CONNECTION_REFUSED)`.
All failed logs remain separately identified in the evidence.

All six admission tests pass after the fix: ordinary client, incomplete peer
isolation, configured expiry, shutdown, backlog rejection/recovery, and closed
receiver cancellation. `bin/test-fast` and final `bin/verify` pass, including
148 core, 121 default/129 test-hook FFI, 526 router and 124 Dart benchmark tests,
live MCP/package consumers, 13 zero-copy cases, and Chrome/Dart2Wasm tests.
The earlier intermittent HTTP/3 verification failures are not proven to have
this cause. The local model review was advisory; source inspection did not
confirm its proposed cancellation defects. Production listener shutdown closes
the endpoint, serving paths remove closed connections, and synchronous
registration/spawn contains no intervening await before notification.

The [complete comparison and pressure-gate evidence](2026-09-11-http3-admission-benchmarks.json)
records source/library/executable/raw-result hashes, commands, scripts, logs,
CPU boundaries, latency and memory. Six ABBAAB AOT runs hold the Dart service,
worker and patched benchmark driver constant while swapping only the native
library. The baseline library is from identical production-native sources at
`592df650`; no transport source changed between that commit and `5dc11c9a`.
Candidate library SHA-256 is
`69b4f43f39b160f931788f5ab0915a7e34919c3f2222860d0e4b47ccb238d9f5`.
All 103,728 measured requests and 7,680 warmups succeed, with the expected exact
connection counts, no hidden reconnects, and no error/timeout counter changes.

| Workload | Baseline Requests/s | Candidate Requests/s | Change | Baseline / Candidate Request p99 ms |
| --- | ---: | ---: | ---: | ---: |
| HTTP/2 reused, serial | 396.4 | 398.7 | +0.58% | 3.069 / 3.054 |
| HTTP/2 reused, multiplexed | 2,651.1 | 2,673.6 | +0.85% | 9.547 / 9.357 |
| HTTP/3 reused, serial | 394.7 | 397.1 | +0.60% | 3.056 / 3.016 |
| HTTP/3 reused, multiplexed | 145.7 | 142.3 | -2.32% | 193.951 / 194.726 |
| HTTP/3 fresh, serial | 427.2 | 425.9 | -0.30% | 1.629 / 1.638 |
| HTTP/3 fresh, 16 concurrent clients | 1,227.1 | 1,556.8 | +26.87% | 2.947 / 8.887 |

**Performance is not cleared.** Parallel fresh-connection throughput improves,
but all three candidate request-p99 observations exceed the baseline range
(8.535-10.413 versus 2.927-3.155 ms). Median sampled server RSS after that workload
rises from 141.5 to 151.6 MiB. Reused multiplexed HTTP/3 throughput falls from
1.527 to 1.492 GBit/s, with overlapping per-variant ranges. No own tests, builds,
or model inference overlap timing; boundary inference is at most 0.1%, while
other shared-host activity remains. Do not erase the decreases or infer that
they are harmless noise.

Whole-workload elapsed throughput includes fresh TLS/QUIC setup, but existing
per-request latency starts after connection setup. Measure handshake-inclusive
operation latency separately and profile queueing/memory before deciding whether
the increased request tail is an end-to-end regression or a shift in where work
waits. Do not reintroduce listener-wide serialization to improve that isolated
metric. All five unchanged `h3_multiplex_scaling` pressure-gate workloads pass
(640 requests); those gates do not guarantee unchanged throughput or latency.
Earlier audit performance questions and every pending component row remain
required work. Nothing is pushed or published.

#### Setup-Inclusive Timing Follow-Up (2026-09-11)

The benchmark now records optional per-sample `http_fresh_connection_timing`
for plain non-reused H1/H2/H3 requests. Setup ends at protocol sender return;
total operation time includes setup and response-body drain, but not close or
per-worker payload preparation. Existing request latency and aggregate gates
retain their semantics. Reused, auth and old reports omit the new field.
Two fail-first cases detect its absence, with the reused-H3 control passing.
All three tests then pass, including concurrent workers, an injected 50 ms QUIC
handshake delay, positive finite timing bounds, and legacy JSON decoding.
Full `bin/verify` exits zero, including 77 benchmark-driver tests, 526 router
tests (one explicit skip), 124 Dart benchmark tests and Chrome coverage.

[Setup-inclusive comparison evidence](2026-09-11-http3-operation-timing-benchmarks.json)
preserves the earlier results and records six more ABBAAB passes. Both native
libraries and Dart AOT binaries are unchanged from the admission checkpoint;
one identical newly instrumented benchmark driver is used for both variants.
All 103,728 measured requests plus 7,680 warmups succeed, with exact connection
counts and no transport error/timeout counter increases.

These are medians of three per-run observations, not pooled percentiles:

| Fresh HTTP/3 Workload | Baseline / Candidate Requests/s | Request p99 ms | Setup p99 ms | Setup-Inclusive Operation p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Serial | 389.4 / 389.0 | 2.297 / 2.259 | 1.873 / 1.234 | 3.212 / 3.131 |
| 16 concurrent clients | 1,227.1 / 1,482.4 | 3.184 / 10.423 | 13.085 / 8.978 | 15.791 / 13.860 |

For fresh parallel clients, throughput improves 20.8% and setup-inclusive p99
falls 12.2%. The latter ranges do not overlap: baseline 15.702-15.978 ms versus
candidate 13.847-14.094 ms. Thus the request-only tail increase is not an
end-to-end regression in this measured workload: time shifts from setup to the
post-setup interval while the complete operation gets faster. This does not
identify the specific post-setup queue or establish latency under every load.
Never sum phase percentiles to reconstruct an operation percentile.

**Overall performance remains uncleared.** Median sampled server RSS after
fresh parallel traffic still rises from 140.0 to 150.5 MiB. That is not by itself
proof of a leak or its cause; profile live/closing connections, retained tasks,
allocation and post-drain memory next. Reused H3 multiplex throughput is 1.538
versus 1.532 GBit/s (-0.39%, overlapping ranges), without erasing the earlier
-2.32% result. Other throughput deltas are H2 serial +0.46%, H2 multiplex +1.35%,
reused H3 serial +0.05%, and fresh H3 serial -0.12%. No own test, build or model
inference overlaps timing; unrelated shared-host activity remains recorded.
Earlier audit performance questions and pending component reviews still apply.
No transport tuning, production security behavior, versions, remotes or
publications changed in this follow-up.

#### Native Ownership And Post-Idle Memory (2026-09-11)

The new `http3_admission_connection_churn_releases_native_owners` regression
uses the production listener with four bursts of eight concurrent TLS/QUIC
clients. Alternating bursts either complete and drain one GET or send no request.
The test captures weak connection/stream-channel owners before releasing the
clients, then checks endpoint and registry cleanup, destruction of those owners,
return of the registry Arc count to its initial listener baseline, and exactly
one graceful terminal event per accepted ID. The listener remains open throughout.
All 32 clients pass without a production change. This is ownership coverage,
not a reproduced new leak or proof about every Dart/FFI handle lifetime.

The [churn comparison](2026-09-11-http3-connection-churn-benchmarks.json) retains
six ABBAAB passes using the same frozen binaries as the setup-inclusive series.
The diagnostic scenario runs four 4,096-connection bursts at concurrency 16 per
process, separated by eight-second idle intervals and a final fifteen-second
interval. A total of 98,304 measured connections, 3,072 warmup connections and
30 small HTTP/2 probes pass exact byte/connection checks without errors or
transport error/timeout counter increases. Idle intervals are outside the
throughput window; the following values use the probes' pre-request RSS samples.

| Post-Idle Point | Baseline Median RSS, MiB | Candidate Median RSS, MiB |
| --- | ---: | ---: |
| After warmup | 56.234 | 55.344 |
| After burst 1 | 64.609 | 77.359 |
| After burst 2 | 65.844 | 79.781 |
| After burst 3 | 66.375 | 80.844 |
| After burst 4 | 68.938 | 83.281 |

Final RSS ranges do not overlap: 68.109-69.266 MiB baseline versus
81.812-84.422 MiB candidate. Both variants still grow across later bursts;
neither leak freedom nor a stable plateau is established. Do not replace the
earlier mixed-workload RSS observations with these different workload histories.

`vmmap -summary` snapshots taken only during the final idle interval show median
default-malloc-zone resident memory of 28.6 versus 40.5 MiB, but allocated bytes
of approximately 1.733 versus 1.940 MiB. Reported dirty/swap fragmentation is
23.6 versus 29.0 MiB; physical footprint is 51.3 versus 59.4 MiB. These rounded
macOS figures differ from process RSS and do not cover every allocation owner.
They support allocator retention/fragmentation as a substantial contributor,
not attribution of the whole difference or dismissal of possible leaks. The
router's `active_connections` gauge counts worker-owned connections and is not
used as proof of zero native QUIC connections.

The initial zero-response probe configuration was rejected by strict byte
validation: the existing benchmark handler returns `bench` for an empty echo
request. That failed attempt is retained separately; only probe responses were
changed to explicit 1 KiB synthetic bodies. A busy-inference preflight also
refused to start; no load threshold or byte check was weakened. No own tests,
builds or inference overlap the six valid runs; unrelated host activity remains
recorded. The new native regression and initial full `bin/verify` pass.
Final `bin/verify` after the probe correction also exits zero: 149 core,
121/129 FFI, 29 benchmark-artifact and 77 driver tests, plus 526 router tests
(one explicit skip), 124 Dart benchmark tests, consumer/MCP smoke, zero-copy,
and the Chrome/Dart2Wasm SCRAM and WebSocket checks.
Performance remains uncleared. Next separate allocator behavior from remaining
Dart/FFI resource ownership under comparable workload histories, while continuing
the other component reviews. No production transport code, versions or releases
changed in this checkpoint.

### SA-007: Restarted Native Resources Alias Stale Owners

**Impact: E2EE key confusion, file/metadata disclosure, and replacement-resource
destruction; moderate with the in-process lifecycle prerequisites below. Fixed
locally; full verification and absolute budgets pass, performance provisional.**

`ct_shutdown()` clears resource maps through `clear_channels()`. File, E2EE
keyring/session, and HTTP connection-event stores also reset their allocation
counters to one. Dart providers and other owners can outlive that explicit
runtime shutdown. After another caller starts the runtime and allocates a new
resource, the old integer handle can identify the replacement instead of being
rejected. The Dart provider's released flag does not identify runtime generations.

This requires a surviving owner or delayed in-process callback across explicit
native shutdown/restart, followed by replacement allocation. It is not evidence
that a remote peer can directly choose native handles or restart another process.
Applications that dispose every owner before restarting avoid this particular
trigger; the native boundary must nevertheless reject stale owners safely.

Six Dart fail-first regressions exercise both AES-256-GCM and
XSalsa20-Poly1305 through the native providers. For each cipher, the old provider
can decrypt ciphertext made with a different replacement key, encrypt using that
replacement key, and destroy the replacement on release. Positive controls
verify the replacement's round trip and its rejection of the original key's
ciphertext. The encryption reproduction explicitly decrypts the stale provider's
output using the replacement, distinguishing key confusion from retaining the
old key. The corrected implementation passes all six cases plus the seven
existing native provider tests.

Six additional native fail-first cases cover file lookup/release, keyring
mutation/release, and connection-event lookup/release. Fresh file bytes and
replacement event metadata remain usable after rejected stale operations. The
first native test attempt failed to compile because it imported a private
module; moving the tests into the runtime module fixes that fixture issue.
The subsequent six assertion failures are the actual before-fix evidence.

The production change removes the four counter resets while retaining resource
clearing. It does not change encryption, serialization, packet processing,
allocation on the traffic path, wire formats, or public ABI. Stale file/keyring
lookups and operations now report unavailable handles; stale releases cannot
delete replacements. Existing release contracts remain unchanged: Dart provider
release returns void, and connection-event release is idempotently successful
for unavailable positive handles. Replacement survival, not a newly invented
release error, is the regression invariant.

`bin/test-fast` passes before the production change. Full `bin/verify` passes
after it, including 149 core, 127 default/135 test-hook FFI, 29 native artifact,
77 driver, and the existing router, consumer/MCP, zero-copy and browser checks.
Both client verification scripts now explicitly run the six-case restart suite;
a script regression checks that inclusion. GLM review and bounded test planning
completed; the initial planning request exhausted its output limit. Suggestions
were checked against API contracts rather than accepted as findings.

**Remaining boundary:** process-lifetime counter exhaustion and unsigned wrap
are not fixed by removing shutdown resets. These stores still need bounded
exhaustion/collision regressions and a compatible allocation strategy. Do not
claim that resource IDs can never recycle under any condition. Broader HTTP
body/stream ownership and other component rows also remain under review.

Six native-only ABBAAB runs with identical AOT driver/router/client inputs
complete 63,648 measured operations plus 5,160 warmups without errors or
byte/count discrepancies. The 23-workload matrix covers all 16 canonical E2EE
variations and seven native 64 MiB file paths, including TLS and both ciphers.
Measured file traffic alone totals 42 GiB. Native E2EE uses 256 iterations per
client, Dart XSalsa 128 and Dart AES 16, with four clients; file cases use eight
iterations and two clients. Those budgets were fixed before either variant ran.
Warmups precede measured workloads but use separate sessions.

| Representative workload | Baseline GBit/s | Patched GBit/s | Median change |
| --- | ---: | ---: | ---: |
| RawSocket native AES RPC, 64 KiB | 0.982 | 0.996 | +1.4% |
| RawSocket native XSalsa RPC, 64 KiB | 0.934 | 0.928 | -0.7% |
| WebSocket Dart AES pub/sub, 64 KiB | 0.00540 | 0.00531 | -1.7% |
| RawSocket MessagePack file, 64 MiB | 14.463 | 15.953 | +10.3% |
| WebSocket TLS AES file, 64 MiB | 12.833 | 14.620 | +13.9% |
| WebSocket TLS XSalsa file, 64 MiB | 3.751 | 3.866 | +3.1% |

GBit/s counts application request plus response payload, except files count
one-way file bytes; it is not wire bandwidth. The two throughput decreases have
overlapping ranges. RawSocket Dart AES pub/sub p99 increases from 3,084.750 to
3,686.510 ms (+19.5%), also with overlapping ranges and only 64 measured samples
per run. Retain that unfavorable observation rather than claiming no tail cost.
All seven file throughput medians improve, but source inspection does not
establish that removing resets caused the improvement. Server RSS sampled after
the last workload is 399.84 versus 396.48 MiB median; these are shared-process
observations, not isolated peak-memory measurements or leak-freedom evidence.
Per-workload client/server memory, lifecycle rates, full latency summaries,
every run and hashes are retained in the machine-readable evidence.

Own tests, builds and inference do not overlap timed runs. Unrelated inference
causes bounded waits between processes and is still visible at two baseline
completion snapshots; VM and other load also vary. These are not dedicated-host
measurements or proof of equal performance. All 70 unchanged absolute workload
gates pass over 2,040 samples: 16 E2EE, 24 large-frame, and 30 file-transfer
workloads, including 24 GiB combined frame payload and 25.5 GiB file payload.
Absolute budgets do not resolve relative latency or earlier audit regressions.

Evidence: [restart comparisons and production gates](2026-09-11-resource-restart-benchmarks.json)
(SHA-256 `3a5a6a2ea7807028367f0ba9aa7b3e50b52cf893f8750d436a5a164fd95d3b6c`).
Keep this change local and performance provisional. Continue resource-counter
boundary work and every pending component row; the complete audit and earlier
performance questions remain open.

### SA-008: Native Resource Allocation Crosses Signed Limits And Replaces Owners

**Impact: resource unavailability, stale-owner aliasing and live-owner
replacement; moderate with the allocation-volume prerequisites below. Checked
allocation is locally implemented; finite legacy capacity remains unresolved.**

Twelve FFI resource stores allocate an unsigned 32-bit ID with unchecked
`fetch_add`, insert into a `DashMap`, and return the ID through signed C `int`.
Above `i32::MAX`, valid allocations appear as negative errors; zero is the
no-item sentinel. At unsigned wrap the map insertion can replace a live owner,
or a stale ID can identify a new resource. Removing runtime-restart resets in
SA-007 did not prevent this independent process-lifetime wrap.

Affected stores hold files, E2EE keyrings and sessions, HTTP metadata/response
handles, request bodies, connection events, response-stream writers, HTTP/2
handshakes, HTTP/3 connection references/handshakes/streams, and WebSocket
handshakes. Each has its own allocation budget, unrelated to the number of
simultaneously live objects. Previously hardened routing-message handles are
unchanged by this checkpoint. Core listener/connection IDs are separate and
still require their own boundary review.

The trigger requires near 2^31/2^32 allocations in a store, or an already-invalid
counter. Ordinary HTTP churn reaches some of these allocation paths, but this
review does not demonstrate a remote exhaustion attack, its rate, or remote
ability to select native handles. Bounded tests seed private counters and maps;
they do not create billions of connections or mutate global production stores.

**Reproduction:** first extract the repeated original `fetch_add` plus `insert`
algorithm into a common helper without adding bounds checks. Seven allocator
assertions fail while positive controls pass. Extracting the old response
dispatch-before-store ordering adds an eighth failure: successful HTTP headers
are sent even when no usable writer handle can be returned. The strengthened
before run has five passes and eight assertion failures. This is a
behavior-preserving testability refactor before the fix, not a claim that the
new tests ran against an untouched old checkout. The before diff and complete
unchecked helper are retained with the evidence.

**Fix:** checked monotonic allocation accepts only `1..=i32::MAX`. The last
positive ID is usable once; invalid/exhausted counters never wrap or rewind.
An occupied-entry check preserves the original owner instead of replacing it,
and rejection drops the incoming resource. All twelve store functions use
their original counter/map and return a checked result through thirteen FFI
creation paths. Failure uses existing `ERR_HANDLE_UNAVAILABLE` (`-14`), without
new exported signatures. Sequentially consistent atomic ordering is retained.
Response streaming allocates its writer before dispatching success headers,
and removes that writer if dispatch fails. No cipher, serialization, payload
copying, wire format, or package version is changed.

All 13 focused regressions pass: positive IDs, zero, signed exhaustion,
unsigned wrap, collision survival, rejected-owner destruction, concurrent
final-slot allocation, clearing without reuse, FFI error mapping, and response
success/failure cleanup. The concurrent test starts eight callers at the last
valid slot and requires exactly one success. Existing file and HTTP-event
fixtures now unwrap their successful setup results.

Local summary, test planning and review completed; advisory claims were checked
against source. The suspected partial-response leak is not supported:
`HttpResponseHandle.respond` sends through a oneshot; a failed send drops the
undispatched reader. Releasing the stored writer closes its channel. The
suggestions to add an FFI panic or weaken atomic ordering were not adopted.

`bin/test-fast` passes before the substantive guard change. Full `bin/verify`
exits zero, including 149 core, 140 default FFI, 148 feature-enabled FFI,
29 artifact, 77 benchmark-driver, 526 router (one explicit skip), and existing
live MCP, consumer/package, zero-copy and Chrome/Dart2Wasm checks. This was not
a clean first attempt: the feature-enabled native suite initially had 147
passes and an HTTP/3 network handshake timeout; its existing retry passed all
148. Root cause is not established. A missing `--all` on the initial virtual
workspace formatting command was corrected separately, not a compile failure.

**Remaining availability work:** exhaustion is now fail-closed, not removed.
Clearing maps and restarting the runtime must not recycle IDs held by delayed
owners. A compatible wider resource-handle strategy, its Dart consumers,
legacy-adapter behavior, ownership review, and workload evidence are still
required. Do not release this checkpoint as a complete availability solution
or infer completion of the component audit from these local tests.

**Benchmark-driver readiness defect found during validation:** two old-library
baseline processes completed, but the strict comparison rejected unexpected
HTTP/1 reconnects. The first sustained workload opened five connections for four
workers; the second run's serial/sustained cases opened four/six instead of
one/four. Both attempts and their failing validation exits are retained.
The Hyper 0.14 client permits a temporarily non-ready sender to reject an
immediate `send_request`; the driver's retry hid that from successful request
samples while its connection count exposed the discrepancy.
The original retry errors were not logged: the reproduction below establishes
the readiness defect, not the cause of every observed reconnect.

Three deterministic fail-first tests occupy Hyper's initial queue slot while
leaving its connection driver unpolled. Plain, protected and JSON request
helpers all return `connection was not ready` instead of waiting. After adding
`poll_ready` waits, all three remain pending until the driver runs, then both
requests succeed on exactly one connection. All 80 driver tests pass. Plain
and protected request timing includes the wait; JSON login/refresh callers
already time the enclosing operation. Connection-closure errors still propagate
and the existing workload deadlines remain. This corrects the benchmark client,
not a demonstrated product HTTP-stack defect. Both native-library variants
must use the same corrected driver for the fresh comparison; neither reconnect
assertions nor performance thresholds are relaxed.
Fresh full `bin/verify` after this driver correction passes on its first
attempt, including all 80 driver tests and the existing router, live/package
and browser gates. The earlier HTTP/3 timeout remains recorded separately.

**Separate HTTP/1 reliability lead:** a third old-library matrix attempt still
opens five sustained-stream connections for four workers with the readiness
fix in place. A bounded diagnostic driver temporarily logs the first retry
error, without changing native or Dart code: worker 1, iteration 0 fails while
reading a TLS response body with unexpected EOF / missing `close_notify`, then
the retry succeeds. That isolated process completes 4,096 logical requests but
uses five connections. The diagnostic logging is removed from the product diff;
the retained ordinary driver source exactly matches the fully verified source.
Root cause is not established, and readiness is not the sole reconnect issue.
Do not interpret recovered request samples as error-free transport operation.

For full-matrix collection, unexpected connection counts remain strict findings.
The collector now preserves subsequent runs and all unaffected workloads before
returning a nonzero exit if any finding occurs, rather than aborting after the
first process. No expected connection count or performance threshold changes.
Lifecycle goodput includes recovery time; retry-affected request-only latency
omits failed-attempt time and cannot establish clean-request tail performance.
The three earlier rejected matrices and isolated diagnostic remain separate.

**Six-pass native comparison:** identical frozen AOT service/client inputs and
the same readiness-corrected driver complete 136,512 measured logical operations
plus 8,904 warmups in ABBAAB order. The matrix covers 16 E2EE variants, seven
64 MiB file paths (42 GiB measured file payload), and serial, sustained and
fresh-connection HTTP/1/2/3. Request/response byte-count and sample checks pass;
this does not imply independently verified HTTP content hashes. Cryptographic
algorithms, payloads and sample budgets are unchanged across the two libraries.

The strict comparison **exits one**: eight HTTP/1 streaming findings cover five
measured workloads and three warmups, with eleven extra opened connections.
Both variants are affected; one baseline process is clean. All other workload
connection checks pass. Final logical-request error fields and four transport
error/timeout counters remain zero despite recovered HTTP/1 failures. Do not use
those counters alone as a complete transport-error oracle.

| Representative workload | Baseline GBit/s | Patched GBit/s | Median change |
| --- | ---: | ---: | ---: |
| RawSocket native AES pub/sub, 64 KiB | 0.634 | 0.610 | -3.9% |
| RawSocket native XSalsa RPC, 64 KiB | 0.967 | 0.916 | -5.3% |
| RawSocket TLS CBOR file, 64 MiB | 14.673 | 13.435 | -8.4% |
| HTTP/1 fresh connections, 1 KiB each way | 0.03270 | 0.03045 | -6.9% |
| HTTP/2 sustained, 256 KiB up / 1 MiB down | 25.265 | 24.129 | -4.5% |
| HTTP/3 fresh connections, 1 KiB each way | 0.02176 | 0.02228 | +2.4% |

GBit/s counts application goodput, not wire traffic; file payload is counted
one way. WAMP uses data-window elapsed time and HTTP uses whole-workload elapsed
time. Every throughput range overlaps, but that does not establish no overhead.
All seven file medians decrease (0.15% to 8.43%). The TLS file case's sample p99
rises from 74.948 to 82.626 ms; native AES RawSocket pub/sub p99 rises from 17.979
to 19.956 ms. File and Dart AES sample budgets are small and limit tail precision.
Fresh HTTP/1 setup-inclusive p99 is 5.482 versus 5.495 ms; HTTP/3 is 8.407 versus
8.460 ms. Keep these separate from request-only timing and recovered-retry rows.

Server RSS sampled after the last workload has medians 196.48 versus 213.19 MiB,
with ranges 176.23-285.25 and 204.75-215.84 MiB. This is a shared-process
post-workload observation, not an isolated allocation peak or leak proof.
Client memory for the native HTTP driver is not sampled, not zero. Other
per-workload memory and latency observations remain in the evidence.
No own tests/builds/inference overlap timings. Preflight waits and process CPU
snapshots are retained; unrelated inference exceeds 2,000% CPU at the end of
one candidate process, and VM/emulator load varies. **Performance is not cleared**:
investigate the decreases under controlled load, fix/reproduce the HTTP/1 EOF
independently, retain all earlier audit comparisons, and do not publish this
checkpoint as release-ready.

**Unchanged absolute budgets:** the first production run completes 75 workloads
and 2,680 samples. E2EE (16), large RawSocket frames (24), and HTTP/3 multiplexing
(five) pass; the 30-workload file matrix has one failure. Buffered Dart/JSON
WebSocket transfer of a 64 MiB file achieves lifecycle goodput of 1.952 GBit/s
against the existing 2.000 GBit/s minimum. The strict gate exits one even though
the finding is labelled warning. Other 74 workloads pass; this is not an
all-green budget run.

Repeating the entire file matrix with the candidate gives the same sole failure
at 1.900 GBit/s. The identical matrix against the previous SA-007 native library
also fails that budget, at 1.921 GBit/s. Both additional processes complete 408
samples and pass the other 29 file workloads. Each uses the same frozen driver,
service, client, scenario and unchanged policy. The baseline subprocess/gate
exits (zero/one) are persisted; its outer tool-session exit was not retained.
All runs and CPU snapshots remain in the evidence. This failure is not unique
to the new guard, but these shared-host observations do not establish equal
performance, justify a lower budget, or clear the separate relative decreases.
Profile the buffered JSON file path and retest under controlled load before
making a release-speed claim.

Evidence: [resource-boundary comparisons, failures and production gates](2026-09-11-resource-boundary-benchmarks.json)
(SHA-256 `9d01cb5b7a5a041a5c3a210d3bd26b8459d94e803a99d50a7b048c8fbce5f0af`).
This local checkpoint records passing correctness verification alongside failed
strict performance/reliability checks. The whole security audit remains active;
no package version, release or remote branch is updated by this checkpoint.

### SA-009: HTTP/1 Responses Can Finish Before TLS Ciphertext Is Flushed

**Impact: incomplete responses and connection stalls under output backpressure;
local correctness and full verification pass; speed comparison incomplete.**

Before the fix, both `protocol::write_http_response_shared` and
`write_http1_chunked_response` returned after `write_all` without flushing. The
HTTP/1 connection loop then waits for the next request. Tokio-Rustls can accept
plaintext while retaining ciphertext when the underlying socket cannot accept
more bytes; subsequent reads do not flush it. A client waiting for the rest of
that response therefore cannot send its next request, and an eventual connection
close can truncate the response. This is a legitimate-traffic availability
defect, not a demonstrated authentication bypass or remote code execution.
It is a concrete cause candidate for the earlier HTTP/1 retry observations;
those historical retries did not record the server's close reason.

The behavior matches the pinned library's
[documented flush contract](https://docs.rs/tokio-rustls/0.26.4/tokio_rustls/#why-do-i-need-to-call-poll_flush),
verified against its local `poll_write`, `poll_flush` and `poll_fill_buf` source.
This fix adds a completion flush without introducing per-chunk flushing.
Flushing does not shut down a reusable connection or weaken TLS validation.

**Fail-first reproduction:** a generated, trusted TLS 1.3 certificate and a
64-byte in-memory duplex channel force backpressure without network timing or
global native state. Four tests cover buffered 8 KiB and empty responses, plus
chunked 1 MiB and empty responses. Each old helper returns while Rustls still
reports pending ciphertext; the assertion closes the fixture and its client
observes truncated TLS input. This artificial assertion-induced close is not a
claim that the fixture reproduced the production idle timer. Two independent
flush-error tests also fail because the old helpers incorrectly return success.
A plain-byte positive control passes. The confirmed before result is six
assertion failures and one pass, not a compilation or setup failure.

The initial TLS fixture instead timed out during its handshake: post-handshake
session tickets could fill its tiny channel before application reads started.
The corrected fixture disables those tickets only in its test server; production
TLS settings and tickets remain unchanged. All initial logs are retained.
For testability, only the private chunked writer's parameter was generalized
from `IoWriteHalf` to monomorphized `AsyncWrite + Unpin` before reproducing the
failure; its original no-flush behavior was retained for the before tests.

**Fix:** flush buffered HTTP/1 responses after their final bytes and streaming
responses after the terminal chunk. Propagate flush errors; close the streaming
reader on failure, matching existing write-error cleanup. No per-chunk flush,
new cipher operation, ABI, serializer, framing or package-version change is
introduced. All seven focused regressions pass, including exact wire bytes and
a second response on the same TLS stream after the first is fully readable.
`bin/test-fast` passes before edits. The first full `bin/verify` exits one:
156 core, 140/148 FFI and 80 driver tests pass, but protected native HTTP/3 MCP
times out after 30 seconds among 525 passing router tests and one explicit skip.
A focused rerun with the correct `ffi-test` library passes without changing
code or timeouts. The first isolated command incorrectly used the production
library and skipped the test; its zero exit is not counted as a test pass.
Cause of the full-suite timeout is unestablished, including any relation to
previous intermittent HTTP/3 failures. Fresh full `bin/verify` passes with
156 core, 140 default FFI, 148 test-hook FFI, 29 artifact and 80 HTTP-driver
tests, 526 router passes and one explicit skip, 11 remote-auth and 13 zero-copy
cases, the live MCP/package gates, and six SCRAM plus two WebSocket
Chrome/Dart2Wasm tests. No test timeout or retry tolerance was relaxed.

The first native-only comparison process exits one during baseline HTTP/1
streaming warmup: the peer truncates the TLS body even after the existing driver
reconnect. Only its warmup and measured serial workloads have complete JSONL
rows (16 and 2,000 samples). That failed process is retained exactly once;
partial attempts in its failed workload are unknown, not zero errors. The
remaining five planned ABBAAB processes were then collected without rerunning
that failed entry or changing driver retries, timeouts, sample budgets or
scenario order. The second baseline also fails, during measured HTTP/1
streaming after its warmup completed. The third baseline completes all workloads
but opens five rather than four connections in both streaming warmup and
measurement. Both collectors exit one, retaining four strict findings: two
failed processes and two unexpected connection counts. Unknown partial failed
attempts are not included in the completed-sample totals.

All three patched processes finish all nine workloads and their warmups with
expected connection counts, no reported request errors and no selected server
error-counter increments. They contain 36,432 measured requests and 1,872
warmups. Across both variants, complete JSONL rows contain 52,576 measured
requests and 2,592 warmups, short of the planned 72,864 and 3,744 because of the
baseline failures. The separate patched HTTP authentication smoke passes all
27 ticket/WAMP-CRA/SCRAM login, refresh and protected-route workloads with 126
samples and the exact expected connection counts across HTTP/1, HTTP/2 and
HTTP/3. This is stronger local reliability evidence, not proof every historical
EOF had this cause or that no other HTTP/1 failure can occur.

**Observed application throughput (GBit/s):** serial workloads use 2,000 requests
with one client; sustained streaming uses 256 requests per each of four clients,
256 KiB uploads and 1 MiB responses; fresh-connection workloads use 128 requests
per each of eight clients with 1 KiB each way. Values use total application
request/response bytes divided by lifecycle elapsed, not wire bandwidth.

| Workload | Complete baseline runs | Baseline median GBit/s | Patched median GBit/s (three runs) | Patched range GBit/s |
| --- | --- | --- | --- | --- |
| HTTP/1 serial | 3 | 0.006471 | 0.006476 | 0.006439-0.006502 |
| HTTP/1 streaming | 1, with reconnect | 1.898 | 8.549 | 8.153-9.288 |
| HTTP/1 fresh | 1 | 0.03948 | 0.03875 | 0.03804-0.03966 |
| HTTP/2 serial | 1 | 0.005801 | 0.005718 | 0.005661-0.005763 |
| HTTP/2 streaming | 1 | 25.999 | 25.384 | 24.798-26.644 |
| HTTP/2 fresh | 1 | 0.04358 | 0.04184 | 0.04092-0.04237 |
| HTTP/3 serial | 1 | 0.005704 | 0.005664 | 0.005641-0.005850 |
| HTTP/3 streaming | 1 | 1.512 | 1.486 | 1.453-1.548 |
| HTTP/3 fresh | 1 | 0.02126 | 0.02129 | 0.02113-0.02190 |

Only HTTP/1 serial has three complete observations per variant. Its median
throughput changes +0.079%, median request p99 rises from 3.060 to 3.088 ms,
and median sampled server RSS is 39.16 versus 39.11 MiB. These are small
observed differences, not proof of identical timing. All other rows are
explicitly unbalanced; no three-versus-three performance delta is emitted.
The surviving baseline streaming row includes recovery time, while its
request-only latencies exclude failed attempts; do not call the apparent
throughput increase a clean-request speedup. Lower candidate observations such
as HTTP/2 fresh connections remain visible and need balanced confirmation.
The artifact retains p50/p95/p99, setup-inclusive fresh p99, RSS/high-water RSS,
preflight waits, CPU snapshots, commands, source and binary hashes for every
process. No own inference, builds or tests overlapped timed runs; unrelated VM
and emulator activity remained. Workload-end RSS is shared-process state, not
isolated peak allocation; client memory is unavailable, not zero.

Evidence: [HTTP/1 completion regressions, failed and successful runs](2026-09-11-http1-response-flush-benchmarks.json)
(SHA-256 `f5ad1394f7cd78450095f0910d30b55c6f5b22ac0a5fd65d2c42f286f3edd8ee`).
No WAMP/file/frame budget was changed or rerun by this HTTP/1-only fix. The
earlier buffered JSON file budget failure, relative performance findings and
finite-handle availability remain open. Review paused mid-response producers
and HTTP/1 transfer-coding framing separately: these completion tests do not
prove timely intermediate SSE delivery or safe handling of ambiguous requests.
Keep this checkpoint local; the full component audit is not release-cleared.

### Public Dart Dependency Advisory Coverage

On 2026-09-10, `dart pub deps --json` was collected for the root workspace and
the standalone application's client, server, and shared packages. The root
graph includes all seven public packages. The union contains 163 distinct
hosted package/version pairs, queried against the
[OSV Pub ecosystem](https://osv.dev/list?ecosystem=Pub) through its
[batch API](https://google.github.io/osv.dev/post-v1-querybatch/).
All 163 responses arrived without advisories or pagination tokens. Only public
package names and versions were sent, not source files, local paths, or secrets.

This means no *listed matching advisory* was found on that date. OSV's Pub
coverage is limited; SDKs, local/path dependencies, native platform packages,
bundled WASM/JavaScript, and undisclosed vulnerabilities are not cleared by this
result. Source inspection, key lifecycle review, and malformed-input tests
remain required.

## Verification Record

- Baseline `bin/test-fast`: passed before production-code edits.
- Auth service: 25 tests passed after the fix.
- Remote auth RPC integration: 8 tests passed after the fix.
- `dart analyze` on the auth package and RPC regression file: no issues.
- Full `bin/verify`: passed, including 482 router tests, eight isolated remote
  auth tests, 13 zero-copy tests, 124 benchmark tests, package/CLI/live MCP
  consumer smokes, and Chrome/Dart2Wasm tests. The two final null-aware test
  style fixes were reanalyzed; auth tests reran and the full verification run
  subsequently exercised the updated RPC test file.
- SA-002 final `bin/verify` passes after the test-isolation correction, including
  142 Rust core tests, 90 default FFI tests, all 97 feature-enabled FFI tests,
  29 native artifact tests, 74 HTTP-driver tests, 24 verification-script tests,
  and the full Dart, live MCP/router, zero-copy, and Chrome/Dart2Wasm checks.
  Rust formatting checks and public-artifact-reference checks pass as well.
- These audit changes are local. Hosted verification has not been requested
  for these changes and no package version or release tag has changed.
- SA-003 authentication-only full `bin/verify` passes, including all 41 auth
  tests, 482 router tests, 11 isolated remote-auth tests, and the existing
  native, zero-copy, public CLI/MCP, benchmark, and browser gates. Router
  dispatch remains unchanged pending the separate ownership review.
- Local companion suggestions were checked against source and executable tests;
  incorrect suggestions (including missing the fake-state and adapter ABORT
  mutations) were not used as audit conclusions.

Keep the audit active until every component row and performance gate is covered.
These findings are an initial slice, not an exhaustive vulnerability list.

## SA-001 Performance Evidence

The [machine-readable comparison](2026-09-10-auth-admission-benchmarks.json)
preserves each run, medians/ranges, native-library and Dart snapshot hashes,
toolchain, workload hash, and run order. Hardware: Apple M3 Ultra, 32 logical
CPUs, 512 GiB RAM, macOS arm64, Dart 3.13.1. This is a shared developer host;
unrelated virtualization activity was present, but no audit tests, builds, or
local-model inference overlapped the measured passes.

The checked-in
[`remote_auth_security_throughput.toml`](../../native/bench/scenarios/remote_auth_security_throughput.toml)
scenario exercises a real RawSocket client and the remote auth service over
mTLS. Each process performs 1,200 actual warmup exchanges, then 1,000 serial
and 4,000 concurrent successful ticket exchanges. One router worker and one
native runtime thread are fixed. Each runtime mode uses baseline/patched/
patched/baseline/baseline/patched order with a three-second between-run cooldown.

| Runtime / workload | Baseline logins/s | Patched logins/s | Throughput delta | p95 baseline / patched, ms | p99 baseline / patched, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| JIT serial | 89.75 | 86.96 | -3.1% | 13.529 / 13.872 | 14.726 / 14.769 |
| JIT concurrent | 199.65 | 205.76 | +3.1% | 57.813 / 56.273 | 65.055 / 62.888 |
| AOT serial | 95.26 | 97.79 | +2.7% | 13.139 / 12.372 | 15.364 / 13.705 |
| AOT concurrent | 200.23 | 211.05 | +5.4% | 57.861 / 55.032 | 65.638 / 59.582 |

Values are medians of three independent process runs per variant, not pooled
latencies. BSD `time -l` process-tree measurements also remain close: median
peak RSS was 177,963,008 / 178,307,072 bytes (JIT) and
46,907,392 / 46,923,776 bytes (AOT), baseline/patched respectively. Median total
user+system CPU was 26.02 / 26.56 seconds (JIT) and 22.86 / 20.40 seconds (AOT).
Those process-tree measurements include startup, warmup, and control helpers;
they are not isolated auth-service allocation profiles.

The serial JIT result triggered the AOT confirmation rather than being
discarded. The slowdown did not reproduce consistently across runtime modes,
and run ranges overlap. These results support no consistent measured regression
on this host, **not** identical timing or a statistically proven speedup. This
is not a new production capacity claim. Native byte forwarding, payload crypto,
large frames, and file transfer were unchanged by this fix.

Reproduction uses the existing `http_stream` driver with `--scenario` pointing
at the file above, `--router-worker-counts 1`, and
`--native-runtime-thread-counts 1`. For the source/JIT pass, compile the baseline
and candidate `bench_router_service.dart` into separate kernel snapshots and
select each with `--bench-main`. For AOT, use `dart build cli` (not
`dart compile exe`, because dependencies have build hooks), supply the same
prebuilt `wamp_client_worker` to both variants with
`--wamp-worker-executable`, and launch the selected service executable through
the driver's `--dart` command adapter. The adapter removes the leading `run`
argument and executes the remaining command. The baseline auth package was
extracted from `733c6d91`; all other package sources and the native library were
identical between variants. Raw JSONL and `time -l` logs are retained in the
local `connectanum-security-auth-performance` and
`connectanum-security-auth-performance-aot` temporary evidence directories.

## SA-002 Initial Performance Evidence

**Not yet a cleared no-regression result.** The
[six-run comparison](2026-09-10-native-http-security-benchmarks.json) retains
every run, per-process medians/ranges, library/driver/service hashes, CPU/RSS,
and transport counters. The
[scenario](../../native/bench/scenarios/http_dependency_security.toml) uses one
router worker, four native threads, the same baseline benchmark client and AOT
router service for both variants, and swaps only the native library. Each
process performs 512 actual warmup requests per protocol, then 2,000 serial
1-KiB request/response exchanges and 4,096 multiplexed exchanges with 256-KiB
requests and 1-MiB responses per protocol. Order is A/B/B/A/A/B with a three-second
cooldown. The six measured passes complete 73,152 requests plus 6,144 warmups,
with no payload-count errors or protocol/internal/body/idle-timeout events.

| Workload | Baseline / candidate requests/s | Change | Baseline / candidate total payload Gbit/s | Baseline / candidate p99, ms |
| --- | ---: | ---: | ---: | ---: |
| HTTP/2 serial | 425.80 / 405.10 | -4.9% | 0.00698 / 0.00664 | 2.691 / 3.373 |
| HTTP/2 multiplexed | 2,531.52 / 2,540.94 | +0.4% | 26.545 / 26.644 | 8.976 / 9.979 |
| HTTP/3 serial | 421.41 / 416.93 | -1.1% | 0.00690 / 0.00683 | 2.796 / 2.978 |
| HTTP/3 multiplexed | 105.51 / 114.60 | +8.6% | 1.106 / 1.202 | 297.311 / 275.830 |

Values are medians of three processes, not pooled samples. Gbit/s sums request
and response payload bytes over workload wall time, including connection setup;
it is not a one-direction physical-link rating. Median process-tree CPU is
209.17 / 215.49 seconds; peak RSS is 164,888,576 / 160,497,664 bytes, baseline /
candidate. These include startup and helpers, not isolated allocator profiling.

An unrelated VM consumed approximately ten CPU cores during the later passes.
Baseline HTTP/2 multiplex throughput fell from 26-28 Gbit/s to 8 Gbit/s, and
candidate throughput also fell to 7.4 Gbit/s. All outliers remain included.
No audit tests, builds, or companion inference overlapped these six passes,
but other host work cannot be treated as controlled. A quiet repeat is required
to distinguish the serial HTTP/2 decrease and tail changes from contention.
Do not describe this as unchanged speed or a proven HTTP/3 speedup. Canonical
production-budget and large-frame/file gates now pass as recorded below, but
they do not resolve this relative comparison. The benchmark graph is now upgraded,
but driver-only performance must be compared separately with the patched server
held constant. The bounded security reproductions do not depend on timing noise.

Raw JSONL, BSD `time -l` output, and logs remain in the local
`connectanum-sa002-performance` temporary evidence directory. An initial setup
pilot is excluded a priori from the six timed passes; none of those six passes
was discarded. A report-parser type error after the first completed pass was
corrected to select numeric transport counters; its complete raw run was reused
without rerunning or overwriting it.

A subsequent lower-load attempt completed one baseline and one candidate process
(24,384 measured requests plus 2,048 warmups, no errors). It was stopped while
waiting between processes because unrelated inference repeatedly used many CPU
cores. No measured process was interrupted and no unrelated workload was stopped.
The same JSON retains both processes and before/after aggregate host CPU samples;
these are spot observations, not continuous isolation proof. One process per
variant is insufficient to resolve the earlier serial/tail comparison. Raw files
remain in the `connectanum-sa002-performance-confirmation` temporary evidence
directory. Performance remains **not cleared**, rather than selecting a favorable
pair or silently discarding the initial six passes.

### SA-002 Production Gates

With the upgraded benchmark driver and native library, all nine scenarios in
`bin/wamp-profile-validate` pass their existing policies: 102 workload gates
cover clear/TLS WAMP, control operations, pub/sub fan-out, E2EE, progressive
invocations, call timeout, and Meta APIs. The full large-frame scenario adds
24 workload gates and 864 samples with 12 GiB request plus 12 GiB response
payload. It covers native/Dart clients, JSON/MessagePack/CBOR, 64 MiB RawSocket
frames, 8 MiB WebSocket frames, and clear/TLS variants. The file-transfer
throughput scenario adds 30 workload gates and 408 transfers totaling 25.5 GiB.
No counter or performance-policy findings were reported in these 156 gates.

The existing policies were not weakened. These are absolute production gates
on a shared macOS host, not a paired speed comparison or Linux kTLS evidence.
Large-frame dominant-direction throughput ranges from 0.664 to 17.681 Gbit/s;
file-transfer throughput ranges from 2.190 to 20.634 Gbit/s across distinct
workloads. These ranges are not a single transport rating. The canonical
dominant-direction metric differs from the initial HTTP comparison's summed
request/response metric; do not compare those numbers as equivalent.

The same machine-readable evidence retains per-workload large-frame/file results
and gate counts, with the benchmark/native hashes. Raw summaries, JSONL,
Prometheus snapshots, and gate JSON/Markdown remain in the temporary
`connectanum-sa002-wamp-profile-validation`, `connectanum-sa002-large-frames`, and
`connectanum-sa002-file-transfer` evidence directories. No audit tests, builds,
or companion inference overlapped measured workloads; unrelated host activity
was not controlled. Driver-only and repeated native-library comparisons remain
required before claiming no measurable performance regression.

## SA-003 Performance Evidence

The [machine-readable comparison](2026-09-10-auth-lifecycle-benchmarks.json)
retains all six AOT passes in baseline/candidate/candidate/baseline/baseline/
candidate order. It includes source and binary hashes, toolchain, per-process
host CPU estimates, process time/RSS evidence, latency distributions, transport
error deltas, and raw JSONL/log hashes. Baseline Dart service code is SA-001
(`227b5b06`); the native library, driver, and AOT client worker are identical
between variants. The candidate changes only the auth service lifecycle, not
router dispatch. Both builds use the existing
`remote_auth_security_throughput.toml` workload: 1,200 warmups followed by 1,000
serial and 4,000 concurrent valid ticket logins per process, through RawSocket
and the mTLS remote auth service, with one router worker/runtime thread.

All 30,000 measured exchanges and 7,200 warmups completed without driver errors;
recorded protocol/internal/body-timeout deltas are zero. Values below are medians
of three independent process runs per variant, not pooled latencies.

| Workload | Baseline logins/s | Candidate logins/s | Delta | p95 baseline / candidate, ms | p99 baseline / candidate, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Serial | 81.06 | 79.96 | -1.4% | 15.610 / 15.571 | 16.685 / 16.662 |
| Concurrent | 185.68 | 191.80 | +3.3% | 60.552 / 59.173 | 75.878 / 73.088 |

Serial throughput ranges are 80.60-86.86 / 78.78-82.10 logins/s; concurrent
ranges are 179.24-186.78 / 184.34-192.11. Median BSD `time -l` maximum RSS is
46,907,392 bytes for both variants. Router RSS after the concurrent workload is
46,825,472 / 46,809,088 bytes; retained capacity under deliberately uncooperative
providers is tested separately, not measured by this valid-login workload.

No audit tests, builds, or companion inference overlapped these measurements.
Unrelated virtualization/emulator activity was present throughout; unrelated
inference appeared at the end of baseline pass 4 and beginning of pass 5 (roughly
1,036% / 1,152% aggregate CPU estimates). Every pass is retained, including those
observations. Ranges overlap and median tails/RSS are similar or lower, but the
serial median decreased and the host was not controlled. This is **provisional
evidence, not proof of zero overhead or release clearance**. Obtain quieter
confirmation before a strict no-regression claim; do not infer a speedup or
discard inconvenient runs. This comparison does not resolve SA-002's separate
HTTP performance concern or the broader native ownership finding.
