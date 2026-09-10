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
