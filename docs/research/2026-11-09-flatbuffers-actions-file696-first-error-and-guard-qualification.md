# PR #132 adapter first-error correction and guard placement qualification

The private adapter was corrected after a fresh focused regression reproduced the outward-error defect. The same saved harness ran three cases before the edit and the matching three after it. A new private collector draft now has an unconditional entry guard at byte zero, with the complete original collector source preserved as its exact suffix.

| Qualification | Actual result |
| --- | --- |
| BEFORE, original2,234-byte adapter | 3 cases:1 failure,2 passes,0 errors |
| AFTER, corrected2,280-byte adapter | Matching3 cases:3 passes,0 failures,0 errors |
| Guard prefix execution | Refused before the following sentinel |
| Full new source composition | Guard at byte0; original source begins at byte248 and remains byteexact |

These are local Python draft qualification results. The controlled recorder failure is test-only policy evidence, not an actual allocator failure, original Linux/Dart runtime admission, RAM cause or production acceptance result.

## First-error behavior

The first case raises the adapter's real invalid-length `ValueError`. A declared trace hook substitutes a failing recorder in the exposed operation's recorder slot after that primary exception. Original adapter bytes, arguments and case bodies remain unchanged during the BEFORE phase. The failing recorder then raises `ControlledRecorderFailure`.

Before correction, the recorder failure became the outward exception. The two normal error-path controls passed. This one failure and its complete unittest output were saved before the corrected source was written.

The correction adds a preallocated internal primary-error slot, moves registry insertion into the existing protected block, and replaces the fallible exception-list append with assignment to the slot followed by bare raise. External opaque transport fields and input identity checks remain unchanged.

The matching AFTER cases preserve the original outward exception, its original cause/context, the exact input-byte object and owner reference, and the retained primary exception. The controlled faulty recorder is no longer called by error handling. This verifies the declared cases; it does not establish crash completeness or behavior for every possible resource failure.

## Guard placement

The first new input intake selected the original source's leading ordinary imports. The new248-byte guard prefix is placed at byte zero, before those imports and outside the original collector's handlers. It has no environment, receipt, boolean or command-line override.

A fresh prefix-plus-sentinel execution returned the expected `RuntimeError`; the sentinel remained false. Actual prefix line events were2,3,2. The full new source was written and read back bytewise on its original output FD; its suffix is the unchanged80,496,772-byte source input. The full collector was not compiled, imported or executed.

| New private artifact | Bytes | SHA256 |
| --- | ---: | --- |
| Corrected adapter | 2,280 | `4ca2186abf6ae9b3bf0403689c7e8505829356e3d4aa6e95029ca1fe237f6265` |
| Unconditional prefix | 248 | `9d58fc9df5877659a4a51c03ba8871aacb037056434626b1e13fdfcd92b24c46` |
| Guarded full draft | 80,497,020 | `d8cb1a2f4411acb747ec71b68fab75e871e811973dda9f94527297c41af7abcd` |

The new source-writer input was bound to original source SHA256`a57ffdba308c769d8ac5ba2f4b7f119ead53c635844b4b0963f3f8fc20c6a7b9`. That was a new writer-input binding, not a replay of its consumed syntax98777/AST/source-flow question. The original390-byte standalone guard and2,234-byte adapter remain unchanged in their original evidence.

Exact source placement and prefix behavior are qualified within this scope. Original Actions Python compatibility, actual full-collector execution, original credentials, actor FD ownership, generated-output cohort and continuous official physical EX/crash admission remain unqualified.

## Evidence and next boundary

The new local qualification actor was PID82647. Official EX remained held across the BEFORE phase, corrected source write, matching AFTER phase, source composition and prefix execution, with identity verification and fresh1GiB capacity checks. These points are not original driver credentials or a runtime ownership receipt. No native/Dart/Rust build occurred.

The [public assessment](2026-11-09-flatbuffers-actions-file696-first-error-and-guard-qualification-assessment.json) and [selected archive](2026-11-09-flatbuffers-actions-file696-first-error-and-guard-qualification-evidence.tar.gz) contain explicit derived metadata only. Complete original native metadata values, actual ROOT roles, unittest outputs, source bytes, FD/stat-time context, order, duplicates, relationships and nulls remain private and unchanged. Public projection excludes private contexts only.

The original native IO ledger retains the actual FD/stat-time/read-write/close points for both saved unittest outputs. Their helper-return descriptor values were not serialized; those missing original descriptor fields remain unsaved/null and cannot be restored by later observations. Outer tool pipe EOF is also unprovided/null.

The preceding [draft preparation](2026-11-09-flatbuffers-actions-file696-entry-adapter-draft-preparation.md), its six static checks and Qwen61746 timeout remain consumed. No previous case, parser, review, packet, archive, proof or numerical body was replayed; no new model request, fallback, approval or unavailability inference was used.

Next: qualify the actually owned full-context staging/input-loader interface and applicable original-source/known-ledger/SDK/compiler/linker/credentials/actorFD/generatedcohort/continuous physical EX/crash preflight. The corrected adapter is still a private metadata draft; the full-context loader is not installed, and the guarded collector refuses runtime use.

Source20 and the runtime checkout remain untouched. No SDK file-body query, original collector execution, workflow source publication/dispatch, native/driver/broker/profiler/numerical execution, adoption or cleanup occurred. All original full private fields and historical/static nulls remain unchanged; actual new qualification facts are separate. All admission flags remain false and ownership null. RAM repair, own FINAL strict48/50 and clean final production CI remain incomplete; preparation-only skip-ci does not waive final CI.
