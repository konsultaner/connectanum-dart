# RC Stale-Tag Evidence Next Actions

Status: complete

## Context

`bin/audit-github-deployment-chain --show-rc-readiness` now detects when the
selected RC tag, hosted Native Artifacts evidence, and Router Image dry-run tags
do not describe the same candidate. The remaining release-readiness output still
had one confusing edge: when the selected RC tag itself is stale, the native and
router evidence sections told the operator to rerun evidence for that stale tag.

## Plan

- Keep the existing readiness gates and failure behavior unchanged.
- When the selected RC tag does not cover the checked-out release-sensitive
  candidate, make Native Artifacts and Router Image next actions tell the
  operator to create or move the selected RC tag to the checked-out candidate
  first.
- Re-run the focused RC-readiness audit so the stale-tag and evidence-mismatch
  messages describe one coherent release sequence.

## Verification

- `bin/test-fast`
- `bash -n bin/audit-github-deployment-chain`
- `git diff --check`
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --show-native-release-dry-run --show-router-image-dry-run --show-rc-readiness`
- `bin/verify`

Result: all checks passed on 2026-05-14. The focused RC-readiness audit now
prints the corrected stale-tag sequence for both Native Artifacts and Router
Image evidence mismatches.
