# Windows packaged consumer launcher

The [native dry run](https://github.com/konsultaner/connectanum-dart/actions/runs/37614965856)
for source `2bfff943` finishes with four successful Linux/macOS platforms and
one Windows failure. Each successful platform runs all 34 public profile
cases and verifies that the packaged library excludes 18 test oracles.
Windows fails before any profile case runs: the first Dart process exits 65,
with hook compilation attempting `dart.EXE.exe`. The uploaded failure proof
retains its archive/library hashes and first process log.

The Python launcher receives `dart.EXE` from `shutil.which("dart")`. Its old
Windows normalization handles only `.bat` and `.cmd`, leaving that uppercase
suffix unchanged. An execution control calls the actual consumer entry point
and confirms the uppercase path reaches every child process. Two fail-first
cases expose uppercase propagation and failure to reject a missing executable.

The correction normalizes `.exe`, including uppercase PATHEXT results, along
with shell wrappers to lowercase `.exe`, then requires that file to exist.
POSIX paths are unchanged. Three added execution methods cover uppercase and
lowercase executables, both wrappers, path spaces, missing executables and
all three profile commands. All 17 verifier methods pass; bounded local review
completes without a definite error. Earlier review reaches its token limit and
is not used. Local companion advice to preserve uppercase `.EXE` is rejected
by the actual hosted failure. The SDK version and profile gate are unchanged.

The preceding source checkpoint `736b6454` passes canonical fast and full
verification. The corrected consumer also passes the 48-byte ABI guard and all 34 public
profile cases against the macOS production candidate. Canonical `bin/test-fast` and `bin/verify` pass at exit 0 after the launcher
correction, including Rust/VM/public consumers, 1,642 benchmark, 4,958 router,
4,751 core browser and 2,829 client browser cases with 20 unchanged native-only
skips. New hosted Windows runtime proof is pending. Local mock execution cannot establish
Windows runtime acceptance. The [machine-readable proof](2026-10-07-windows-consumer-launcher-proof.json)
retains failure and regression log digests. No release or milestone acceptance
follows from these checks.
