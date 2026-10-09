# Deframer and record copy observations

This follow-up to [the pinned Rustls observer](2026-10-07-rustls-copy-observer.md)
adds observations at actual copy sites while preserving the existing buffered
TLS engine. It extends the Rust-only partial snapshot; C and Dart snapshot ABIs
are unchanged. No total-copy or benchmark acceptance follows.

The observer remains optional upstream and enabled by `ct_core`. Five existing
upstream files now differ from Rustls 0.23.45; original hashes and all 841 source
and fixture entries remain in the source manifest. The three original licenses
are retained.

## Named sites

| Counter | Operation observed | Exclusions |
| --- | --- | --- |
| `deframer_append_copy_bytes` | `DeframerVecBuffer::extend` copies incoming slices. | Capacity growth and `read` into the destination buffer. |
| `deframer_move_copy_bytes` | Pending-byte compaction and coalescer `copy_within`. | Zero shifts, empty ranges and growth. |
| `record_buffer_copy_bytes` | Prefixed record Vec clones and plaintext conversion via `to_vec`. | Moving the owned buffer during encode. Clones include the five-byte prefix; plaintext conversion excludes it. |
| `record_append_copy_bytes` | Record slice/iterator appends and construction from content. | Initial header initialization, capacity growth and chunk appends already counted by the outbound counter. |

The original outbound-chunk and queue-read counters remain separate. Each hook
runs after its operation succeeds. Snapshots are cumulative and process-wide;
relaxed field loads do not provide an atomic snapshot across counters. Exact
source tests use thread-local observations to exclude concurrent traffic.
The feature-disabled `PrefixedPayload` retains its derived Clone; the enabled
implementation clones its Vec once and then records its actual length.

## Reproduction and verification

Two deframer tests first fail with zero observations while verifying their
payloads: ten appended bytes, nine compacted bytes and six overlapping
coalescer bytes are omitted. Two record tests then fail despite a nine-byte
prefixed clone, four construction bytes and three subsequent slice/iterator
bytes. Adding the hooks makes all four pass. Encode retains the original
payload address; chunk appends are not counted twice.

All 238 macOS library tests pass with observations enabled, and all 232 upstream
tests pass with them disabled. Linux arm64 passes 239 enabled and 233 disabled
cases; the additional case is the existing Linux-only key-log permission test.
All 860 frozen source/lock inputs match before the Linux checks. Source-integrity
verification and its five failure controls pass. The real native TLS test passes
on both platforms, verifying the received payload and outbound/record-append
observations.

An initial new live deframer-append assertion fails. Source inspection shows
that buffered `read_tls` reads directly into deframer storage and bypasses
`extend`; it is not evidence of a slice append. The invalid new assertion is
removed. Existing payload and outbound assertions remain, and the new record
append assertion passes. Accepted input bytes are not substituted for copy
observations.

A completed focused Qwen hook review finds no concrete defect; it reiterates
partial accounting and speculates about Clone divergence. Direct inspection
and both enabled/disabled suites confirm the single Vec clone and unchanged
payload behavior. The broader prior review timed out and is not counted as a
completed review. An additional snapshot review is initially blocked by the
active native-mutation resource lease, then completes after verification. Its
local/global snapshot concern does not apply: exact source tests assert the
local tuple, while the live native test checks the global snapshot. The code
does not claim exhaustive coverage; all six atomic/local index pairs are
checked directly.

Canonical `bin/test-fast` and full `bin/verify` pass for this follow-up at
exit 0, including 1,616 benchmark, 4,958 router, 4,751 core browser and 2,829
client browser cases, with 20 unchanged native-only skips.
See [scoped check evidence](2026-10-07-rustls-deframer-record-copies-proof.json). The
[published primary campaign](https://github.com/konsultaner/connectanum-dart/actions/runs/37582544124)
uses frozen `a5c6aaf9` source and remains separate evidence. Native artifact and
package dry runs at that source complete successfully; no real release occurs.

## Clean-checkout CI repair

Both `a5c6aaf9` hosted fast jobs fail the campaign preparation unit test because
`native/bench/Cargo.lock` has not been generated. A temporary source root with
no generated locks reproduces the failure locally. The fixture now owns three
synthetic lockfiles, checks their archived bytes and hashes, and retains all
48 cases, three warmups, seven measured repetitions, 1,440 rows, 10-second
minimum duration and 1,000-operation minimum. All 15 campaign tests pass on
macOS and Linux. No runner policy or production lockfile requirement changes.
Completed Qwen advice is checked against the actual Path-based hash helper and
temporary-root lifecycle; its suggested path and cleanup defects do not apply.

## Published artifact checks and newline repair

The `a5c6aaf9` native dry run produces all five platform archives. Their
manifests and checksums match; all fifteen attestations verify with the source
digest, source branch, signer workflow and hosted-runner restriction pinned.
All thirty preview assets are listed, and release notes reproduce byte for
byte when the exact workflow reference is supplied. An initial local render
uses only the branch as its workflow reference and differs in the certificate
identity; correcting that invocation matches the unchanged renderer output.
The macOS production library excludes test oracles and retains both old and V2
snapshot symbols. All 34 production profile cases pass in isolated processes
on each of macOS arm64 and Linux arm64 using these hosted libraries. The other
three platforms have build and provenance evidence. See
[published artifact proof](2026-10-07-a5-native-artifact-proof.json).

Twenty-three notice/manifest files match their source bytes. The Windows
notice and source manifest differ only by CRLF conversion. This actual bundle
reproduces byte drift; a local `core.autocrlf=true` filter control fails for
both files before adding `-text` attributes. These attributes complement the
existing protections for the 841 crate/fixture files. All 843 current
source/fixture/notice/manifest blobs remain exact with `core.autocrlf=true`.
Resulting-source hosted Windows packaging remains separate evidence from
this published dry run.

## Remaining coverage

Growth, initial header initialization, remaining record/crypto operations,
Tokio-Rustls plaintext extraction and Dart SDK TLS are still outside complete
copy coverage. Mixed-serializer transformations and whole-crypto accounting
remain required. The full primary campaign and original supplemental scope
must meet unchanged parity and resource budgets. Issues #100–#104 remain open.
