# Native Release Router Image Tags

Status: complete

## Goal

Make native GitHub Release notes tell users which router image tags belong to a
project release, instead of only naming the GHCR package.

## Scope

- In scope: native release-note rendering, focused unit coverage, and a sample
  `v0.1.0-rc.1` release-note render.
- Out of scope: publishing or editing an existing GitHub Release, changing the
  router image workflow, or changing existing GHCR tags.

## Implementation

- `tool/render_native_release_notes.py` now reuses the router image metadata
  resolver for `v*` project release tags.
- Project release notes list the exact Git tag image alias and normalized
  semver alias for prereleases such as `v0.1.0-rc.1`.
- Stable project release notes also list stable semver convenience aliases
  such as `:X.Y`, `:X`, and `:latest`.
- Standalone `ct-ffi-v*` native-bundle release notes continue to state that no
  router image tag is implied and that router images are released separately.

## Verification

- `bin/test-fast` passed before edits.
- `python3 -m py_compile tool/render_native_release_notes.py tool/test_render_native_release_notes.py`
  passed.
- `python3 tool/test_render_native_release_notes.py` passed.
- A sample `v0.1.0-rc.1` release-note render listed both
  `ghcr.io/konsultaner/connectanum-router:v0.1.0-rc.1` and
  `ghcr.io/konsultaner/connectanum-router:0.1.0-rc.1`.
- `bin/verify` passed on 2026-05-13.
- Hosted GitHub CI #25816244654 passed for `4634831`; the branch audit with
  clean latest CI/log requirements and router package visibility also passed,
  detecting the router image through the public GHCR registry manifest.
