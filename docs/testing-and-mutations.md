# Regression And Mutation Testing

The project target is at least 98% executable-line coverage per shipped
component/runtime and at least 95% killed viable, non-equivalent mutations.
**These targets have not been reached repository-wide.** A passing CI job means
that its named scope and current regression floors passed, not that the complete
project has 98% coverage or 95% mutation coverage.

## Commands

Run `bin/test-fast` before substantial changes and `bin/verify` before handoff.
Both include regression tests for the coverage and mutation tooling.
Do not overlap full native verification and VM coverage collection on the same
host: the native test runtime uses a shared lock with a bounded admission wait.

```sh
dart pub global activate coverage 1.15.1
CONNECTANUM_COVERAGE_DIR=out/coverage-vm bin/test-coverage
CONNECTANUM_BROWSER_COVERAGE_DIR=out/coverage-chrome bin/test-browser-coverage

bin/test-mutations --target router-authorization --output out/mutations-authz
bin/test-mutations --target auth-server --output out/mutations-auth
bin/test-mutations --target core-base64-vm --output out/mutations-base64-vm
bin/test-mutations --target core-base64-web --output out/mutations-base64-web
bin/test-mutations --target core-msgpack-vm --output out/mutations-msgpack-vm
bin/test-mutations --target core-msgpack-web --output out/mutations-msgpack-web
bin/test-mutations --target mcp --output out/mutations-mcp

rustup component add llvm-tools-preview
cargo install cargo-llvm-cov --version 0.9.1 --locked
CONNECTANUM_NATIVE_COVERAGE_DIR=out/coverage-rust bin/test-native-coverage
cargo install cargo-mutants --version 27.1.0 --locked
bin/test-native-mutations --package ct_core --file rawsocket.rs \
  --timeout 20 --build-timeout 300 --output "$PWD/out/mutations-rawsocket" \
  -- --lib rawsocket::tests
```

Use fresh output directories. Browser mutation tests require Chrome. The browser
coverage command currently measures the core serializer suites and SCRAM Worker,
not the complete client application or every browser implementation. The
[Dart test runner](https://github.com/dart-lang/test/blob/master/pkgs/test/README.md)
supports Chrome coverage; source-mapped browser results are kept separate from
the VM badge. Isolate-only tests remain explicitly VM-only.

## Interpret Evidence

`summary.json` records per-file/package numerator and denominator, missing lines,
unmeasured library sources and unmeasured runtimes. Missing files are not 100%.
Export-only libraries and platform-specific implementations need separate
classification, not blanket exclusion. `tool/coverage_policy.json` and
`tool/browser_coverage_policy.json` contain measured floors, distinct from the
98% target. The VM policy also pins the previously measured source inventory:
dropping a difficult file cannot silently improve the package percentage.
`tool/check_coverage.py --require-target` fails while measured files
or unmeasured scopes remain below the complete target.

Raw LLVM LCOV currently includes inline Rust unit-test bodies. It is useful
diagnostic evidence, **not a production-only Rust percentage**, and is never
merged into the Dart badge. A production-only native report, native benchmark
workspace coverage, client/browser coverage, hooks and standalone application
coverage remain work in the active execution plan.

`mutation-report.json` records source/test hashes, the base commit, every generated
mutation, per-mutation outcomes, clean/restored baselines and completion status.
Directory targets resolve to sorted `*_test.dart` paths, recorded as
`resolvedTests` and `testCommand`. Helper files remain in `testHashes`. This
avoids filesystem-dependent fail-fast order; callback-entry tests must also
fail explicitly on premature operation completion rather than wait indefinitely.
Only `complete: true` is finished evidence. The operator inventory is explicit:
binary operators, boolean/condition replacement, negation and null fallback;
statement deletion, constants and other operators are not yet included. No
sample is extrapolated to the full codebase.

The runner changes only an isolated workspace snapshot, executes mutants serially
and kills timed-out process groups. It currently requires POSIX (Linux/macOS)
process groups. Compiler errors are unviable, not kills.
Infrastructure errors and timeouts remain in the score denominator and fail the
gate. An empty, skipped or incomplete baseline fails. Every completed target is
tested again with restored original sources.

Equivalent mutants require individual reasons and matching source hashes in
`tool/mutation_equivalents.json`; changed or stale entries fail validation. The
raw score remains visible alongside the adjusted score. Do not waive survivors
merely to reach a number: add a distinguishing regression or prove equivalence.

## CI Scope

CI enforces Dart VM package floors, core browser floors and the full authorization
and authentication-server AST mutation inventories. It uploads detailed coverage
and mutation artifacts.
The separate, manually dispatched **Mutation Diagnostics** workflow measures
Base64 and MessagePack on VM/Chrome, the MCP production source inventory
(including its router-hosted CLI), and RawSocket on Linux/macOS. The MCP target
has 2,274 mutations at the current checkpoint and a larger workflow execution
budget; it is not a quick smoke test. The workflow deliberately
fails when its unresolved survivors/timeouts fail the target; it is not presented
as an already-green release gate. Native platform-disabled mutants remain in
the raw inventory until they can be assessed against both operating systems.

The active [execution plan](exec-plans/2026-09-15-regression-mutation-coverage.md)
tracks the remaining work and verified results.
