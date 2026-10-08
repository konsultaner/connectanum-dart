# Tokio-Rustls plaintext extraction observation

The transport workspace pins Tokio-Rustls 0.26.6 from its published crate
and observes the existing `Stream::poll_read()` copy after successful
`ReadBuf::put_slice(&data[..amount])`. The counter adds the actual selected
amount, excluding prefilled bytes and unused caller capacity. The buffered
TLS engine and ownership behavior remain unchanged.

The [pinned upstream implementation](https://github.com/rustls/tokio-rustls/blob/8aebb7c9556ea8024c1b974b84a4a6f2e306889a/src/common/mod.rs)
borrows Rustls's first plaintext chunk before copying it into the caller's
buffer. `AsyncBufRead::poll_fill_buf()` and `consume()` retain that storage;
tests check the same pointer and its offset after consumption, with zero
extraction copies. Copied reads count three bounded bytes, nine total bytes,
and six bytes after consuming four borrowed bytes. Empty reads, completed
EOF, pending reads and malformed input add no copied bytes.

The [source manifest](../../native/transport/vendor/tokio-rustls-source-manifest.json)
records all sixteen published files, the unchanged published lockfile,
four omitted upstream test utility/certificate fixtures restored from the
same commit, and the new observer module. Four upstream files change:
feature declaration, module export, copy hook and source tests. Original
Apache-2.0/MIT licenses, modification notice and manifest ship in native bundles.
All seven Tokio integrity controls and five existing Rustls controls pass.

Both macOS arm64 and Linux arm64 pass fourteen observer-enabled and eleven
observer-disabled unit cases. Linux matches all 3,017 frozen inputs and passes
the real native TLS client connection case. Each candidate production bundle
passes all thirty-four public profile cases in three separate Dart processes,
with nine license/notice/manifest files byte-identical to the source. These
local candidate packages have no hosted provenance claim. The Linux package
has `git_commit: unknown` because its frozen source checkout has no `.git`;
the separate digest inventory establishes its source identity.

The initial canonical fast run loads the candidate production library and
fails three ownership-oracle tests because production deliberately lacks test
symbols. The fast client function now explicitly builds `ffi-test`, matching
the full verification script. Three execution controls pass on macOS/Linux:
explicit/automatic production selection is replaced before oracle tests,
a failed build stops verification, and unsupported platforms retain the skip.
This change leaves other runtime helper callers intact. Its two final script
hashes supplement the earlier frozen source inventory.

Canonical fast verification passes before the added ABI gate. The first full
run terminates at exit 255 on Dart kernel-copy OS error 28 because the host disk
is full. Removing only rebuildable compiler/debug caches in this feature
worktree restores 21 GiB free; source, release libraries and proof artifacts
are retained. Final canonical `bin/test-fast` and `bin/verify` pass at exit 0 after cleanup,
including Rust/VM/consumers, 1,642 benchmark, 4,958 router, 4,751 core browser
and 2,829 client browser cases with 20 unchanged native-only skips. Initial local companion
attempts are lease-blocked; later test advice completes. Advice to retain a
production library for ownership oracles is rejected by the actual failures.
A larger final review reaches its token limit; the bounded retry completes
without an actionable finding. Its speculative cautions are disproved:
thread-local `with()` initializes before adding, successful Rust setup precedes
the build and the failure control exits 37, and `ct_core` explicitly enables
the observer. Exact log
digests and scoped results are in the [machine-readable proof](2026-10-07-tokio-rustls-extraction-proof.json).

This additional counter remains source-only. The six-field Rustls C ABI,
legacy transport snapshots and complete-copy benchmark gates are unchanged.
Growth, remaining record/crypto operations and other boundaries still prevent
complete TLS-copy certification. No performance or milestone acceptance follows.

The packaged-consumer audit now requires the existing 48-byte Rustls snapshot
export and calls it before this fresh process starts any TLS. It verifies
alignment, null rejection (-4), successful writes to all six initial counters,
and unchanged surrounding guards. Six controls reject a missing export, wrong
null status, failed/omitted writes and writes to either guard. All fourteen
verifier methods pass. The macOS candidate package passes this guard and all
thirty-four profile cases; bounded GLM review completes without a definite
error. Linux's additional probe remains live while Docker's API is unresponsive
following the disk-full event. All-platform acceptance is pending. This ABI
exercise measures no traffic copies and does not certify complete TLS coverage.
