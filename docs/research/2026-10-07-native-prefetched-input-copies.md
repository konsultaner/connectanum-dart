# Native prefetched input copy accounting

Date: 2026-10-07. Issues #100, #102 and #103 remain open.

`IoStream::buffer_front` stages protocol detection bytes and other prefetched
transport input. The previous prepend implementation cloned unread bytes into
a temporary vector and copied them again into the buffer. `poll_read` then
copies staged input into the caller's read buffer. These operations were absent
from transport copy totals. This boundary applies to RawSocket negotiation and
WebSocket upgrade input, including native client and router processes.

Two real TCP-pair regressions first failed with unmeasured counters. Adding
observations without changing the prepend implementation exposed nine staging
bytes for a case requiring seven. The implementation now allocates one combined
buffer and copies the new prefix and unread remainder once each. This example
observes seven staging bytes and five replay bytes. Empty prefixes and reads
with zero remaining capacity add no copied bytes. Direct TCP reads are excluded;
TLS plaintext volume is still distinct from memory-copy measurements.

The existing C snapshot and Dart layout remain 24 bytes. A separately named
`ct_transport_copy_metrics_snapshot_v2` exports a 40-byte layout with the legacy
prefix and two additional unsigned counters. Both Dart runtimes prefer this
symbol; a library exposing only the legacy snapshot leaves the new fields null.
Nullable deltas retain unavailable evidence. No database dependency, borrowed
foreign-memory adoption or allocator/ownership change is introduced.

The worker adds these counters to its own measured and known-copy totals. The
router merge requires both router counters and, for native clients, both client
counters before emitting a numeric complete transport total. The comparator
also requires the corresponding numeric nonnegative breakdown evidence. Older
reports cannot assert complete coverage by retaining the previous label alone.
TLS, Dart SDK, transcoding and whole-crypto pipeline unknowns remain fail closed.
All original performance thresholds and supplementary workload scope remain.

## Focused evidence

- `/tmp/connectanum-native-io-copy-before.{log,exit}`: two Rust regressions fail
  before measurement; the measurement-only intermediate has one failing case
  exposing the duplicate staging copy in
  `/tmp/connectanum-native-io-copy-measured-before-optimization.{log,exit}`.
- `/tmp/connectanum-native-io-copy-focused.{log,exit}`: both final TCP-pair
  regressions pass. `/tmp/connectanum-native-io-copy-abi-test.{log,exit}`:
  two FFI tests pass, including the legacy size/sentinel and null output check.
- `/tmp/connectanum-native-io-copy-merge-before.{log,exit}`: 24 pass and six
  fail before report integration. The final 30 cases pass in
  `/tmp/connectanum-native-io-copy-merge-focused.{log,exit}`.
- `/tmp/connectanum-native-io-copy-comparator-before.{log,exit}`: twenty missing,
  invalid or unavailable-counter subcases fail before enforcement. The final
  comparator/campaign suite passes all 39 tests in
  `/tmp/connectanum-native-io-copy-comparator-focused.{log,exit}`.
- `/tmp/connectanum-native-io-copy-dart-abi-{new,old}.{log,exit}`: the same
  snapshot/layout regression passes with the newly built library and the
  archived production `0ec8df06` Apple Silicon library respectively. `nm`
  confirms that the latter exports only the legacy snapshot.
- `/tmp/connectanum-native-io-copy-worker-focused.{log,exit}`: all eight live
  RawSocket/WebSocket RPC/pub-sub native-buffer/pre-encoded-span cases pass;
  each worker's numeric total equals its five measured copy components.

