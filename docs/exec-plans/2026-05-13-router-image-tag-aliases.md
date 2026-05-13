# Exec Plan: router-image-tag-aliases

Status: complete
Owner: Codex
Created: 2026-05-13
Last updated: 2026-05-13

## Goal

Make future router image tag-push releases produce predictable RC and stable
image tags by publishing both the exact Git tag form and the normalized semver
form for `v*` refs.

## Scope

- In scope: router image metadata generation, focused unit coverage, and
  release-chain state updates.
- Out of scope: publishing a new router image, changing GHCR package settings,
  or changing the existing `v0.1.0-rc.1` artifacts.

## Files Expected To Change

- `tool/render_router_image_metadata.py`
- `tool/test_render_router_image_metadata.py`
- `docs/project_state.md`

## Preconditions

- `bin/test-fast` must pass before changing release-chain metadata behavior.

## Plan

1. Confirm the fast suite is green.
2. Update tag-push metadata so a Git tag such as `v0.1.0-rc.1` publishes
   `:v0.1.0-rc.1` and `:0.1.0-rc.1`.
3. Keep stable semver aliases for `vX.Y.Z` tags: `:X.Y`, `:X`, and `:latest`.
4. Run focused metadata tests, full verification, then push and inspect hosted
   CI/audit evidence if the implementation commit is published.

## Verification

- `bin/test-fast`
- `python3 -m py_compile tool/render_router_image_metadata.py tool/test_render_router_image_metadata.py`
- `python3 tool/test_render_router_image_metadata.py`
- `bin/verify`

## Decision Log

- 2026-05-13: The current RC image evidence is visible at
  `ghcr.io/konsultaner/connectanum-router:v0.1.0-rc.1`, while the tag-push
  metadata path normalized `v*` refs to only the non-`v` semver image tag.
  Publishing both forms avoids ambiguity for the next RC/stable tag without
  removing conventional semver aliases.

## Handoff

- `tool/render_router_image_metadata.py` now emits both the exact `v*` Git tag
  and the normalized semver image tag for tag-push releases.
- Stable `vX.Y.Z` tag pushes still emit `:X.Y`, `:X`, and `:latest`.
- Verified locally with `bin/test-fast`, Python syntax compilation, focused
  router image metadata tests, a sample `v0.1.0-rc.1` render, and full
  `bin/verify`.
- Hosted GitHub CI #25814049258 passed for `7215164`; the branch audit with
  clean latest CI/log requirements and router package visibility also passed,
  detecting the router image through the public GHCR registry manifest.
