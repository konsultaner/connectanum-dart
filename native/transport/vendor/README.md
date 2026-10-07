# Pinned Rustls copy observations

The transport workspace patches Rustls **0.23.45** to the published crate in
`rustls/`. Its registry archive SHA-256 is
`0d41d731c7d2f962d1ccc364cec258de3c0e93b38c2fb3ba97ac74513048d634`.
The upstream repository is https://github.com/rustls/rustls, commit
`2976d90fd1c2db6b518700dd101b714069cfcb17`.

The original Apache-2.0, ISC and MIT license files are retained. The published
crate's 118 files are recorded in `rustls-source-manifest.json`, with both the
original and current SHA-256 values. Four existing files change: the optional
feature, public observer module, outbound append observations and queue read
observations. `src/copy_observer.rs` is the only new Rustls source module.

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
They exclude buffer growth, other record/deframer/crypto operations and copies
in Tokio-Rustls. In particular, Tokio-Rustls receives plaintext through
`Reader::into_first_chunk()` followed by `ReadBuf::put_slice()`, bypassing the
instrumented queue read. These observations cannot certify total TLS copies.
Existing total-copy benchmark gates remain unmeasured until their full scope
is observed. The separate native benchmark orchestrator retains its registry
Rustls dependency; it does not consume these transport counters.

The canonical full test script runs all 232 upstream Ring/std/TLS 1.2
library tests and two observer tests with the observer enabled. The source checker runs in both fast
and full verification. No protocol, cipher, allocation or buffer ownership
behavior is changed by the observer hooks.