The initial fast check exposed two unnecessary-null-assertion warnings and a
missing direct test dependency. These were corrected without changing runtime
behavior or dependency versions. The first Linux snapshot omitted ignored Cargo
locks and stopped under `--locked`; both exact resolved locks were then added.
The failed setup log is retained. Final Linux arm64 checks pass at exit 0:
two real TCP-pair cases, two FFI cases, 31 Dart snapshot/merge cases and eight
live worker cases. All 18 overlaid source/lock hashes match the worktree inputs.
Logs are retained in `/tmp/connectanum-native-io-copy-linux-evidence/` and the
[checked-in proof](2026-10-07-native-prefetched-input-copies-proof.json).
Direct review identified process-wide counter races in an exact snapshot test.
The probe now runs in a fresh process; both old/new macOS libraries pass the
isolated variant; both new and archived production Linux libraries pass too. The first wrapper attempt was rejected because Dart test mains
cannot take arguments; the corrected no-argument wrapper uses a dedicated child
environment marker. No comparisons are weakened. The running fast check was
stopped before this test-only edit; fresh `bin/test-fast` then passes at exit 0 with all 1,616 benchmark cases.
The first full verification exposed a test-only library resolution defect and
was stopped after the new probe failed. An isolated reproduction with the exact
package-root/cleared-environment command also fails: the general client loader
selects a stale October 3 debug library lacking the snapshot symbol. The probe
now uses `nativeBenchTestLibrary`, the suite's existing helper selecting the
canonical `target/ffi-test/release` build. The same no-environment command passes;
no runtime loader behavior or assertion changes. Evidence:
`/tmp/connectanum-native-io-copy-full-mode-{before,after}.{log,exit}`.
Final full verification passes at exit 0 in
`/tmp/connectanum-native-io-copy-verify-final.{log,exit}`: Rust/VM/consumers,
1,616 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser cases
with the same 20 native-only skips. The final exact full-suite no-environment
probe passes on Linux as well. Only the test resolver changed after the passed
fast run; focused reproductions and final full verification cover that edit.
This is correctness evidence, not performance acceptance.
The initial local companion review was blocked by the native mutation campaign's
resource lease (`/tmp/connectanum-native-io-copy-local-review.{log,exit}`). The
lease later cleared. Qwen debug advice suggested verifying library identity;
the exact no-environment reproduction and source inspection confirmed the stale
debug preference. The first broad Qwen review reaches its output token limit and provides no final
result. A narrower native review completes. Its missing-import claim is rejected
because `use bytes::BytesMut` already exists; its empty-prefix claim is rejected
because the function returns before copying. The FFI test uses monotonic bounds
under shared counters, while the isolated Dart probe performs exact layout/value
comparisons; no global lock is assumed to cover all core traffic. Thread-local
source-site observations run in current-thread TCP-pair tests and reset per case.
No asserted speculative ordering/allocation risk establishes a new defect.
The separate report review completes with no concrete bug. Its residual notes
are checked: the native router always requires its own counters; missing client
counters are required only for native clients; available-only sums are explicitly
lower bounds with unavailable breakdown entries and partial coverage. Worker
null assertions are guarded by both counters being available. No source change
is indicated. Direct source review remains authoritative; no lease was bypassed.

## Preceding hosted coverage evidence

The published `0ec8df06` push's [Dart VM Coverage job](https://github.com/konsultaner/connectanum-dart/actions/runs/37565051795/job/112617197871)
passes. Its archived artifact reports 44,589/47,606 handwritten library lines
(93.66%), 45,318/51,044 raw lines including generated artifacts (88.78%) and
792/820 packaging lines (96.59%). These are scoped measurements and successful
configured gates, not a claim of universal 98% coverage. The new IO follow-up is
not in that commit; its resulting-head hosted acceptance remains pending.

The final Qwen test-ideas pass suggests null snapshots, measured zeroes,
native/Dart client separation and old ABI fallback. The first three are checked
against existing report guards/merge cases and live worker evidence; actual
old-library probes on both platforms confirm null fields without a crash. Both
missing counters follow the same unavailable path already tested individually;
no duplicate implementation-mirroring regression is added. Dart SDK coverage
remains incomplete independently of native input counters.

Both preceding `0ec8df06` hosted push/PR runs pass 40/41 jobs. Only their MCP
mutation gates remain active. Publication of the new local commits is held to
avoid cancelling those runs. No resulting-head hosted or performance acceptance
is inferred from preceding-source evidence.
