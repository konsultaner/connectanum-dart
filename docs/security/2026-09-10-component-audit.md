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
