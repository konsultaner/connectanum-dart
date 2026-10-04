# Regression And Mutation Testing

The project target is at least 98% executable-line coverage per shipped
component/runtime and at least 95% killed viable, non-equivalent mutations.
**These targets have not been reached repository-wide.** A passing CI job means
that its named scope and current regression floors passed, not that the complete
project has 98% coverage or 95% mutation coverage.

## Commands

Run `bin/test-fast` before substantial changes and `bin/verify` before handoff.
Both include regression tests for the coverage and mutation tooling.
Do not overlap full native verification and VM coverage collection in the same
checkout: they rebuild shared native artifacts and instrumentation output.

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
bin/collect-native-mutations --output out/mutations-rawsocket

# Whole native components: 32 disjoint batches, at most four isolated workers.
bin/collect-native-mutation-campaign --target core-all --batches 32 --jobs 4 \
  --output out/native-core-campaign
# The same command supports --target ffi-all.
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

Raw LLVM LCOV includes inline Rust unit-test bodies and is retained unchanged.
`production.info` and `production.summary.json` remove test/helper-only lines
using source-hash-pinned AST scopes, report unmeasured candidates, and keep each
native component separate. Neither report is merged into the Dart badge.
Native benchmark-workspace coverage and the remaining client/browser, hooks
and standalone application scope remain work in the active execution plan.

The native collector supports complete RawSocket/WAMP/config/protocol candidate
inventories and whole core/FFI production-candidate inventories. It copies the transport workspace and sibling
public TLS fixtures into a private directory, materializes symlinks and pins
source, tooling and log hashes. The auditor checks every outcome against the
inventory, a nonempty clean baseline and an identical restored test inventory.
Only explicit assertions at verified test-only locations count as kills.
Compiler failures, signals, runtime panics, unwrap/expect failures, timeouts and
infrastructure failures remain separate. `audited-results.json` reports raw and
adjusted candidate scores (no native equivalence waivers yet) and operator counts.
Platform-inactive candidates remain visible; these are not platform-active
production scores. A single-batch diagnostic command fails on survivors or
unclean evidence; the combined whole-component audit requires clean evidence
and an unchanged >=95% score gate.

### Faster Native Campaigns

`collect-native-mutation-campaign` runs each batch in a separate source and Cargo
build directory. It limits concurrent workers with `--jobs` and Cargo build
threads per worker with `--cargo-jobs` (default: CPU count divided by workers).
The complete workspace test suite, per-mutant deadlines, assertion-only kill
evidence and source/tool pins are unchanged. Source mutations are still rebuilt;
this does not patch machine code or bypass Cargo's compilation checks.

`campaign-manifest.json` records elapsed time and actual peak worker count;
`combined.json` is written only after every batch's raw logs, clean/restored
baselines and exact inventory union pass audit. Completed collection can still
have a failing mutation gate. SIGINT/SIGTERM cancels owned Cargo process groups
and leaves incomplete evidence without a score. An unresolved inherited stdout
pipe is bounded and reported as an infrastructure failure, never a kill.

Resume into a **fresh** output directory, explicitly selecting completed batches:

```sh
bin/collect-native-mutation-campaign --target core-all --batches 32 --jobs 4 \
  --reuse out/native-core-campaign/batch-0000 \
  --reuse out/native-core-campaign/batch-0001 \
  --output out/native-core-resumed
```

Reused evidence must match source/test/tool/AST hashes, the full inventory and
partition, compiler versions and hashed build configuration. Its raw logs are
reaudited before new workers start. Missing, corrupt, interrupted or differently
partitioned batches are rejected; never overwrite an old batch. Collector-tool
changes invalidate reuse rather than silently relabeling older evidence.

The regression benchmark runs the same eight mutants and complete tests in a
controlled two-crate Cargo fixture with one, two and four workers. It compares
outcomes and records timings without a flaky speed threshold. Fixture speedups
are not production ETAs; cold builds, contention and uneven test runtimes affect
the complete native campaign. Dart/browser campaigns remain serial within each
target; this acceleration does not claim their speed has changed.

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

The Dart runner changes only an isolated workspace snapshot, executes mutants serially
and kills timed-out process groups. It currently requires POSIX (Linux/macOS)
process groups. Compiler errors are unviable, not kills.
Infrastructure errors and timeouts remain in the score denominator and fail the
gate. An empty, skipped or incomplete baseline fails. Every completed target is
tested again with restored original sources.

Equivalent mutants require individual reasons and matching source hashes in
`tool/mutation_equivalents.json`; changed or stale entries fail validation. The
raw score remains visible alongside the adjusted score. Do not waive survivors
merely to reach a number: add a distinguishing regression or prove equivalence.

### Base64 Functional Equivalents

The VM and JavaScript Base64 targets retain all generated candidates. Individual
proofs in `tool/mutation_equivalents.json` are pinned to production source hash
`4fd495def55fdd760f6deb7d3aee714ae47e0eae4087e09f6fe11a7565d59d02`.
The 44 string-decoder proofs cover changed guards that either evaluate identically
or delegate to the same SDK decoder without returning partial output. They do
not waive arithmetic corruption, new accepted invalid characters, or the
byte-decoder candidate `8be0ffb08e2b2f783bc2`.

The relevant invariant is that the custom string path returns only canonical
quartets with zero unused padding bits; all other inputs already delegate to
`base64.decoder.convert(input, start)`. Both paths produce the same octets in
a fresh mutable `Uint8List`. Range validation happens before the changed guards;
the input String is immutable and the intermediate output never escapes.
For each alphabet-mapping proof, all altered values are checked to be invalid
negative sextets caught by every applicable sentinel/negative guard, on both
VM and JavaScript. Positive out-of-range sextets are not equivalent: mixed-class
and invalid-character regressions must distinguish them.

SDK allocation and padding behavior were also inspected in Dart 3.13.1
`lib/convert/base64.dart` (SHA256
`db95fe2459011ca9e8a2478d60b0d133376984687493dfdf0d01b14f7b7669ee`).
Its canonical output allocation is exact-size; invalid and URL-safe input uses
the same SDK call in both versions. Reassess these proofs if that dependency
behavior changes. These are functional equivalences, not performance claims:
an extra SDK fallback can be slower, and mutation scores do not replace the
transport/serializer benchmark evidence.

## CI Scope

CI enforces Dart VM package floors, core browser floors and the full authorization
and authentication-server AST mutation inventories. It uploads detailed coverage
and mutation artifacts.
Base64 VM and JavaScript run their complete inventories in required mutation
jobs at the unchanged 95% assertion-backed gate. Raw and equivalence-adjusted
scores, every outcome and the restored baseline remain in the artifacts.
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
