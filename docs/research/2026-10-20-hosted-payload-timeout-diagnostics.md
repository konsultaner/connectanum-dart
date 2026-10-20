# Capture the unresolved hosted payload-size timeout before cleanup

Issue [#103](https://github.com/konsultaner/connectanum-dart/issues/103) remains
blocked by numerical parity failures and incomplete supplemental execution.
This diagnostic adds evidence for the execution failure; it does not repair
the timeout or accept performance.

## Retained observations

The strict Linux diagnostic on integrated source `9e964951` completes all 90
rows. Independent evaluation reproduces its comparison exactly. All three
allocation comparisons pass, but eleven numerical gates fail in addition to
the diagnostic-ineligibility guard. Native-buffer CPU is 1.017585 and throughput
is 0.997779 relative to the better binary baseline. No budget changes.

The renewed supplemental payload-size batch on `8104d339` stops after 20 rows
in its first warmup pass. Its `ext_18_payload_sizes_flatbuffers` workload is a
Dart caller, TLS WebSocket, one-MiB typed RPC payload, 1,000 minimum samples and
a ten-second minimum window. Immediately preceding CBOR/MessagePack workloads
complete. The 300-second driver timeout issues a stop request before the
worker-stopped warning. That warning therefore does not establish an earlier
worker crash. Server shutdown statistics retain one pending invocation.

- [Original failing hosted run](https://github.com/konsultaner/connectanum-dart/actions/runs/39433310792).
- Payload-size archive SHA-256:
  `95c9764ffc1c751630f50bb782bcd48d4b772c223183b23fc2189344ca117bdc`.
- Ninety-row diagnostic archive SHA-256:
  `ca4d52a7ed6ad4528e4cc5dced3279104244d800840e9c59c90eac3adf7d5715`.

Replaying the exact first warmup scenario locally completes all 36 rows with
unchanged source inputs and process cleanup. This includes the failing hosted
step, but does not reproduce its failure. The local platform is macOS arm64,
Dart 3.13.1 and Rust 1.95.0; hosted measurements use Linux x64, Dart 3.13.5 and
Rust 1.99.0. Local success cannot resolve the hosted blocker.

Four retained server allocation windows also remain unavailable. Their native
collection counters match every recorded GC event. Conservative uncertainty
is 1.1295%, 1.1584%, 1.0672% and 1.0047%, above the unchanged one-percent limit.
They are not negative estimates or missing timeline events. Do not substitute
the SDK's misleading accumulated-size label: the pinned
[`ClassTable::AllocationProfilePrintJSON`](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/vm/class_table.cc#L285-L346)
prints accumulated and current sizes from the same heap visitor counts.

## Opt-in hosted reproduction

Choose `flatbuffers_payload_repro` in WAMP Profile Benchmarks. The existing
pinned production build and no-test-oracle export check remain in force. The
executor prepares the complete unchanged payload-size schedule, then
`tool/capture_wamp_stall.py` replays all ten original scenarios: three warmup and
seven measured passes, 360 rows, in the original shared process context. The
other campaign choices keep their existing commands, cases and gates.

The diagnostic retains the exact workload order, sample/duration fields and
300-second workload and 19,800-second full-schedule deadlines. URI-only Dart wrappers identify the already-enabled
client/router VM services. After sixty seconds without driver log progress,
bounded `getVM`/`getStack` requests retain stacks or explicit service errors
before teardown. Up to three observations are retained per stalled progress
point. Fresh output directories prevent overwriting existing evidence.

The artifact contains the original scenario, actual ephemeral listener config,
wrapper sources, source/lock/binary hashes, unmodified driver log bytes, raw
reports, stack snapshots and exit/cleanup results. Truncated, reordered, missing
or undersampled reports remain failed. Source, lock or binary changes prevent
a completed claim. The tool owns only its new process group and always labels
results `stall_reproduction_never_acceptance`. Stack capture perturbs execution;
this instrumented replay cannot establish primary or supplemental acceptance.

Local tests use fake drivers and temporary Git repositories, including startup
failure, descendant cleanup, source mutation, invalid evidence and VM errors.
The initial eleven tests pass, alongside 24 campaign-runner, nine profiling and fourteen
CI execution checks. YAML, all fourteen Bash run blocks and their embedded
Python parse. A live three-codec one-MiB smoke run completes with actual client
and router VM stack responses, unchanged source/lock/binary hashes and complete
process cleanup. The short capture trigger in that smoke run is diagnostic
instrumentation, not the hosted sixty-second default or performance evidence.
The actual hosted capture and a causal regression are required before changing
application behavior. The native table-allocation optimization remains deferred
until this execution blocker is understood.

## First hosted replay and effective compiler selection

The first `f88a8f3d` Linux replay completes all 36 original warmup rows with no
timeout, stall capture or allocation gap. Source, lock and binary hashes remain
unchanged, and the original order matches. Its archive SHA-256 is
`8897c3abd267444d2400382cec09bbabdceaa5ea074926a66feeb84bf0d77fa2`.
It does not resolve an intermittent failure: the runner image changes from
`ubuntu24/20261012.334.1` / Linux 6.17 to `ubuntu24/20261018.339.1` / Linux 7.0,
and the reported compiler changes from Rust 1.99.0 to 1.99.1.

The action log confirms installation and default selection of Rust 1.99.0.
However, this repository's `rust-toolchain.toml` selects `stable`. The
[rustup override order](https://rust-lang.github.io/rustup/overrides.html)
places repository toolchain files above the default, and places the
`RUSTUP_TOOLCHAIN` environment above both. Campaign and CPU-profile jobs now set
that environment to 1.99.0 and verify the effective `rustc` version before use.
The old action selection alone did not enforce its apparent pin. A regression
fails for both jobs before the correction and passes afterward.

The complete diagnostic now copies lexically sorted regular TOML files,
preserves within-file order and repeated workload names across passes, ignores
nested/symlink entries exactly like the native driver, and rejects changes to
original/copied contents or scenario inventory. Exclusive destination creation
prevents case-alias collisions from overwriting evidence. Sixteen focused
tests cover these cases and the effective toolchain contract. The original
300-second workload and 19,800-second full-campaign limits remain unchanged.

## Verification checkpoint

Before this diagnostic addition, source `8104d339` passes canonical `bin/verify`
and fresh `bin/test-fast`. All 3,154 source inputs and resolved locks remain
unchanged. A separate production build has no `ct_test_*` exports; its native
library SHA-256 is
`73087fa1e77edd209b6b440a672aaf64896cea36e8e57a1d9a2a995215813eb1`.
Detailed evidence is under `out/flatbuffers-resume-20261020/`. The diagnostic
addition requires its own final verification and hosted observations. Historical
failed campaigns remain failed. No sample, duration, deadline, copy scope,
precision limit or parity threshold is relaxed.

The full hosted CI run on `8104d339` subsequently passes. Frozen `f88a8f3d`
passes 120 production copy cases and all 300 short correctness rows, including
32 declared zero-avoidable-copy observations; all 3,157 inputs remain unchanged.
Production source inputs match the binary built on `8104d339`. The copy-gate
criterion in #103 is checked separately from the five unmet criteria. The new
cleanup test also follows the existing process-group contract: a dead zombie
awaiting host reaping cannot execute or retain sockets, so it must not be
mistaken for a live leaked child.
