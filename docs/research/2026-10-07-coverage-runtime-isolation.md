# Isolate remote-authentication runtime ownership in coverage

The `4a7ac185` [PR coverage job](https://github.com/konsultaner/connectanum-dart/actions/runs/37622673258/job/112825887695)
fails one MCP last-owner cleanup assertion: expected an empty WAMP subscription
list, observed `[1]`. All four related isolated macOS coverage cases pass.
The specific Linux assertion's cause is not established.

A focused actual coverage run combines those four MCP cases with the thirteen
remote-authentication cases in two test isolates. It fails runtime admission
with `runtime already started`, then aborts the VM at exit 134 with
`Cannot invoke native callback from a different isolate.` Remote-authentication
starts and shuts down its own process-wide native runtime. The normal regression
runner has isolated this file since `70dc5f83`; the coverage runner omitted that
isolation and selected the file in the shared router process.

Coverage now excludes the tagged remote-authentication file from that shared
process, then executes the complete file in a separate Dart process. Its raw
reports use `connectanum_router_remote_auth`; the existing formatter still reads
the entire raw root for library and packaging reports. Every test and coverage
denominator remains required. No production code or MCP assertion changes.

An execution regression uses the actual coverage launcher and observes separate
process IDs, complete test selection, distinct raw reports and the package
working directory. Failure controls preserve both shared and isolated process
exit codes. The old launcher fails those controls at exit 79 because it mixes
the runtime owners; the corrected launcher passes both methods. All 85 script
regression methods pass. The four MCP and thirteen remote-authentication cases
pass in separate actual coverage processes. Bounded local review finds no
concrete defect; speculative output-path and environment concerns are checked
against literal sequential execution, separate report labels and subshells.
Canonical candidate `bin/test-fast` and `bin/verify` both pass at exit 0,
including Rust, VM, public consumers and both browser suites with the same
20 native-only skips. The `df1a9ad5` native run passes all five consumer gates (170 cases),
then fails macOS Intel archive attestation persistence. Failed-job rerun requests
return HTTP 500. Sampled hosted PR jobs also fail without acquiring a runner;
their steps are empty and the annotation reports five acquisition failures.
Companion attestation triage is resource-lease blocked and no bypass is attempted.
No overall native or hosted CI acceptance follows. Hosted CI acceptance and
the original Linux subscription assertion require fresh evidence.

[Machine-readable proof](2026-10-07-coverage-runtime-isolation-proof.json)
retains failure and success digests without weakening the coverage policy.
