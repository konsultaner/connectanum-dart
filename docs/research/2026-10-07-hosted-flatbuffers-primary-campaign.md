# Hosted full FlatBuffers campaign

The existing WAMP Profile Benchmarks workflow gains an explicit
`flatbuffers_primary` manual choice. Pushes and the default `profiles` choice
retain the canonical profile job. The primary job uses an Ubuntu 24.04 hosted
runner, Dart 3.13.5 and Rust 1.99.0. A repository-wide concurrency group queues
additional primary runs without cancelling a running campaign.

The current implementation and local checks do not establish hosted completion
or performance acceptance. Issues #100–#104 and the milestone remain open.
The 1,440 rows cover the primary 64 KiB typed RPC/pub-sub matrix. The original
small/large payload, fan-out, progressive, control and mixed-serializer
performance scope also remains required; this job does not replace it.

The resource policy already declares CPU/allocation/GC/RSS point ratios at most
1.0 and confidence upper bounds at most 1.05 against the better binary baseline.
Contradictory documentation calling those budgets undeclared is corrected; no
machine-readable threshold, metric, scope or acceptance criterion changes.

## Full scope and failure behavior

The job runs the existing primary executor without diagnostic or case-selection
flags: 48 cases, three codecs, three warm-up passes and seven measured passes,
10 seconds and at least 1,000 samples per row. That is 1,440 rows, whose minimum
measurement time alone is four hours. Its 330-minute executor deadline sits
inside a 360-minute job budget, leaving time for setup and artifact upload.
Timeout or incomplete rows stay failed evidence; no smaller matrix substitutes
for the primary campaign.

Dependency resolution and both locked release builds finish before measurement.
The archived production `ct_ffi` library is checked for absence of `ct_test_`
oracles, then supplied with the archived driver to the executor. Host image
version, CPU details, toolchains, resolved dependency locks, binary checksums,
source revision, policy, generated scenarios, raw rows and logs are retained.
The executor still rejects dirty source, changed policy, overlapping build/test
jobs, restarted workers and missing active copy measurements.

The artifact upload and bounded summary run after failure. The summary displays
at most twenty findings and links the reader to the complete retained reports;
it does not truncate the stored comparison. Setup failures and incomplete
campaigns explicitly report that acceptance remains unproven.

## Usage

After the feature commit is published, dispatch the already-registered workflow
on that exact branch or revision:

```sh
gh workflow run wamp-profile-benchmarks.yml \
  --repo konsultaner/connectanum-dart \
  --ref codex/flatbuffers-zero-copy \
  -f campaign=flatbuffers_primary
```

No release, tag or package publication is performed by this workflow.
GitHub permits manual dispatch on another ref using `--ref`, while requiring
the workflow to exist on the default branch. Reusing the registered profile
workflow avoids introducing an undispatchable feature-only workflow. See
[manual workflow dispatch](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
and [job timeout syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idtimeout-minutes).

## Local evidence and limits

The campaign/comparator suite passes 38 tests, including reduced policy floors,
subset selection, non-Linux/dirty-source/changed-policy refusal, full 1,440-row
preparation and a real sleeping descendant stopped by the deadline. Actionlint
1.7.12 passes after verifying its downloaded archive checksum; all extracted
shell blocks pass `bash -n`. Four synthetic summary fixtures cover setup
failure, 124 incomplete rows, failed comparison and passed comparison. These
fixtures establish summary behavior, not measurement evidence.

Qwen test advice included useful scope/deadline/environment cases. Its proposal
to launch a primary job on a push contradicted the explicit manual choice;
adding `--diagnostic` to rejection cases would waive the guards under test;
mocking `execute` to sleep would bypass the actual deadline; a marker under
`/tmp` would not dirty Git. Those suggestions were rejected. The retained tests
exercise the actual non-diagnostic CLI and real process-group deadline.

A clean published `0ec8df06` snapshot also passes real Linux prepare-only
preflight: 48 cases, 1,440 planned rows, exact policy hash and resolved locks.
It reuses the archived `8af2c337` production driver/library solely to validate
preparation; no workload or new artifact consumer runs. Native/benchmark Rust
source is unchanged between those revisions. This is preflight evidence, not
a hosted workflow execution or performance result.

The published-head native dry run `37565137233` passes all five builds and its
preview. Fifteen exact-source/workflow attestations, thirty assets and exact
rendered notes verify. Fresh attested Apple Silicon and Linux arm64 libraries
pass 32 focused profile tests each with no skips or test-oracle exports. The
Linux library also passes 20 live worker tests, including per-owner submission
observations. Other platforms have build/provenance evidence only. This checkpoint does not prove
current-head CI completion or full performance acceptance.

Final companion review was blocked by the active native mutation resource
lease. Direct workflow/source inspection and linting completed. Baseline `bin/test-fast` and full `bin/verify` pass at exit 0, including
1,609 benchmark, 4,958 router, 4,751 core browser and 2,829 client browser
cases with the unchanged 20 native-only skips. Full log and exit evidence are
`/tmp/connectanum-hosted-primary-verify.{log,exit}`. Resulting-head hosted
execution remains pending.
