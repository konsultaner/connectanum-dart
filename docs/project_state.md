# Project State

Last updated: 2026-10-04.
Current milestone: [FlatBuffers and zero-copy native buffers](https://github.com/konsultaner/connectanum-dart/milestone/1).
Active plan: [FlatBuffers execution plan](exec-plans/2026-10-03-flatbuffers-zero-copy-native-buffers.md).
All ten issues (#95–#104) remain open. Draft PR: [#105](https://github.com/konsultaner/connectanum-dart/pull/105).

## Checkout and authorization

The managed worktree uses `codex/flatbuffers-zero-copy`; last pushed commit is
`d26581c3e1779788cf565437d6cd83588cdba2c7`. It started at `54eafc5f` and
integrates released master `3bac4cf5`. The primary checkout's independent work
remains untouched. Feature commits, pushes and draft PR updates are authorized;
releases, version bumps, publication and merging master are not authorized.
Actual ObjectBox integration belongs in a separate adapter. Core provides generic
memory contracts. The earlier coverage/mutation objective is deferred.

## Uncommitted candidate

Portable/native sibling providers implement a Connectanum-local version-2
`wamp` / `flatbuffers` E2EE profile for XSalsa20-Poly1305 and AES-256-GCM. They
preserve one raw application span, reject keyword containers and share machinery
with unchanged version-1 CBOR providers. Session selects exact profile/provider
compatibility. This is not a standardized WAMP E2EE version; application schemas
and all outer metadata are not validated or authenticated by this profile.

An optional native consume-format-wide API returns complete typed plaintext.
Format 0 preserves legacy CBOR unwrapping; missing typed exports use generic raw
decryption. Read-only outputs retain their owner through backing/derived views.
Explicit root release invalidates those views. Opt-in
`materialize(..., deferPayloadExports: true)` postpones all exports until the first
getter. Consume/release before export invalidates unexported getters; already
exported ciphertext remains valid and forces the safe copied fallback. Ordinary
transports/Session remain eager. Actual VM-service GC and 42 ownership matrix
cases are included in the 135-case runtime cohort.

Ordinary benchmark factories now support FlatBuffers, whose WAMP envelope uses
FlatBuffers and dynamic argument fragments use CBOR. Internal RPC transfer now
records the actual native serializer separately from fragment encoding. The
repaired peer speaks FlatBuffers, uses RawSocket ID 5 and acknowledges the profile.
Focused checks pass 78 factory and 16 live transport/RPC/pubsub cases. Typed
benchmark workloads remain a separate unfinished prototype.

The new macOS Native Ownership GuardMalloc CI job verifies failure controls and
uploads logs, exact source/executable hashes and dependency lock. Full Verify
depends on it. Both canonical scripts include its five tooling controls. A missing
Cargo lock is resolved before freezing the native inventory; compilation then
uses `--locked`. Timeout/interruption logs and owned-process cleanup failures are
retained and fail closed. Actual feature-tree execution passes 57 instrumented
cases, with loader/count/log evidence independently recomputed:
`/tmp/connectanum-flatbuffers-native-memory-feature-default-repo-completed-audit.json`.
This is local macOS execution, not hosted, all-platform, ASan/Miri or performance
acceptance.

## Current verification

The preceding 1,450-file candidate passes both canonical fast/verify on snapshot
`b77da9a480509729d469e9d7ca91cf3bda5b5fc96132ff2030e4ded92afed1ea`.
All product/native/log hashes are audited:
`/tmp/connectanum-flatbuffers-deferred-factory-repaired-canonical-completed-audit.json`.
Local canonical scripts select Chrome WASM on macOS; hosted Linux selects JS.
Separate focused Session checks pass 44 cases each in Chrome JS and WASM.
The earlier description of both compilers as local canonical execution is corrected.

After applying the test-only loop oracle and memory CI tooling, fresh combined
fast/verify passes on unchanged 1,452-file snapshot
`edce848870ae28ab3aee2a7e30f144e9b230ab00112c7831085e560187cd40a0`.
Prefix: `/tmp/connectanum-flatbuffers-native-memory-loop-canonical-*`.
Both process exit codes, all product/native/log hashes and preserved history
bytes are independently audited in `*-completed-audit.json`. Canonical browser
execution is Chrome WASM on this host.
The native ffi-test library remains SHA256
`9884a14303c9036eec642cd55470f105dbfb898e62b3e4cb9ee28ffc179a2a78`.

Current production native library SHA256
`01c90d8dbc169e49874e7755f06086e2f57c20fbc56f479961cb68fe678aef9c`
builds without ffi-test and passes 116 explicit VM provider/runtime cases.
The typed-format export exists; four actual owner-oracle exports are absent, with
positive controls against ffi-test. Audit:
`/tmp/connectanum-flatbuffers-typed-production-vm-completed-audit.json`.
The initial command completed VM cases but failed by attempting FFI WASM loading;
its failed report remains retained. Its misspelled symbol-absence check is discarded.
Older d265 production ABI fallback checks also remain valid independent evidence.

## Mutation acceptance

Unchanged production source has 300 core E2EE mutations. The repaired loop oracle
uses a distinct throwing policy sentinel so skipped byte conversion cannot proceed
to expensive 64 MiB decryption. Four observed timeout mutants are assertion-killed
at unchanged deadlines, with restored baseline passing. The full VM campaign
passes 235 kills, ten survivors and 55 compile errors at 95.9184%; no timeouts,
unknown/testError-only kills or new equivalents. All classifications and mutation
hashes are audited; source/test/support and target inputs match the feature tree:
`/tmp/connectanum-flatbuffers-typed-e2ee-loop-bound-committed-snapshot-core-e2ee-vm-feature-input-completed-audit.json`.
The matching Chrome JS campaign also completes all 300 mutations with the same
235/10/55 counts and 95.9184% assertion score, no timeouts or new equivalents,
and restored baseline exit 0. Its wrapper exits 1 because the separate audit
helper generated one `tool/__pycache__/run_dart_mutations.cpython-314.pyc` during
execution. The original failed wrapper report is preserved. An independent audit
verifies that exact sole added artifact, every frozen source/test/support byte,
all 300 classifications and mutant hashes, unchanged gate/deadlines, and feature
input equivalence:
`/tmp/connectanum-flatbuffers-typed-e2ee-loop-bound-committed-snapshot-core-e2ee-web-feature-input-cache-reconciled-completed-audit.json`.
The mutation process exits 0; the wrapper is not relabeled as passing.

Earlier failed campaigns remain failed: original VM 90.9465%; expanded VM with
one timeout; original browser with three timeouts at 94.6939%; logical-fixture
browser with one timeout at 95.5102%. The complete logical browser failure is
independently audited:
`/tmp/connectanum-flatbuffers-typed-e2ee-logical-bound-committed-snapshot-core-e2ee-web-completed-audit.json`.
Canonical fixture-registration, fake-peer, support-list and analyzer failures,
partial interruptions and scratch startup/mode/lock failures remain retained.
They are repaired or superseded evidence, not passes. See the history archives.

## Last pushed hosted evidence

[PR CI run 37196989435](https://github.com/konsultaner/connectanum-dart/actions/runs/37196989435)
passes all 40 jobs at d26581c3. Local canonical, complete lazy VM/web and binding
mutation gates pass; browser client coverage is 96.5283% above 96.29%.
[Native Artifacts run 37197154855](https://github.com/konsultaner/connectanum-dart/actions/runs/37197154855)
passes five platform builds with publication skipped. Downloaded source manifests,
checksums and provenance verify. Apple Silicon executes 34 native cases and a
standalone consumer; other platform binaries are not executed on this host.
PR #105 now records these completed hosted results. They do not clear the newer
uncommitted candidate or the new memory CI job.

## Next work

Review the verified stage, commit/push, update the draft PR and verify exact-head
CI/artifact consumers. The canonical checks and complete VM/browser mutation
gates are audited; the browser wrapper cache discrepancy is explicitly retained.
Then preserve native payload capability through negotiated Session wrapping and
choose runtime decryption before opaque exports. Merely setting deferred mode in
the transport would still export through its `incoming.message` getter. Existing
immutable ciphertext and forwarding semantics must stay valid. Session defaulting
also invokes a key policy before underlying typed preflight; reproduce that
ordering concern before changing it. Source audit:
`/tmp/connectanum-flatbuffers-session-native-crypto-capability-audit.json`.

Connect native-owned construction through encryption/submission; generic crypto
still copies input/output. Complete external session conformance, malformed-input/
fuzz and ownership CI, supported-platform consumers and adapter/release docs.
Declare representative performance/copy budgets before controlled measurement.
No throughput parity is established. The pinned Autobahn object serializer is not
a functioning live peer; independent generated Python codec fixtures do not prove
full session conformance. Audit every issue before closing this milestone.

## Research and preserved history

[Binding](flatbuffers_binding.md), [PPT/E2EE](e2ee_ppt_research.md) and
[ownership](native_buffer_ownership.md) record the contracts.
[Prior state](history/2026-10-04-project-state-before-flatbuffers-consolidation.md)
and [implementation journal](history/2026-10-04-flatbuffers-implementation-journal.md)
preserve earlier notes byte-for-byte. Their older entries are historical checkpoints.
