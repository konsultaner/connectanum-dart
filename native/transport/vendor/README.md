# Pinned TLS copy observations

The transport workspace patches Rustls **0.23.45** to the published crate in
`rustls/`. Its registry archive SHA-256 is
`0d41d731c7d2f962d1ccc364cec258de3c0e93b38c2fb3ba97ac74513048d634`.
The upstream repository is https://github.com/rustls/rustls, commit
`2976d90fd1c2db6b518700dd101b714069cfcb17`.

The original Apache-2.0, ISC and MIT license files are retained. The published
crate's 118 files are recorded in `rustls-source-manifest.json`, with both the
original and current SHA-256 values. Six existing files change: the optional
feature, public observer module, outbound record/chunk observations, deframer
observations, payload storage/encoding observations and queue read observations. `src/copy_observer.rs` is the only
new Rustls source module.

Upstream unit tests require omitted `rustls/src/testdata/`, sibling `test-ca/`
and `fuzz/corpus/message/`. These are restored unchanged from the same upstream
commit and hashed in the manifest. Certificate private keys are public upstream
test fixtures. They are not deployment credentials.

Run `python3 tool/check_rustls_source.py` from the repository root to verify all
841 source and fixture files. The test build's generated `Cargo.lock` and
`target/` are excluded. When updating the dependency or observer, review the
upstream changes and the exact instrumentation diff before refreshing digests.

`connectanum-copy-observer` is disabled by default upstream and enabled by
`ct_core`. Its counters measure only named actual byte-copy sites, process-wide.
The six fields cover outbound chunks, queue reads, deframer appends/moves,
record/payload clones, borrowed ownership conversion and record/payload/certificate
content appends.
Record clones include the five-byte prefix; plaintext conversion excludes it.
Moving an owned record/payload buffer and cloning a borrowed reference add no
copy. U24 wrapper clones delegate to their inner payload and count once.
Length-prefixed U8/U16 reads count only successful content copies.
They exclude buffer growth, generated length prefixes, initial header initialization, remaining record
and crypto operations. These Rustls observations cannot certify total TLS copies.
Existing total-copy benchmark gates remain unmeasured until their full scope
is observed. The separate native benchmark orchestrator retains its registry
Rustls dependency; it does not consume these transport counters.

The canonical full test script runs all 232 upstream Ring/std/TLS 1.2
library tests and eleven observer tests with the observer enabled. The source checker runs in both fast
and full verification. No protocol, cipher, allocation or buffer ownership
behavior is changed by the observer hooks.

The transport workspace also pins Tokio-Rustls **0.26.6** in `tokio-rustls/`.
Its published archive SHA-256 is
`c9cc2678c2cdd569ef8215e2afd7954ada2ae20b4fdd2c5fe6139a3b02d105db`,
from https://github.com/rustls/tokio-rustls at commit
`8aebb7c9556ea8024c1b974b84a4a6f2e306889a`. Apache-2.0 and MIT licenses
are retained. `tokio-rustls-source-manifest.json` records all 16 published
files, four restored unchanged upstream test utility/certificate fixtures,
and the new observer module. The published `Cargo.lock` is audited unchanged;
only generated `target/` contents are excluded. Test keys are public upstream
fixtures. The source checker verifies both packages.

Four upstream files change: the optional feature, observer module export,
the extraction hook and source tests. The observer counts `amount` immediately
after the existing successful `ReadBuf::put_slice()` in `Stream::poll_read()`.
It excludes the borrowed `Reader::into_first_chunk()` path, `AsyncBufRead`
views and consumption, buffer growth, and crypto. Tests verify bounded/prefilled
reads, pointer preservation after borrowed consumption, zero-length/EOF reads,
pending reads and malformed TLS input. All eleven upstream and three observer
tests run in canonical full verification. This additional partial observation
does not change the six-field Rustls ABI or certify total TLS-copy coverage.
Both packages' licenses, notices and source manifests ship in native bundles.
