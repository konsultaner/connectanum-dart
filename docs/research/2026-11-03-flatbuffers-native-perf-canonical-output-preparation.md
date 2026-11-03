# Canonical output declaration aligned with the selected verification recipe

The source-only canonical producer declared the standard release library, while
the selected `bin/verify` → `bin/test-all` → `build_native_ffi_test_release`
chain builds and selects `native/transport/target/ffi-test/release`. A nonempty
`CONNECTANUM_CI_NATIVE_DIR` can select a separate CI artifact branch, which this
producer recipe did not declare. These are source integration gaps; no actual
canonical run or production performance defect was observed in this phase.

The factory and the emitter's location predicate now share the own ffi-test
path. The factory refuses nonempty undeclared CI artifact reuse before its
constructor. Empty/unset reuse settings preserve the fixed `bin/verify`
recipe. The production factory, its target locations and its original RLIB
pattern remain unchanged.

Six new source/path guards initially produce four failures, one error and one
pass. The two platform cases execute only the two verbatim selected shell path
functions with an OWN fixture root and **synthetic** Darwin/Linux `uname`.
Factory positives replace the constructor; output-location positives are pure
data predicates. They never build, emit or adopt a live receipt.

An intermediate extraction error double-escaped the RLIB pattern: thirteen of
fourteen selected tests pass and one pure valid-RLIB location errors. Restoring
the exact original regex value yields fourteen passes: six new factory/path
guards, five pure location guards and three required existing factory callers.
This is neither the earlier 78-test proof nor full canonical verification.
The earlier suites, method controls and numerical campaigns were not rerun.

[Root assessment](2026-11-03-flatbuffers-native-perf-canonical-output-assessment.json)
and [retained evidence](2026-11-03-flatbuffers-native-perf-canonical-output-evidence.tar.gz)
retain original/before/intermediate/fixed source snapshots, executed coordinator
text, fixtures, actual logs, advice and qualifications. The archive contains all
selected regular files in this new phase directory, with the unrelated full
private checkpoint snapshot explicitly excluded. Special nodes are metadata
only. Existing fixture Git setup API returns are not all separately serialized;
the new finite Bash path queries retain stdout, stderr and direct status.

The Qwen test advice completes according to its saved helper output; its outer
terminal session status was not retained. The Qwen selected-diff review
completes with direct status zero. Root rejects the proposed path normalization:
the constructor already requires canonical source/run-parent paths, and
subsequent regular-file checks reject resolved-path drift. Existing bounded
checks do not establish atomic write prevention or authentication. Ambient
environment is cleared for every new factory call; pure location predicates do
not read it. No new Windows support or measured hashing cost is claimed.

This phase changes two of the twenty uncommitted tools; the other eighteen
match its before epoch. Together with the prior admission pair, four files now
differ from the earlier Linux method epoch. Production packages/native and the
selected verification scripts remain unchanged at source commit
`601108ea6216464bd00ae29c16cfaf0a59c71db6`. The helper bundle still has twenty
members, and all remain uncanonical and unadmitted.

Available space is about 8.7 GB at the final scoped observation, above the
1 GiB scoped-test floor and below the unchanged 12 GiB build floor. No files
were deleted and no compiler, canonical build, actual native recipe, kernel
control, benchmark, capture or strict campaign ran. Space-change cause remains
unmeasured.

The independently owned orchestration and complete current-source provenance
remain required, including actual canonical/build outputs, native/driver/RLIB,
locks, hidden configs, SDK/compiler/tool/kernel identity and original-host
credential/access/inheritance/arming/role/timing/metadata/coverage controls.
The live provider is absent, live admission always refuses and the controller
remains closed. No RAM cause, repair, performance acceptance or source adoption
is established. PR #132 remains open and draft; issue #103 and the milestone
remain open.
