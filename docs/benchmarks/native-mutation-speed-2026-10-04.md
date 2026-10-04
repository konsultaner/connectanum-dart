# Native Mutation Campaign Timing

Date: 2026-10-04. These are production-native timing pilots, not full mutation
campaigns, mutation gate passes or an estimate for the entire Dart/Flutter
repository. Native sources and workspace tests match `7e1083ab`.

## Method

Host: Apple M3 Ultra, 32 CPUs, 512 GiB RAM; other host workloads were not disabled.
Cargo/rustc 1.95.0 and cargo-mutants 27.1.0 are pinned. Each batch owns an isolated
source snapshot and cold build cache. Every viable mutation executes the same
534 workspace tests with `ffi-test`, locked dependencies, `--all-targets`,
`--no-fail-fast` and `--test-threads=1`. Build and test deadlines remain 180 seconds;
the batch deadline remains 14,400 seconds.

The production inventories contain 1,959 core and 1,297 FFI mutations. Pilots
partition each inventory into 512 batches and measure indexes
`0,64,128,192,256,320,384,448`. This selects 31 core and 21 FFI candidates.
The estimator extrapolates measured mean mutation work to the full inventory,
adds measured setup/cold-build/clean-and-restored-baseline overhead for 32 full
batches, and divides by observed effective parallelism, capped by the worker
and full-batch counts. It does not assume ideal linear speedup.

This is a deterministic sample, not a statistical confidence interval. The core
sample covers 8 of 12 production files; `http1_stream.rs`, `http_body.rs`,
`http_stream.rs` and `platform/mod.rs` have no sampled mutant. The FFI sample
covers 4 of 6 files, omitting `runtime/constants.rs` and
`runtime/resource_handles.rs`. Different failure
mixtures, timeouts, build cache behavior, longer shard lifetimes and shared-host
contention can change the actual full-run duration. Estimate components
sequentially; running both simultaneously has not been measured.

## Measurements

| Component / configuration | Sample | Measured pilot | Estimated full component, 32 batches |
| --- | ---: | ---: | ---: |
| Core, default test profile, 4 workers / 4 Cargo jobs each | 31 | 11m55s | 8.16h |
| Core, debug information disabled, 8 workers / 4 Cargo jobs each | 31 | 7m33s | 4.92h |
| FFI, debug information disabled, 4 workers / 4 Cargo jobs each | 21 | 7m50s | 4.07h |

Estimated full native scope is **3,256 mutations** across both components.
Running the fastest successful configurations sequentially gives **8.99h**
(core at eight workers, FFI at four). Keeping both components at four workers,
using the measured default-debug core and lean-debug FFI profiles, gives
**12.23h**. Neither figure is a measured complete run, a passing mutation score,
a universally reliable deadline or a hosted-CI estimate. Given the rejected
higher-concurrency baselines, prefer the four-worker setting for unattended work.

The matched core pilots have identical source/test hashes, mutant identities,
outcome classifications and 534 baseline test identities. Their measured pilot
speedup is **1.58x**, or 36.6% less elapsed time. The corresponding modeled
full-core reduction is 8.16h to 4.92h. This is stronger evidence than the previous
tiny synthetic fixture, but it is still not a measured full campaign.

In the four-worker core pilot, mutation builds consume 125.22 seconds and tests
1,483.19 seconds: **92.2% of mutation phase time is testing**. Mean mutation cost
is 51.88 seconds, median 42.50 seconds and p95 183.31 seconds. The lean-debug
eight-worker pilot spends 99.40 seconds building and 1,470.73 seconds testing,
with mean cost 50.65 seconds. Reducing debug information helps cache size and
build work; it does not remove the dominant repeated test cost. Observed private
caches are roughly 1.6-1.8 GiB with default debug information versus 1.0-1.1 GiB
after lean-debug mutation work.

The FFI pilot spends 34.94 seconds building and 765.70 seconds testing:
**95.6% of mutation phase time is testing**. Mean mutation cost is 38.13 seconds,
median 38.06 seconds and p95 38.66 seconds. Observed effective parallelism is
3.62, versus 3.59 in default-debug core/four-worker and 5.85 in lean-debug
core/eight-worker. Mean per-batch non-mutation overhead is 112.57 seconds for
FFI, 119.87 seconds for default-debug core and 135.22 seconds for lean-debug core.
All eight FFI initial and restored baselines pass. Its source/test hashes and
534 baseline test identities exactly match the core pilots.

Even eliminating mutation build time entirely would reduce these measured
mutation phases by only 7.8% for default core and 4.4% for FFI. That excludes
clean/restored-baseline overhead. Further large gains require improving repeated
test execution and safe scheduling, not just compiler caching; dropping tests or
loosening mutation/baseline timeouts is not an accepted optimization.

Both core samples retain 9 assertion kills, 11 errors, 6 survivors, 3 compile
errors and 2 timeouts. Their initial/restored baselines pass, but these outcomes
do **not** establish a passing mutation gate. No error, survivor or timeout is
converted into kill credit to improve either the score or the timing estimate.
The FFI sample likewise retains 8 assertion kills, 6 errors and 7 survivors;
it is timing evidence, not a passing mutation campaign.

