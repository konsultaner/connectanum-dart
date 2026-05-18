# RC Stale Tag Next-Action Safety

Status: complete locally; hosted CI/package evidence pending after push
Started: 2026-05-17
Completed locally: 2026-05-17
Owner: Codex

## Goal

Make the deployment-chain audit safer for RC operations when an existing
GitHub prerelease or selected RC tag does not cover the current
release-sensitive candidate commit. The audit should recommend choosing a fresh
RC tag by default, and should treat retagging an already published RC as an
explicit release-policy decision.

## Scope

- Update `bin/audit-github-deployment-chain` stale-RC guidance.
- Keep the audit read-only; do not create, move, delete, or publish tags or
  releases.
- Bundle the change with current project-state evidence so the commit is not
  docs-only.

## Verification

- `bin/test-fast` passed before changes on 2026-05-17.
- `bash -n bin/audit-github-deployment-chain` passed on 2026-05-17.
- Static stale-wording scan confirmed the old `move or create` and
  `create or move` phrases are gone from the audit script on 2026-05-17.
- Focused audit output inspection showed stale-RC next actions now recommend a
  fresh RC tag and explicitly call retagging a release-policy approval on
  2026-05-17.
- `git diff --check` passed on 2026-05-17.
- Private-name scan on touched public docs/tooling paths passed on 2026-05-17.
- `bin/verify` passed on 2026-05-17.

## Handoff Criteria

- The audit no longer presents moving an already published RC tag as the normal
  next action.
- The docs/state update records the material verification state alongside the
  implementation change.
- Hosted CI/package evidence should refresh after the implementation commit is
  pushed; no native/router image rerun is required unless the hosted audit
  reports release-sensitive inputs changed for those gates.
