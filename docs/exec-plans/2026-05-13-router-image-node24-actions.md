# Router Image Node 24 Actions

Status: in progress

## Goal

Keep the Router Image deployment chain warning-clean by removing the future
Node.js runtime deprecation annotation emitted by Docker setup action `v3`.

## Scope

- In scope: update Router Image workflow setup actions to the current Docker
  action major that declares Node 24 support, then validate the workflow and
  dry-run audit path.
- Out of scope: changing image tags, publishing images, creating RC tags, or
  changing Docker build/publish semantics.

## Implementation

- `.github/workflows/router-image.yml` now uses
  `docker/setup-qemu-action@v4` and `docker/setup-buildx-action@v4`.
- GitHub release metadata reports `v4.0.0` as the latest release for both
  actions, and both `action.yml` files declare `runs.using: node24`.

## Verification

- `bin/test-fast` passed before edits.
- `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/router-image.yml')"`
  passed.
- `git diff --check` passed.
- `bin/verify` passed on 2026-05-13.
- Hosted CI, hosted Router Image dry-run, and final deployment-chain audit are
  pending after push.
