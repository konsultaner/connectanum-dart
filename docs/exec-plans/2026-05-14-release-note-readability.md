# Release Note Readability

Status: complete

## Goal

Make generated GitHub release notes clearer for first-RC consumers by stating
what the release contains, whether it is a release candidate or stable release,
and how the native bundles relate to router image tags.

## Scope

- In scope: release-note renderer wording, renderer tests, and stale public
  deployment-guide status text.
- Out of scope: moving tags, publishing releases, changing package publication
  policy, or changing router image publishing semantics.

## Verification

- `bin/test-fast` passed before edits on 2026-05-14.
- `python3 -m unittest tool/test_render_native_release_notes.py tool/test_render_router_image_metadata.py`
  passed.
- `python3 -m py_compile tool/render_native_release_notes.py tool/render_router_image_metadata.py`
  passed.
- Ruby YAML parsing passed for `.github/workflows/native-artifacts.yml` and
  `.github/workflows/router-image.yml`.
- A sample `v0.1.0-rc.1` release-note render showed release-candidate status,
  commit metadata, and matching router image tags.
- `git diff --check` passed.
- `bin/verify` passed on 2026-05-14.

## Remaining

- No implementation work remains for this slice.
