# Controlled source comparison workflow design

This is a diagnostic mode in the existing registered `mqtt-profile.yml`, not
`dart.yml` and not a new workflow filename. GitHub requires a manually dispatched
workflow to exist on the default branch; the CLI can select its branch using
`--ref`. This avoids merging diagnostic plumbing to master or repeating the
unchanged main MQTT gate.

Primary references:
- https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch
- https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow

Diagnostic inputs: source_baseline_ref (full7476SHA), source_candidate_ref
(full4ecSHA), source_locks_run (41316307118). Source comparison is mutually
exclusive with recover_run, probe_intel and compare_workers. Default profile
and Intel jobs skip source-comparison mode. Comparison dispatches get unique
run-id concurrency with cancellation disabled; ordinary mode remains unchanged.

Create detached baseline/candidate worktrees. Retrieve the declared candidate's
completed copy/lifetime artifact and verify its recorded head before extracting
the three canonical lockfiles; all duplicate retained lock copies must agree.
Copy exactly those locks to both source worktrees before bootstrap and verify
unchanged digests afterward. Retain locks, both source archives/digests, tool
revision, compiled client/brokers, native library/build logs and raw client rows.
No URI/package_config reuse across worktrees; bootstrap builds their own maps.

Use standard setup-ci (Dart3.13.1/Rust1.99.0). Verify identical complete native
source/build inputs and original client source. Build one standard release
ffi-test native library freshly with locked transport dependencies; both legs
load these same bytes. Compile each source's Dart broker once and one unchanged
candidate client. Use all original five profile budgets/five pairs with AB/BA
order as predeclared. Keep original delivery/body verification and broker
metrics; do not alter samples/windows/GC/allocator/SDK/body patterns.

Results are diagnosticOnly with all50rows retained; no gate passed field or
acceptance substitution. Source4ec CI failure remains retained. Do not claim
causal repair of old7763 failures from another host's success. Native-only
comparisons remain available separately for later genuine native changes.
