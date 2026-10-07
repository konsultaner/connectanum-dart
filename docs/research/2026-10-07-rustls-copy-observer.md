# Source-observed Rustls copies

The transport pins Rustls 0.23.45, registry archive SHA-256
`0d41d731c7d2f962d1ccc364cec258de3c0e93b38c2fb3ba97ac74513048d634`,
upstream [commit 2976d90f](https://github.com/rustls/rustls/tree/2976d90fd1c2db6b518700dd101b714069cfcb17).
The archive digest is verified against the local registry cache. Its 118
published files are hashed before edits; four existing files change and one
observer module is added. The original Apache-2.0, ISC and MIT licenses remain.
Upstream unit fixtures omitted from the published crate are restored unchanged
from that commit: 51 testdata, 169 test-ca and 502 message corpus files. The
841-file source manifest records original and current hashes. The source gate
rejects changed, missing, added and symlink-substituted files.

A bounded GLM architecture judgment recommends feature-gated observations
while preserving the buffered TLS engine. A replacement unbuffered async record
engine would change handshake/read/EOF behavior across shipped transports.
The advice is checked against the pinned source. No full TLS-copy claim follows.

## What the observations cover

`OutboundChunks::copy_to_vec` records each actual appended source range after
`extend_from_slice`. `ChunkVecBuffer::read` and its alternative `read_buf` record
the bytes copied into the destination. `to_vec` and `append_limited_copy` do not
also increment counters, avoiding double counting. An empty copy adds zero.
The public snapshot is process-wide, cumulative and uses relaxed atomics;
concurrent connections contribute. It is neither per-session accounting nor
an atomic snapshot across both counters. Test-local observations provide exact
expectations without attributing other threads' traffic to the fixture.

`ct_core` enables the optional feature and exposes the partial snapshot.
The old transport snapshot structs and C/Dart ABI are unchanged. Benchmark
whole-TLS fields remain unmeasured. Accepted plaintext is input volume and
is never substituted for measured copies.

## Reproductions and checks

Initial compile failures identify omitted upstream fixtures and no-std test
imports; these setup failures are not behavior evidence. With fixtures restored,
two tests compile and fail at `(0, 0)` instead of `(5, 5)` and `(6, 0)`, while
verifying the exact copied payloads. Source observations make both pass.
All 234 Ring/std/TLS 1.2 library cases (232 upstream and two observer cases)
then pass. The feature-disabled build passes. Linux arm64 passes all 235 library cases
(the additional case is upstream `test_env_var_cannot_be_written`) and the
same real native TLS test, with all 859 frozen overlay inputs matched. The
Linux compiler emits three existing `fetch_update` deprecation warnings outside
the changed observer code.

The existing real native TLS RawSocket/file-send test verifies both receipt of
the full message and an increase in observed outbound chunk copies. An initial
assertion expecting receive queue observations fails. Source inspection explains
why: Tokio-Rustls 0.26.6 uses `Reader::into_first_chunk()` and
`ReadBuf::put_slice()` instead of the instrumented `ChunkVecBuffer::read`.
The test asserts the actual outbound observation; it does not mislabel the
unobserved receive path as measured. No existing acceptance assertion is relaxed.

The transport lock changes only the same-version Rustls source from registry to
the pinned path. Native benchmark Rustls remains registry-resolved. The source
gate and its five failure controls are integrated into fast/full checks, and
full checks run the upstream Rustls library tests.
Fresh `bin/test-fast` passes at exit 0. Five source-gate controls pass, as does
a Git filter control showing all 841 source blobs remain identical with
`core.autocrlf=true`. Vendored files use `-text` attributes. Native artifact
packaging validates the source and includes original licenses, the modification
notice and source manifest. The broad final GLM request times out; a smaller native patch judgment completes
with no confirmed defect after retracting speculative concerns. Direct source
inspection confirms post-copy counting and unchanged buffer progress. Full
`bin/verify` fails the unchanged FastCGI cumulative stdout-limit fixture
with a peer reset. The isolated unchanged repro and five separate unchanged
runs pass. Assertions and timeouts are unchanged. Fresh full `bin/verify`
passes at exit 0: Rust/VM/consumers, 1,616 benchmark, 4,958 router, 4,751 core
browser and 2,829 client browser cases, with 20 unchanged native-only skips.
Real macOS arm64 artifact packaging passes: all five Rustls notice/manifest
files match, archive checksum verifies, both old/V2 transport snapshots remain
exported and test oracles are absent. Its manifest names base `04757fda` while
built from the uncommitted source candidate; scoped source hashes accompany this
local packaging check. It is not resulting-head or multi-platform release
acceptance. No release is published.
No release, tag, version bump, issue closure or performance acceptance follows.

## Required remaining coverage

Buffer growth, record assembly, deframer movement, crypto-wrapper copies and
Tokio-Rustls plaintext extraction are still outside these two observations.
The native and Dart SDK TLS gates stay incomplete until their full scope is
observed. Mixed-serializer transformation and whole-crypto accounting remain
separate required gaps. A numeric partial snapshot cannot satisfy the existing
whole-transport copy gates or the unchanged CBOR/MessagePack parity budgets.

## Audited next copy sites

A bounded Gemma summary helps select these sites; direct source inspection
also finds the payload `to_vec` and derived Vec clone that the summary omits.
These are audit leads, not additional measured coverage.

| Site | Operation and remaining boundary |
| --- | --- |
| `DeframerVecBuffer::discard` | Moves pending bytes with `copy_within`; a zero shift is a no-op and must not be reported as traffic. |
| `DeframerVecBuffer::extend` | Copies incoming bytes with `copy_from_slice`; preceding capacity growth remains a separate boundary. |
| `OutboundOpaqueMessage::into_plain_message` | Allocates and copies the payload through `to_vec`; audit real-path reachability. |
| `PrefixedPayload` | Slice appends and derived Vec clones remain unobserved; distinguish copied bytes from generated record metadata and crypto output. |
| `Tokio-Rustls Stream::poll_read` | `ReadBuf::put_slice` copies `amount` plaintext bytes after borrowing `Reader::into_first_chunk`. |

TLS 1.3 Ring `extend_from_chunks` reaches the existing outbound observation;
adding another observation at that wrapper would double-count the same copy.
`seal_in_place_append_tag` transforms data in place and produces authentication
bytes; output length alone is not evidence of another payload copy.
