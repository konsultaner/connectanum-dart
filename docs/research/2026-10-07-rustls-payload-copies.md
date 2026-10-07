# Payload copy observations

The pinned Rustls observer now covers actual owned payload clones, borrowed
ownership conversion, bounded U8/U16 reads and payload/certificate content
appends. It reuses the existing record-buffer and record-append counters; no
Rust snapshot field or C/Dart ABI is added. The buffered TLS engine and buffer
ownership behavior remain unchanged. These observations remain partial.

Six existing upstream files now differ from Rustls 0.23.45. The source manifest
preserves original hashes for all 841 crate/fixture entries and records the new
`msgs/base.rs` instrumentation. The original licenses remain unchanged.

## Copy and ownership boundaries

| Operation | Observation |
| --- | --- |
| `Payload::clone` on Borrowed | Retains the source address and copies zero bytes. |
| `Payload::clone` on Owned | Copies the Vec contents once into another allocation. |
| Borrowed `into_vec`/`into_owned` | Copies the selected slice once; the wrapper does not count it again. |
| Owned `into_vec`/`into_owned` | Moves the allocation and retains its address. |
| U24 wrapper clone | Delegates to its inner Payload; an owned clone counts once and a borrowed clone counts zero. |
| U8/U16 read | Counts the content `to_vec` only after cardinality and bounded-reader validation succeeds. |
| U8/U16 clone | Clones the Vec once; the existing Cardinality trait already requires Clone. |
| Payload/U8/U16/U24/certificate encoding | Counts appended content, excluding generated length prefixes and capacity growth. |

Each hook follows the actual operation. The feature-disabled build retains
upstream derived Clone implementations. The enabled implementation preserves
the same borrowed/owned variants and generic trait bounds. There is no extra
clone hook on the U24 wrapper.

## Reproductions and checks

The first setup attempt needs an explicit U24 default type annotation; this
compile error is not behavior evidence. After repairing the test setup, two
tests fail with zero observations instead of seven copied-buffer bytes and
eight appended-content bytes, after verifying payloads and allocation identity.
Two further tests fail at ten copied-buffer bytes and nine appended-content
bytes for prefixed reads/clones and certificate/payload encodes. Hooks make all
four pass. A separate targeted test proves that a borrowed read retains its
address and a U24 owned clone counts exactly once.

All 243 macOS enabled cases and 232 feature-disabled cases pass. Linux arm64
passes 244 enabled and 233 disabled cases; its additional case is the existing
key-log permission test. All 860 frozen source/lock inputs match. The source
checker and five failure controls pass. Both platforms pass the real native
TLS payload/outbound/record-append test.

A focused Qwen review proposes adding hooks to U24 clones and Payload reads.
Source inspection and the targeted regression disprove both proposals: the
wrapper delegates to the observed inner clone, and `Payload::read` returns a
borrowed slice. Adding those hooks would report a borrow as a copy or count an
owned clone twice. The initial follow-up is blocked by an active native-mutation resource lease.
A post-verification retry completes and confirms those clone/borrow semantics;
its speculative comments about pre-existing maximum lengths and Debug formatting
do not identify a defect introduced by the observer patch. Reader bounds and
exact byte/pointer assertions remain independently verified. Initial Qwen test
advice confuses copies with allocation events; exact source and byte/pointer
checks determine the assertions.

Canonical `bin/test-fast` and full `bin/verify` pass at exit 0 for this follow-up,
including Rust/VM/consumer checks, 1,616 benchmark, 4,958 router, 4,751 core
browser and 2,829 client browser cases with 20 unchanged native-only skips.
See [scoped payload proof](2026-10-07-rustls-payload-copies-proof.json). Whole
TLS/SDK, remaining record/crypto/growth boundaries, mixed serializers, whole
crypto, full primary parity and original supplemental acceptance remain open.
No performance or complete-copy claim follows.

## Published CDE artifact checkpoint

Native dry run [37588514671](https://github.com/konsultaner/connectanum-dart/actions/runs/37588514671)
completes all five builds at frozen `cde9fbed`. All fifteen attestations verify
with exact source, branch and signer workflow pins. All twenty-five bundled
notices/source manifests now match source bytes, including Windows; the
previous CRLF difference is repaired. All thirty preview assets match, and the
release-note renderer reproduces the preview byte for byte. No release is
published. This evidence is separate from the uncommitted payload observer.
All 34 production profile cases pass in separate processes on each hosted
macOS arm64 and Linux arm64 library. Both exclude test oracles and retain the
old/V2 ABI. Other platforms have build/provenance evidence, which does not
establish runtime acceptance. See [published artifact proof](2026-10-07-cde-native-artifact-proof.json). The independent 1,440-row campaign remains on its frozen
`a5c6aaf9` source and unchanged policy.
