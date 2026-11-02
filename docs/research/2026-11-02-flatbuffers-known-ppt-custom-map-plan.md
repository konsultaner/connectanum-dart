# Known-only PPT custom-map hypothesis

Status: **rejected**, with no source change retained. The executed metadata-byte
alias counterexample invalidates the zero-pending budget. See the [rejection
and preserved evidence](2026-11-02-flatbuffers-known-ppt-custom-map-rejection.md).
The following records the original hypothesis and preparation history.

Receive/control source tracing identifies a narrow allocation hypothesis,
without establishing a production defect or RAM cause. `NativeSessionMessage`
creates a mutable lazy custom-details map and a deferred dictionary loader even
when the existing exact FlatBuffers PPT matcher can prove that the dictionary
contains only the two projected PPT string fields and no custom fields.
Session RESULT/EVENT/INVOCATION payload construction asks for this map eagerly.

A possible change would use one fresh mutable, nonnull empty map only under
that existing exact guard. It must preserve repeated-access identity, mutation,
per-message independence and every unknown/custom/progress/cipher/keyid/flags
fallback. Both valid PPT key orders are accepted. Missing details bytes must
still yield null. Small copied metadata must not be replaced with views that
pin an entire native message. No ownership, GC, allocator, worker, SDK, body or
gate policy change is proposed.

This is a plan, not a patch or verified allocation/RSS reduction. A meaningful
before-failing witness must establish the unnecessary pending decoder work;
an assertion of an exact implementation class alone is insufficient. Full
mutation/identity/validation and lazy fallback controls remain necessary.
At planning time, no candidate-source reproduction, capture or numerical
campaign had run. Subsequent unit reproduction and alias falsification are
retained in the rejection above; no numerical campaign ran. Local model advice
was qualified against the actual source: the
no-bytes/null case is already a passing control, and key order alone does not
make an otherwise valid dictionary malformed.

The isolated `codex/flatbuffers-ppt-custom-detail-map` worktree started at
unchanged601 and is restored clean after rejecting the shortcut. Fresh baseline
preparation completed under the official exclusive lease: bootstrap,
`bin/test-fast` and full `bin/verify` passed before source edits. All three original
LOCAL locks remain unchanged; none is equated with the distinct hosted cohort.
The first runner incorrectly assumed ignored generated locks existed in the
fresh checkout. Its preflight failure preceded all commands and remains
retained. The corrected preparation initializes exact original frozen LOCAL
lock bytes and requires unchanged hashes after each standard command. It
copies no native binary or report and changes no source, SDK or runtime policy.

Initial free space8.38GB was below the chosen12GiB preparation floor. Under the
official exclusive lease,829 declared incremental compiler objects/depgraph/
query/workproduct cache files were removed only from inactive OWN predecessor
worktrees (11,507,457,811 logical bytes). Before/after protected source/HEAD/
native/RLIB/executable hashes match. Evidence, archives, frozen601 and other
tasks remain untouched. Observed free space after cleanup was19.69GB. No
model/test/source/native/HEAD mutation competed with the baseline. All sessions
are now reaped; no local workload is active.

Frozen601 and both completed failed campaigns remain unchanged. Any eventual
Dart change still needs actual two-Dart-broker fresh50-row controlled source
evidence with the same native/fresh client/all six locks, plus its own complete
canonical/copy/cleanCI and final strict48/50. Component decoder/allocation
evidence cannot establish transport/RAM repair or waive allocation precision.
