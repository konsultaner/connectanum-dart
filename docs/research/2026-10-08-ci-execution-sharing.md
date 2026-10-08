# CI execution sharing

Approved scope: a separate CI PR, preserving release PR #107 at `7ca882c6`.
Base: merged master `0e585405`. Branch: `codex/ci-execution-sharing`.

## Measured problem

Completed [run 37751253521](https://github.com/konsultaner/connectanum-dart/actions/runs/37751253521)
has 41 jobs: Fast Checks 22.4 minutes, WampApp 26.6, Full Verify 57.9,
VM coverage 48.5, browser coverage 18.6 and MCP mutation 181.4.
Full Verify starts after prerequisite jobs, approximately 27 minutes after
run start. Feature push plus PR events duplicate the entire workflow.
Named setup actions across 34 mutation jobs total 7.2 minutes; mutation
execution steps total 611.8, including internal bootstrap/cold compilation.
These are a historical baseline, not a measured improvement claim.

## Execution plan

1. Keep master push, master-targeted PR and manual runs; remove feature push
   duplication in CI and package dry runs. Preserve concurrency isolation.
2. Fast Checks runs formatting, analysis and tooling contracts. Full verification
   runs Rust and consumers, and collects VM coverage during the same complete
   VM suites. Browser coverage retains the full hosted JS browser inventory.
   Canonical local `bin/test-fast` and default `bin/verify` keep their contracts.
3. Cache public pub dependencies and version-checked native tools. Share only
   the same-run ffi-test library, verified against commit, native source hashes,
   Rust identity, target, feature, profile and binary digest. Production release
   artifacts remain independent.
4. Group small mutation targets by toolchain. Partition the complete MCP
   inventory deterministically into six balanced shards; regenerate the full
   inventory at aggregation, reject missing/duplicate/mismatched evidence, and
   apply the original 95% assertion gate to the complete union.
5. Preserve Fast Checks and Full Verify required status names. Full Verify
   explicitly rejects failed, skipped, cancelled or missing prerequisites,
   including all mutation and coverage jobs.
6. Execute tooling regressions, baseline `bin/test-fast`, canonical `bin/verify`,
   coverage execution controls, workflow lint, companion review when available,
   and hosted validation on a ready-for-review PR.

Native runtime/isolate boundaries, per-mutant deadlines, equivalence policy,
coverage scopes/floors and all platform release lanes remain mandatory.

## Primary references

[GitHub workflow events](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)
explain separate runs for separate triggering events.
[Dependency caching](https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching)
distinguishes cross-run dependency caches from same-run output artifacts.
[Cache action](https://github.com/actions/cache) documents key matching and
supported runner versions. [setup-dart](https://github.com/dart-lang/setup-dart)
documents explicit SDK selection.

## Verification

Fail-first partition and required-gate execution tests reproduce missing support.
Baseline `bin/test-fast` passes (exit 0). Local summary/test advice is blocked by the active
native mutation campaign resource lease, rather than inferred backend failure.

`bin/test-ci-fast` passes at exit 0, with formatting, analysis and all tooling
contracts. Focused script, runner and deployment-audit sets pass: 87, 93 and 28
methods respectively; the runner retains its one pre-existing platform/tool
skip. Eleven new execution contracts cover failure propagation, exact target
membership, disjoint/balanced partitions, complete union scoring, missing/stale/
corrupt evidence, baselines and native binary/build-input mismatch.

A fresh MCP list run generates all 1,101 mutants and resolves 23 complete test
files; shard counts are 184/184/184/183/183/183. This inventories MCP without
claiming an executed MCP score. A real six-shard Dart campaign on the complete
`core-scram-request-vm` inventory completes all 12 outcomes and clean/restored
baselines; independently regenerated aggregation passes its 100% assertion
score. Repeated final replay covers the command-identity comparison as well. The
aggregate retains every raw mutant log and all twelve shard baseline logs;
the existing independent kill-evidence auditor accepts its 12 outcomes, leaves
zero reclassified deadlines and preserves the passing gate.

A freshly built ffi-test library is recorded and revalidated with the actual
source, Rust/Cargo identity, resolved dependency lock, features/profile/flags and
binary hash. Reusing it passes 35 native owned-buffer/segmented-send cases;
JSON reporter evidence confirms 35 successes and zero skips. A
conditional-caller control verifies that failed artifact validation cannot be
swallowed by Bash's conditional `errexit` behavior.

Actionlint 1.7.12 (release archive checksum verified), shell syntax and
`git diff --check` pass. Local review and GLM judgment attempts are blocked by
the active native mutation campaign resource lease. Source review and executed
contracts provide the available local review evidence. Canonical `bin/verify`
passes at exit 0, including Rust, VM, consumers and Chrome/Dart2Wasm (4,751
core, 2,829 client; the same 20 native-only skips). Hosted full MCP/coverage
acceptance and measured CI timing remain pending. The new graph has 36 jobs
per workflow run, rather than 41 duplicated across PR and feature-push events. Debug build caches in this managed worktree are cleared with Cargo's
profile-specific clean command to recover disk space, retaining source, release
libraries and saved proofs.
