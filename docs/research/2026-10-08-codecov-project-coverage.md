# PR #105 project coverage correction

Date: 2026-10-08. Baseline: `7b530d580faea252a25bdd3104c46128e79323fd`.
Master `3bac4cf5db3b4cd9d51636f8454e6672722007e2` is already integrated.

## Reproduction and scope

PR CI run 37646862109 and push CI run 37646851286 pass. Package dry run
37646871408 and native artifact dry run 37646867603 pass. Codecov check
112916577585 fails: 45,364 / 51,147 lines (88.693%), compared with master's
40,427 / 43,055 (93.896%). Patch coverage passes.

The two compiler-generated WAMP bindings contribute 3,438 executable lines
and 2,709 misses. `tool/check_coverage.py` already classifies these exact files
separately, verifies compiler provenance, and retains their raw coverage.
Mandatory FlatBuffers Binding CI checks pinned regeneration and independent
fixtures. Codecov was receiving raw LCOV without the corresponding exclusions.
Its [documented top-level ignore setting](https://docs.codecov.com/docs/ignoring-paths)
now names those same two files. No other generated or handwritten files are
excluded. Neither local coverage floors nor Codecov's status threshold changes.

## Actual coverage contribution

Eight existing complete suites were missing from VM coverage: copy metrics,
VM FlatBuffers transport profiles, owned segments, native FlatBuffers profiles,
WebSocket network profiles, native FlatBuffers frames, and both router native
FlatBuffers forwarding suites. Router forwarding variants use the same
`CONNECTANUM_FORWARD_NATIVE_PUBLISH=1` environment as `bin/test-all`, in separate
processes/raw report directories. Remote authentication remains isolated.

Actual added-suite runs pass (179 cases total). Merging their LCOV with the
hosted VM artifact adds 171 handwritten line hits with an unchanged denominator:
44,676 / 47,751 (93.560%) becomes 44,847 / 47,751 (93.918%). The combined Codecov
report estimate becomes 44,806 / 47,710 (93.913%), above master's exact ratio.
This is an estimate until the new hosted upload completes; the platform reports
have slightly different executable-line inventories.

## Regression and acceptance evidence

Three new regression methods fail before the launcher/config change: eight
missing suite invocations, two unpropagated simulated suite failures, and the
missing Codecov exclusion scope. Executed launcher probes check complete suites,
distinct raw reports, forwarding environment, correct package working directory,
and exit 73 propagation. The scope test enforces equality with the existing
verified generated-file set. Existing provenance and handwritten-source guards
remain in place.

Fresh unchanged baseline `bin/test-fast` passes at exit 0. Candidate full
verification and hosted Codecov acceptance are pending. This correction does
not close the remaining performance milestone issues or claim benchmark parity.
