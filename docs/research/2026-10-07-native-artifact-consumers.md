# Packaged production runtime consumers

The Native Artifacts workflow now runs the public FlatBuffers client and router
profiles on each of its five host runners before signing/attesting a successful
bundle. It installs Dart, fetches the workspace dependencies with the existing
skip-native-build hooks, and checks the archive made by the same job.

The checker verifies the archive checksum/name and expected source commit,
requires the detached and embedded manifests to agree, and extracts only one
regular library file into a unique directory. It loads that library, checks the
legacy/V2 transport metrics ABI, and rejects all 18 current test-oracle exports
inventoried from source. Explicit native-library and skip-build settings select
this extracted production binary for every Dart process.

Three separate invocations run the native client (10 cases), Dart transport
profile (22 cases) and native router (2 cases). Separate processes preserve the
native runtime lifecycle. JSON evidence must contain exactly the expected
public completions, matching start/completion IDs, no errors/skips/failures and
one successful terminal event. Hidden loader failures still fail the gate.
Library hashes must remain stable. Logs and the failure/success proof upload as
`native-consumers-<host-triple>` and never become release assets.

Nine failure controls pass on macOS and Linux: changed archive, wrong source,
divergent embedded manifest, library symlink, space-containing paths, hidden
loader accounting, skipped/omitted/unfinished tests and late errors. Actionlint
passes. The actual gate passes all 34 cases against each published `cde9fbed`
macOS arm64 and Linux arm64 production bundle. This verifies the new runner
against those frozen libraries; it is not a resulting-source five-platform run.
See [scoped proof](2026-10-07-native-artifact-consumers-proof.json). Published command paths are normalized to `dart`; the exact raw report digest
retains provenance without embedding a local SDK directory.

The first companion test request reaches its token limit; a narrowed retry
completes. Its useful suggestions are checksum/source and skip/unfinished
controls. Completed review findings are independently checked: an actual
subprocess timeout proves stdout/output aliasing and byte decoding, all hidden
and public results are checked, and test paths are fixed safe constants. No
confirmed defect follows from the speculative review. Windows executable/path
behavior remains subject to the hosted Windows gate.

Canonical candidate `bin/test-fast` passes at exit 0, including all 1,616
benchmark cases and public consumer smokes. Application/native source remains
unchanged from the `0ce3c364` full-verification checkpoint; candidate full
entrypoint/workflow full verification now passes together with the metrics bridge
(1,642 benchmark, 4,958 router, 4,751 core browser, 2,829 client browser and
20 unchanged native-only skips). All-five hosted runtime acceptance remains pending. No release, performance, total TLS/crypto-copy or
milestone acceptance follows from these scoped consumer checks.
