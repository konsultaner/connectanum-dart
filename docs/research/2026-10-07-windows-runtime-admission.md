# Windows native runtime admission

The [native artifact dry run](https://github.com/konsultaner/connectanum-dart/actions/runs/37622772557)
for `4a7ac185` passes all four Linux/macOS platforms. The corrected Windows
launcher compiles hooks and starts the public tests. Its 48-byte Rustls ABI
check passes, but the first profile fails because `ct_start_runtime` reports
that the native runtime is unsupported. Windows selects the unsupported
platform stub before the existing Tokio runtime can start.

Windows now selects the shared supported platform handle alongside Linux and
macOS. That handle only admits the runtime; the networking, TLS and ownership
implementations are unchanged. The platform source is renamed from `linux.rs`
to `supported.rs`. Existing FFI runtime lifecycle tests also select Windows.
Other hosts retain the unsupported stub and an explicit rejection test.

The production consumer verifier now exercises the actual packaged C API:
start returns 0, duplicate start returns -2, shutdown returns 0, restart returns
0 and final shutdown returns 0. Five failure controls reject unsupported
start, failed restart, incorrect duplicate-start status and both shutdown
failures. All 20 verifier methods pass. The constructor, actual macOS FFI
lifecycle and unsupported stub tests pass. A fresh macOS production candidate
passes the new runtime audit, existing ABI guard and all 34 public profiles.
Its manifest names the base commit because the candidate was uncommitted;
source and artifact hashes preserve that distinction in the proof.

Bounded Qwen review completes; its claim that the current cfg excludes Windows
is rejected against the literal source. Bounded GLM review finds no definite
defect. Actual tests establish the local behavior. Hosted Windows acceptance
is pending and the five-platform, 34-profile gate remains unchanged.
Canonical candidate `bin/test-fast` and `bin/verify` pass at exit 0, including
Rust, VM, public consumers and both browser suites with 20 unchanged native-only
skips. The preceding `4a7ac185` PR coverage job separately fails one MCP last-owner
cleanup assertion: expected an empty subscription list, observed `[1]`. The
completed job log is retained; the cause and repair remain pending. Both remote
masters still point to `3bac4cf5`, already an ancestor of this feature branch.
No new master merge is needed. No release, benchmark or milestone acceptance follows.

[Machine-readable evidence](2026-10-07-windows-runtime-admission-proof.json)
retains the actual hosted failure, source digests and local production results.
