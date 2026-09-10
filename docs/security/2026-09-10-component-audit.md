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

**Open. Shipping-path dependency updates and performance validation required.**

`cargo audit` against both checked-in Rust lockfiles on 2026-09-10 reports:

| Dependency | Resolved | Advisory | Scope / next action |
| --- | --- | --- | --- |
| `h2` | `0.3.27` | [RUSTSEC-2026-0258](https://rustsec.org/advisories/RUSTSEC-2026-0258.html) | Direct `ct_core` HTTP/2 dependency; empty DATA frame queuing can exhaust memory when streams are not drained. Migrate to patched `>=0.4.16` and validate HTTP type compatibility and HTTP/2 performance. |
| `quinn-proto` | `0.11.14` | [Upstream advisory](https://github.com/quinn-rs/quinn/security/advisories/GHSA-4w2j-m93h-cj5j), RUSTSEC-2026-0185 | Direct/transitive native QUIC dependency; excessive out-of-order gaps can exhaust memory. Patched `>=0.11.15`; inspect upstream mitigation and test HTTP/3 performance after updating. |
| `rustls-webpki` | `0.101.7` | RUSTSEC-2026-0104, RUSTSEC-2026-0098, RUSTSEC-2026-0099 | Benchmark-control `reqwest` 0.11.27 / `hyper-rustls` 0.24.2 / `rustls` 0.21.12 dependency, not the production router TLS server. Control client intentionally trusts lab certificates and uses HTTP/1; assess advisory-specific reachability and update this older client dependency. |

Dependency resolution is confirmed, but no Connectanum-specific adversarial
network reproduction has yet been run for these advisories. No dependency
updates have been applied. The three older WebPKI reports are not evidence that
the router's current Rustls server uses that version.

The RustSec database used for the scan was commit
`b50980aad8b8f14f77e25a97b32dd94bf008b0af` (updated 2026-09-09). Reproduce with
`cargo audit --file native/transport/Cargo.lock` and
`cargo audit --file native/bench/Cargo.lock`.

The transport lockfile additionally reports maintenance warnings for
`rustls-pemfile`, `serde_cbor`, and the renamed `xsalsa20poly1305` crate. These
are maintenance risks, not proof of exploitable vulnerabilities. Dart and
standalone-application dependencies were also queried below; platform-native
dependencies and bundled assets still need separate review.

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
- The first audit slice is local. Hosted verification has not been requested
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
