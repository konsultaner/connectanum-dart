# RC Evidence Tag Consistency Audit

Status: complete
Owner: Codex
Created: 2026-05-14
Last updated: 2026-05-14

## Goal

Make release-candidate readiness output reject mixed RC evidence, especially a
selected stale RC tag paired with hosted native/router dry-run evidence for a
different RC tag.

## Scope

- In scope: `bin/audit-github-deployment-chain` RC readiness output for native
  release evidence tags and router image dry-run tags.
- Out of scope: choosing the final RC tag, moving existing tags, publishing
  GitHub Releases, or changing pub.dev release-order policy.

## Files Changed

- `bin/audit-github-deployment-chain`
- `docs/project_state.md`
- `docs/exec-plans/2026-05-14-rc-evidence-tag-consistency.md`

## Plan

1. Capture the latest Native Artifacts release evidence tag and mode while
   evaluating hosted native release evidence.
2. Capture Router Image dry-run preview tags while evaluating hosted router
   image evidence.
3. During RC readiness, compare both evidence sets to the selected RC tag and
   print an explicit not-ready finding when they differ.

## Verification

- `bin/test-fast` passed before edits.
- `bash -n bin/audit-github-deployment-chain` passed.
- `git diff --check` passed.
- Focused
  `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --show-rc-readiness --show-required-checks-plan`
  passed and now reports the current mismatch explicitly:
  Native Artifacts evidence is for `v0.1.0-rc.2` while selected RC tag
  `v0.1.0-rc.1` is stale, and Router Image dry-run tags likewise do not
  include `v0.1.0-rc.1`.
- `bin/verify` passed.

## Decision Log

- 2026-05-14: Kept this as a read-only audit hardening change. The script does
  not choose whether to reuse `v0.1.0-rc.1` or move to another RC tag; it only
  ensures all hosted evidence must name the same selected RC tag before the
  audit can be read as coherent.

## Handoff

Implementation is complete locally. The remaining RC blockers are operational:
PR review/merge into `master`, choosing and approving the final RC tag, running
native/router evidence for that same tag, and the intentionally deferred pub.dev
release-order decisions.
