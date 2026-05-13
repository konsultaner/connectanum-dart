# Exec Plan: kTLS Comparison Artifact Readability

Status: completed
Owner: Codex
Created: 2026-04-23
Last updated: 2026-04-23

## Goal

Make the Linux `bin/ktls-http2-bench` artifacts summarize the required-kTLS
performance gap in a way that is directly readable by humans and automation,
then align the checked-in kTLS docs with the current post-secure-WAMP state.

## Scope

- In scope:
  - improve the generated `comparison.json` / `comparison.md` outputs from
    `bin/ktls-http2-bench` so they include aggregate summary findings instead
    of only per-workload rows
  - keep the comparison logic runnable on this macOS host using synthetic
    summary inputs rather than the full Linux-only bench path
  - refresh `docs/ktls_research.md` and `docs/project_state.md` so they point
    at the current remaining kTLS gap instead of stale pre-secure-WAMP next
    steps
  - clean the incidental analyzer info findings introduced by
    `authorization_integration_test.dart` so the branch baseline does not stay
    noisier than the pushed checkpoint
- Out of scope:
  - new kTLS runtime behavior in `ct_core`
  - manual GitHub workflow dispatch or new hosted benchmark claims
  - QUIC / HTTP/3 work

## Files Expected To Change

- `bin/ktls-http2-bench`
- `tool/ktls_http2_compare.py`
- `docs/ktls_research.md`
- `docs/project_state.md`
- `packages/connectanum_router/test/authorization_integration_test.dart`
- `docs/exec-plans/2026-04-23-ktls-comparison-artifact-readability.md`

## Preconditions

- `bin/test-fast` is green before edits. Confirmed on 2026-04-23.
- Hosted GitHub validation is green through commit `c97eff4` on the current
  branch head.

## Plan

1. Improve the kTLS comparison artifact output so it emits an aggregate summary
   section and machine-readable headline findings in addition to per-workload
   rows.
2. Exercise that comparison path locally with synthetic summary inputs and keep
   `bin/ktls-http2-bench` shell-valid.
3. Refresh the kTLS research/state docs and remove the incidental analyzer
   noise in `authorization_integration_test.dart`, then rerun `bin/verify`.

## Verification

- `bin/test-fast`
- `bash -n bin/ktls-http2-bench`
- focused synthetic comparison generation for the updated artifact summary path
- `dart analyze packages/connectanum_router/test/authorization_integration_test.dart`
- `bin/verify`

## Handoff

- Completed on 2026-04-23.
- `bin/ktls-http2-bench` now delegates comparison rendering to
  `tool/ktls_http2_compare.py`, which emits aggregate summary findings in both
  `comparison.json` and `comparison.md` instead of only raw per-workload rows.
- `docs/ktls_research.md` now reflects that secure WAMP coverage is already
  complete and that the remaining kTLS gap is readable performance evidence,
  not missing benchmark surface area.
- `packages/connectanum_router/test/authorization_integration_test.dart` is
  back to an analyzer-clean shape after the earlier worker-auth slice.
