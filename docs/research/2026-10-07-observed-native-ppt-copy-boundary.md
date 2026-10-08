# Observe the owned PPT submission before reporting zero copies

The worker previously reported `optimized_payload_copy_bytes=0` from scenario
settings alone. That did not prove the native frame path ran: unavailable frame
support, an ineligible owner or another fallback could leave the same settings.
The numeric zero now requires an observed native submission for every sample.

Observations are opt-in and keyed weakly by the exact `NativeOwnedBuffer` that
the native PPT resolver selects. The resolver already verifies the exported
byte view and its owner. The transport records that owner's encoded length only
after `sendNativeFrame` returns successfully. This observes acceptance into the
native queue, not peer delivery or TLS copies. Existing native frame pointer and
lifetime tests establish that this path retains application spans without
flattening them. No ABI, wire format, fallback or native ownership rule changes.

Each prepared benchmark payload has a distinct owner. Its sample stores three
optional fields: `native_ppt_frame_submissions`, `native_ppt_payload_bytes` and
`native_ppt_payload_reused_bytes`. Each relevant sample must have exactly one
submission, a nonnegative encoded length and the same number of reused bytes.
Missing evidence, fallback, repeated submission or a size mismatch remains
`not_measured`. Samples cannot cancel each other's counts. An observed empty
owner is distinguished by count one and length zero. Legacy samples still load,
but their absent observations cannot establish zero copies. New JSON fields
reject fractional, negative, nonfinite and inexact values without coercion.

The marker does not reset observations. Weak keys hold no extra native lifetime,
and normal application sends allocate no observation objects. Benchmark owners
for CBOR/MessagePack use the same opt-in bookkeeping; their existing payload
copy classification and construction counters are unchanged. Reused byte volume
is evidence for this submission path and is not itself copied-byte volume.

The fail-first suite records 36 failures and one passing case before the repair.
The final focused suite passes 121 cases. Actual native RawSocket/WebSocket tests
pass 32 cases on macOS and Linux arm64, including rejected profile sends, nested
owners, copying fallback and explicit caller disposal. Twenty live benchmark
cases pass on both systems, including concurrent worker RPC/pub/sub and both
native-buffer/pre-encoded construction. The eight new worker cases exercise
RawSocket and WebSocket and check each owner after serialization through the
worker process. All nine executed Linux source inputs match the feature files.

GLM design review correctly rejected process-wide aggregate reconciliation;
the implementation uses per-owner observations instead. Its queue-versus-delivery
and optional-field concerns are covered by the scope and tests. Qwen test advice
incorrectly equated reused bytes with optimized copied bytes; those numerical
suggestions were rejected. Final local review was blocked by the machine's active
native mutation resource lease. Direct source review and focused verification
completed; the lease was not bypassed. Analysis exits zero with four pre-existing
style infos in the WebSocket test fixture.

Baseline `bin/test-fast` passes. Full `bin/verify` passes at exit zero, including
Rust/VM/consumers, 1,609 benchmark, 4,958 router, 4,751 core browser and 2,829
client browser cases, with 20 unchanged native-only skips. Evidence:
`/tmp/connectanum-observed-owned-copy-verify.{log,exit}`. Resulting-head hosted
verification remains pending.
The strict 1,440-row primary matrix, all copy fields, timing/statistical budgets
and #100–#104 remain unchanged and open. Total SDK/TLS/transcode/crypto accounting
is still incomplete, and the failed preceding campaign supplies no acceptance.

[The proof](2026-10-07-observed-native-ppt-copy-boundary-proof.json) records
source/log hashes, failed attempts, scoped observations and verification status.