The earlier 25.75h figure extrapolated 65 outcomes to a then-current 1,939-mutant
core inventory. It was not a measured single regression run or an estimate for
all native plus Dart/browser/Flutter targets. Comparisons with that historical
figure are not controlled speedup measurements.

## Rejected Configurations

| Experiment | Observed rejection |
| --- | --- |
| Core, default profile, 8 workers | Two initial baselines fail the TLS terminal-frame test; run completes unsuccessfully after 488.53s. |
| Core, lean debug, 16 workers | Eight of sixteen initial baselines fail the same TLS test; owned run stopped at 309.30s. |
| Core, lean debug plus opt-level 1, 16 workers | Seven retained baselines fail TLS; three also fail HTTP/3 owner cleanup. Owned run stopped at 223.95s. |
| FFI, lean debug, 8 workers, before selector fix | All eight batches reject the selected inventory before executing mutations. |
| FFI, lean debug, 8 workers, after selector fix | One initial baseline fails the TLS test; owned run stopped at 119.88s. |

The TLS assertion's five-second completion deadline is unchanged. The optimized
experiment explicitly retains debug assertions and overflow checks. Cold builds
in that experiment complete in 81-117 seconds: these are test failures, not
build timeouts. Resource contention is plausible, not a proven explanation of
the flush failure. Do not weaken a baseline/deadline or report a rejected run
as a valid speedup. Eight workers are the fastest usable core observation, not
a demonstrated universally reliable default. Keep four workers as the default
until higher-concurrency baseline reliability is resolved.

## Tooling And Evidence

The new timing pilot is fresh-only: it rejects cached batches, audits retained
raw mutation outcomes and baseline logs, pins inputs/tools/compiler/build
configuration, and writes `pilotComplete` without campaign `complete`, a
`combined.json` or a mutation gate pass. The profiler rejects missing/impossible
durations and changed provenance. Full campaigns keep the exact union gate.

The first FFI pilot exposes a cargo-mutants 27.1.0
[struct-field regex filtering issue](https://github.com/sourcefrog/cargo-mutants/blob/v27.1.0/src/visit.rs#L703-L748).
Inventories containing field deletions now use Cargo's
[post-discovery round-robin sharding](https://mutants.rs/shards.html), with exact
discovery-order checks for full, selected and executed inventories. Other
inventories retain the original identity-sorted selector. The real two-crate
regression executes all eleven candidates, including both field deletions,
exactly once with all original tests and assertion kills. No operator is waived.

Core pilots were collected before this FFI-specific fix and the estimator's
projected-batch concurrency cap. Their byte-exact measured tools are preserved
in `out/native-mutation-speed401/measured-tools-v1.tar`. Independent reaudits with
that tool snapshot and current unchanged native inputs reproduce both timing
reports exactly. The cap does not alter these estimates: 32 projected batches
exceed both configured worker counts. FFI measurements use the final tooling;
never relabel or reuse the core raw evidence as current-tool mutation evidence.
Adding component cost estimates is not combining mutation scores.

Artifacts, under ignored `out/native-mutation-speed401/`:

- `core-default-4/` and `core-default-4-timing.json`.
- `core-debug-8/` and `core-debug-8-timing.json`.
- Rejected `core-default-8/`, `core-debug-16/`, `core-opt1-16/`,
  `ffi-debug-8/` and `ffi-debug-8-fixed/`.
- `ffi-debug-4-fixed/` and `ffi-debug-4-fixed-timing.json`: final audited FFI pilot.

Core profiler SHA-256:
`a24d1e7801c3ae8f8751f128ea97e323abe70a9d4f283407e56d8122ebcda30d`.
Four-worker pilot manifest SHA-256:
`8836d7cc647f2ba1442757774709dec363ac234cad6dd7ea1f51dea7acba5f53`.
Eight-worker pilot manifest SHA-256:
`f48e34c8fc15404958989ada713377c05e3f91d482ce36e07eec529a54c49b45`.
Final FFI profiler SHA-256:
`5fc930a12ff854eae8be2b4abc0eeccdcbd94dfefd02aead7d5cd927405edb1a`.
FFI pilot manifest SHA-256:
`7b2393f18780455bf52f4d6204f07180f32914366f58feb4d118dc4d7aa3d3ce`.

Reproduce with the commands in
[Production Timing Pilots](../testing-and-mutations.md#production-timing-pilots).
Set `CARGO_PROFILE_TEST_DEBUG=0` for both lean-debug collection and analysis.
[Cargo profile settings](https://doc.rust-lang.org/cargo/reference/profiles.html)
control debug information independently of assertion/overflow behavior.

The repository-wide estimate remains open: its configured 56 Dart VM and 17
Chrome targets, plus separately configured file/Flutter mutation work, are not
timed here. Faster native collection does not make survivors or the existing
remote-auth assertion gate disappear.

## Verification

`bin/test-fast` runs before changes and exits 0. All 90 native collector, batch,
coordinator and timing-profiler regressions pass, including real Cargo field
sharding, raw-evidence tampering, cached-pilot rejection and concurrency-cap
cases. Fresh `bin/verify` exits 0 after timing collection, including native,
package/consumer, router and Chrome/Dart2Wasm core/client checks. No hosted
candidate result or completed production mutation campaign is claimed.
