# Explicit RC Tag Audit

Status: complete

## Goal

Let the deployment-chain audit evaluate an intended release-candidate tag
explicitly, so the next RC can be checked without relying on the newest
reachable local RC tag.

## Scope

- In scope: read-only audit behavior, router image manifest fallback tag
  selection, and focused validation for stale and candidate RC tags.
- Out of scope: creating, moving, pushing, or publishing an RC tag or GitHub
  Release.

## Implementation

- `bin/audit-github-deployment-chain` now accepts `--rc-tag <tag>`.
- RC readiness uses the requested tag when provided and reports whether it is
  at `HEAD`, behind release-sensitive changes, missing locally, or not shaped
  like an RC tag.
- Router image visibility fallback also uses the requested RC tag, so a future
  candidate validates the matching GHCR manifest instead of accidentally
  accepting evidence for an older RC.

## Verification

- `bin/test-fast` passed before edits.
- `bash -n bin/audit-github-deployment-chain` passed.
- `bin/audit-github-deployment-chain --help | rg -- '--rc-tag'` passed.
- `bin/audit-github-deployment-chain --branch codex/post-rc-production-readiness --run-limit 1 --show-rc-readiness --rc-tag v0.1.0-rc.1`
  passed and reported the existing RC tag as behind release-sensitive fixes.
- A temporary local `v0.0.0-rc.audit-local` tag at `HEAD` was recognized as the
  requested RC candidate, and the tag was removed after the focused check.
- `bin/verify` passed on 2026-05-13.
